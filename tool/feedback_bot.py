#!/usr/bin/env python3
"""Feedback bot for PilzBuddy.

Reads unprocessed rows from the Supabase `feedback` table and
- creates a GitHub issue for every feature request,
- opens one pull request adding all requested mushroom species to
  lib/core/mushroom_species.dart (group guessed from the name; the
  maintainer accepts by merging or rejects by closing the PR),
then stamps the rows with processed_at.

On the same two-hourly tick it also keeps `public.error_reports` visible
(one issue per ISO week) and prunes it. Both live here rather than in their
own workflow: the schedule, the service_role key and the GitHub token are
already in place, and `error_reports` deliberately has no select policy, so
whatever reads it needs that key anyway.

Required environment: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GH_TOKEN
(the workflow provides these). Self-tests without any network access:
    python3 tool/feedback_bot.py --test-insert "Violetter Lacktrichterling"
    python3 tool/feedback_bot.py --test-digest
    python3 tool/feedback_bot.py --test-sweep

Eine vergangene Woche nachträglich ansehen (liest nur, schreibt nichts —
die Rohdaten liegen 90 Tage):
    python3 tool/feedback_bot.py --digest-week 2026-W30
"""
import json
import os
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

SPECIES_FILE = "lib/core/mushroom_species.dart"
PUBSPEC = "pubspec.yaml"

# Suffix/keyword heuristics mapping a German species name to its group.
# Order matters: "stäubling" must match before the "täubling" substring.
GROUP_RULES = [
    (("bovist", "stäubling"), "_bov"),
    (("röhrling", "rotkappe", "birkenpilz", "steinpilz", "marone",
      "ziegenlippe", "hexenröhrling"), "_roe"),
    (("pfifferling", "leistling", "trompete"), "_lei"),
    (("champignon", "egerling"), "_cha"),
    (("schirmling", "parasol", "tintling"), "_sch"),
    (("knollenblätterpilz", "wulstling", "fliegenpilz", "pantherpilz"), "_wul"),
    (("täubling", "reizker", "milchling"), "_tae"),
    # "verpel" and "becherling" are morel relatives without "morchel" in the
    # name — without them "Böhmische Verpel" fell through to _son and got a
    # grey gilled-mushroom icon (#153).
    (("morchel", "lorchel", "verpel", "becherling"), "_mor"),
    (("porling", "seitling", "judasohr", "zunderschwamm", "stachelbart"), "_bau"),
]

# Species names must be plain German words — anything else becomes an issue.
NAME_RE = re.compile(r"^[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\- ]{2,59}$")


def group_for(name: str) -> str:
    lower = name.lower()
    for keywords, group in GROUP_RULES:
        if any(k in lower for k in keywords):
            return group
    return "_son"


def existing_species(content: str) -> set[str]:
    return {m.lower() for m in re.findall(r"KnownSpecies\('([^']+)'", content)}


def insert_species(content: str, additions: list[tuple[str, str]]) -> str:
    """Insert (name, group) pairs right before the closing ']' of kBekannteArten."""
    start = content.index("kBekannteArten")
    end = content.index("];", start)
    lines = "".join(
        f"  KnownSpecies('{name}', {group}), // via In-App-Wunsch\n"
        for name, group in additions
    )
    return content[:end] + lines + content[end:]


def bump_pubspec(content: str) -> tuple[str, str]:
    m = re.search(r"^version: (\d+)\.(\d+)\.(\d+)\+(\d+)$", content, re.M)
    major, minor, patch, build = (int(g) for g in m.groups())
    new_version = f"{major}.{minor}.{patch + 1}+{build + 1}"
    return content[: m.start()] + f"version: {new_version}" + content[m.end():], new_version


def run(*cmd: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        # Surface the actual error in the workflow log before failing.
        print(f"::error::Command failed: {' '.join(cmd)}\n{result.stderr}",
              file=sys.stderr)
        raise subprocess.CalledProcessError(result.returncode, cmd)
    return result.stdout.strip()


def issue_exists(title: str) -> bool:
    out = run("gh", "issue", "list", "--state", "all", "--limit", "100",
              "--search", title, "--json", "title")
    return any(item["title"] == title for item in json.loads(out or "[]"))


def api(method: str, path: str, body=None):
    url = os.environ["SUPABASE_URL"] + path
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {"apikey": key, "Content-Type": "application/json"}
    # Legacy service_role keys are JWTs and additionally go into the
    # Authorization header; new sb_secret_* keys must only use apikey.
    if key.startswith("eyJ"):
        headers["Authorization"] = f"Bearer {key}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request) as response:
        text = response.read().decode()
        return json.loads(text) if text else None


def mark_processed(row_ids: list[str]) -> None:
    if not row_ids:
        return
    now = datetime.now(timezone.utc).isoformat()
    api("PATCH", f"/rest/v1/feedback?id=in.({','.join(row_ids)})",
        {"processed_at": now})


# The privacy policy promises error reports are cleaned up regularly, so
# something has to actually do it. This runs on the existing two-hourly cron
# rather than pg_cron: no extension to enable, no second schedule, and the
# service_role key is already here.
ERROR_REPORT_RETENTION_DAYS = 90

# Woran ein Frame im eigenen Code zu erkennen ist.
APP_FRAME = "package:pilzbuddy/"


def top_frame(stack: str | None) -> str | None:
    """The one line of a stack trace worth putting in the digest.

    Prefers the topmost frame inside our own code: a Dart stack almost
    always starts in the framework, and `#0 List.reduce` says nothing about
    which of our widgets got there. Without such a frame the topmost of any
    kind will do — an ANR thread dump has no other kind.

    Warum überhaupt: Bis hierhin zeigte der Digest nur Typ und Meldung. In
    KW30 standen dort 61-mal `Infinity or NaN toInt` — eine Woche lang,
    ohne dass jemand sagen konnte, aus welcher Datei. Der Stack lag die
    ganze Zeit in der Tabelle.
    """
    if not stack:
        return None
    lines = [line.strip() for line in stack.splitlines() if line.strip()]
    for line in lines:
        if APP_FRAME in line:
            return line[:200]
    for line in lines:
        if line.startswith("#") or " pc " in line:
            return line[:200]
    return None


def digest_body(rows: list[dict], week: str) -> str:
    """Group error reports by (context, error_type) into an issue body.

    Grouped here rather than in the query because PostgREST has no GROUP BY.
    """
    groups: dict[tuple[str, str], dict] = {}
    for row in rows:
        key = (row.get("context") or "?", row.get("error_type") or "?")
        group = groups.setdefault(key, {
            "count": 0, "versions": set(), "platforms": set(), "example": "",
            "frame": "",
        })
        group["count"] += 1
        if row.get("app_version"):
            group["versions"].add(row["app_version"])
        if row.get("platform"):
            group["platforms"].add(row["platform"])
        if not group["example"] and row.get("message"):
            group["example"] = row["message"].strip().replace("\n", " ")[:200]
        frame = top_frame(row.get("stack"))
        # Ein Frame aus unserem Code sticht einen aus dem Framework, auch
        # wenn er später kommt: Von zehn Zeilen derselben Gruppe trägt oft
        # nur eine überhaupt einen Stack, der bis zu uns reicht.
        if frame and (not group["frame"] or (APP_FRAME in frame
                                             and APP_FRAME not in group["frame"])):
            group["frame"] = frame

    ranked = sorted(groups.items(), key=lambda kv: -kv[1]["count"])
    lines = [
        f"{len(rows)} caught errors reached `public.error_reports` in {week}.",
        "",
        "These are errors the app **survived** — the user saw a snackbar and "
        "carried on. Android Vitals never sees them, and neither does anyone "
        "else unless it is written down here.",
        "",
        "Each group below shows its message and, where the stack reaches our "
        "own code, the topmost frame in it. Rows stay in the table for "
        f"{ERROR_REPORT_RETENTION_DAYS} days, so any past week can be "
        "re-rendered from them: "
        "`python3 tool/feedback_bot.py --digest-week " + week + "`.",
        "",
        "| # | Context | Type | Versions | Platforms |",
        "|--:|---|---|---|---|",
    ]
    for (context, error_type), group in ranked:
        lines.append(
            f"| {group['count']} | {context} | `{error_type}` | "
            f"{', '.join(sorted(group['versions'])) or '–'} | "
            f"{', '.join(sorted(group['platforms'])) or '–'} |"
        )
    lines.append("")
    for (context, error_type), group in ranked:
        if not group["example"] and not group["frame"]:
            continue
        lines.append(f"**{context} · {error_type}**")
        if group["example"]:
            lines.append(f"> {group['example']}")
        if group["frame"]:
            lines.append("")
            lines.append(f"`{group['frame']}`")
        lines.append("")
    lines.append("_Automatically created by the feedback bot; "
                 "updated in place while the week runs. Close when triaged._")
    return "\n".join(lines)


# Formatted with a literal Z instead of isoformat(): the "+00:00" an aware
# datetime produces would be read as a space in a query string.
def _stamp(when: datetime) -> str:
    return when.strftime("%Y-%m-%dT%H:%M:%SZ")


def week_bounds(week: str) -> tuple[datetime, datetime]:
    """Monday 00:00 UTC and the Monday after, for an ISO week label."""
    match = re.fullmatch(r"(\d{4})-W(\d{1,2})", week)
    if not match:
        raise SystemExit(f"Not an ISO week label: {week} (expected 2026-W30)")
    start = datetime.fromisocalendar(
        int(match.group(1)), int(match.group(2)), 1).replace(tzinfo=timezone.utc)
    return start, start + timedelta(days=7)


def fetch_error_rows(start: datetime, end: datetime) -> list[dict]:
    return api(
        "GET",
        f"/rest/v1/error_reports?created_at=gte.{_stamp(start)}"
        f"&created_at=lt.{_stamp(end)}"
        "&select=context,error_type,message,stack,app_version,platform,created_at"
        "&order=created_at",
    ) or []


def print_past_digest(week: str) -> None:
    """Render a past week to stdout. Reads only — touches no issue."""
    start, end = week_bounds(week)
    rows = fetch_error_rows(start, end)
    if not rows:
        print(f"No error reports in {week} "
              f"(rows older than {ERROR_REPORT_RETENTION_DAYS} days are purged).")
        return
    print(digest_body(rows, week))


def report_error_digest() -> None:
    """One issue per ISO week, rewritten in place on every two-hourly tick.

    Rewritten rather than commented on: 84 comments a week would bury the
    numbers instead of showing them. No errors means no issue — nothing to
    report is not worth an issue.
    """
    year, week_no, _ = datetime.now(timezone.utc).isocalendar()
    week = f"{year}-W{week_no:02d}"
    rows = fetch_error_rows(*week_bounds(week))
    if not rows:
        print(f"No error reports in {week}.")
        return

    title = f"Error reports {week}"
    body = digest_body(rows, week)
    # Label idempotent anlegen — gh issue create scheitert an einem
    # unbekannten Label.
    subprocess.run(["gh", "label", "create", "ops", "--color", "5319E7",
                    "--description", "Betrieb, Monitoring, Backups"],
                   capture_output=True, text=True)

    existing = json.loads(run("gh", "issue", "list", "--state", "open",
                              "--label", "ops", "--limit", "50",
                              "--json", "number,title") or "[]")
    match = next((i for i in existing if i["title"] == title), None)
    if match:
        run("gh", "issue", "edit", str(match["number"]), "--body", body)
        print(f"Error digest updated: {title} ({len(rows)} reports)")
    else:
        run("gh", "issue", "create", "--title", title, "--body", body,
            "--label", "ops")
        print(f"Error digest created: {title} ({len(rows)} reports)")


def purge_error_reports() -> None:
    cutoff = _stamp(datetime.now(timezone.utc)
                    - timedelta(days=ERROR_REPORT_RETENTION_DAYS))
    # The filter is what keeps this from emptying the table.
    api("DELETE", f"/rest/v1/error_reports?created_at=lt.{cutoff}")
    print(f"Purged error reports older than {ERROR_REPORT_RETENTION_DAYS} days.")


# Fundfotos (#532, Patch 026): Zeilen laufen nach 14 Tagen ab, die Bytes
# liegen im Bucket `find-photos`. Beides räumt derselbe Tick ab — per
# ABGLEICH, nicht per Reihenfolge: Jedes Objekt, zu dem keine lebende
# Zeile mehr gehört, fliegt. Das fängt drei Fälle mit einem Griff:
# abgelaufene Zeilen, gelöschte Zeilen (Cascade über Fund, Spot oder
# Konto) und Uploads, deren Zeile nie geschrieben wurde (Netz weg
# zwischen Objekt und Zeile). Eine Reihenfolge „erst Zeile, dann Objekt"
# ließe den dritten Fall für immer liegen.
FIND_PHOTO_BUCKET = "find-photos"
# Ein Objekt, das jünger ist als das, gilt als „im Aufbau": hochgeladen,
# die Zeile folgt gleich. Ohne die Schonfrist löschte ein Tick, der
# zwischen die beiden Schritte fällt, ein Foto mitten im Teilen.
PHOTO_ORPHAN_GRACE = timedelta(hours=1)


def photo_key_of(path: str) -> str:
    """`<uid>/<id>.jpg` und `<uid>/<id>_s.jpg` gehören zum Schlüssel `<uid>/<id>`."""
    if path.endswith("_s.jpg"):
        return path[:-6]
    if path.endswith(".jpg"):
        return path[:-4]
    return path


def photo_sweep_plan(live_keys: set[str], objects: list[tuple[str, datetime | None]],
                     now: datetime) -> list[str]:
    """Welche Objekte weg müssen: ohne lebende Zeile — und nicht ganz frisch.

    Rein, damit der Selbsttest sie ohne Netz prüfen kann. `created` ist
    None, wenn der Dienst keine Zeit meldet; dann gilt das Objekt als alt —
    ein Objekt ohne Zeile UND ohne Alter ist keines, das jemand gerade
    hochlädt."""
    doomed = []
    for path, created in objects:
        if photo_key_of(path) in live_keys:
            continue
        if created is not None and now - created < PHOTO_ORPHAN_GRACE:
            continue
        doomed.append(path)
    return doomed


def _parse_ts(value) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def _storage_list(bucket: str, prefix: str) -> list[dict]:
    return api("POST", f"/storage/v1/object/list/{bucket}",
               {"prefix": prefix, "limit": 1000, "offset": 0}) or []


def list_bucket_objects(bucket: str) -> list[tuple[str, datetime | None]]:
    """Alle Objekte mit Pfad und Erstellzeit.

    Die Liste antwortet je EBENE: Auf der obersten stehen die Ordner (ein
    Eintrag ohne `id`), darin die Dateien mit ihrem Namen ohne Ordner. Ein
    Ordner je Nutzer, also ein Aufruf je Nutzer plus einer."""
    out: list[tuple[str, datetime | None]] = []
    for entry in _storage_list(bucket, ""):
        if entry.get("id") is None:
            folder = entry["name"]
            for obj in _storage_list(bucket, folder):
                if obj.get("id") is None:
                    continue
                out.append((f"{folder}/{obj['name']}", _parse_ts(obj.get("created_at"))))
        else:
            out.append((entry["name"], _parse_ts(entry.get("created_at"))))
    return out


def sweep_find_photos() -> None:
    now = datetime.now(timezone.utc)
    api("DELETE", f"/rest/v1/find_photos?expires_at=lt.{now.isoformat()}")
    live = {row["key"] for row in (api("GET", "/rest/v1/find_photos?select=key") or [])}
    objects = list_bucket_objects(FIND_PHOTO_BUCKET)
    doomed = photo_sweep_plan(live, objects, now)
    if doomed:
        api("DELETE", f"/storage/v1/object/{FIND_PHOTO_BUCKET}", {"prefixes": doomed})
    print(f"Fundfotos: {len(live)} Zeilen, {len(objects)} Objekte, {len(doomed)} entfernt.")


FEEDBACK_PHOTO_BUCKET = "feedback-photos"
# Dieselbe Lizenz wie `kGalleryPhotoLicence` in der App (Patch 034).
GALLERY_PHOTO_LICENCE = "CC BY-SA 4.0"


def dashboard_bucket_url(bucket: str) -> str:
    """Der Bucket im Dashboard — den Link öffnet nur, wer dort angemeldet ist."""
    ref = os.environ.get("SUPABASE_URL", "").split("//")[-1].split(".")[0]
    return f"https://supabase.com/dashboard/project/{ref}/storage/buckets/{bucket}"


def feedback_photo_names(row: dict) -> list[str]:
    """Die Dateinamen der Bilder einer Zeile — ohne Ordner.

    Neue Clients schreiben `photo_paths` (Patch 033, bis zu drei), die
    Clients 1.186.0–1.195.x weiter `photo_path`. Beide werden gelesen;
    steht (warum auch immer) beides da, zählt jedes Bild einmal."""
    paths = list(row.get("photo_paths") or [])
    if row.get("photo_path") and row["photo_path"] not in paths:
        paths.insert(0, row["photo_path"])
    return [p.rsplit("/", 1)[-1] for p in paths]


def feedback_issue_body(row: dict, username: str) -> str:
    """Der Text des Issues.

    Die App-Version (#358) steht dabei, wenn sie da ist; alte Zeilen und
    ältere Clients haben sie nicht, und dann steht sie eben nicht da,
    statt geraten zu werden.

    Ein Bild (#525) wird NICHT verlinkt und nicht angehängt — das Issue
    ist öffentlich, der Bucket nicht. Genannt wird nur der Dateiname;
    der Ordner ist die Nutzer-id, und die gehört so wenig ins Issue wie
    das Bild. Wer nachsehen will, öffnet den Bucket im Dashboard und
    sucht den Namen."""
    version = row.get("app_version")
    aus = f" aus Version {version}" if version else ""
    names = feedback_photo_names(row)
    bild = ""
    if names:
        liste = ", ".join(f"`{n}`" for n in names)
        was = ("Ein Bild ist angehängt" if len(names) == 1
               else f"{len(names)} Bilder sind angehängt")
        # Die Einwilligung (Patch 034) hält HIER den Namen fest, der
        # genannt werden darf — das Issue bleibt, auch wenn sich der
        # Melder später umbenennt. Ohne Haken steht das Gegenteil
        # ausdrücklich da: Wer übernimmt, soll nicht raten müssen.
        if row.get("photo_consent"):
            freigabe = (
                f"\n\n✅ Für die Artgalerie freigegeben: selbst aufgenommen, "
                f"{GALLERY_PHOTO_LICENCE}, Urheber **{username}** "
                f"(am {row['created_at'][:10]}). Übernommen wird erst nach Ansicht."
            )
        else:
            freigabe = "\n\n🚫 Nicht für die Artgalerie freigegeben."
        bild = (
            f"\n\n📎 {was} — nicht öffentlich, nur im Bucket "
            f"`{FEEDBACK_PHOTO_BUCKET}` als {liste} "
            f"({dashboard_bucket_url(FEEDBACK_PHOTO_BUCKET)}); "
            f"wird nach {ERROR_REPORT_RETENTION_DAYS} Tagen gelöscht."
            f"{freigabe}"
        )
    return (
        f"> {row['message']}\n\n"
        f"Eingereicht in der App von **{username}**{aus} "
        f"am {row['created_at'][:10]}.{bild}\n\n"
        f"_Automatisch erstellt vom Feedback-Bot._"
    )


def feedback_photo_sweep_plan(objects: list[tuple[str, datetime | None]],
                              now: datetime) -> list[str]:
    """Feedback-Bilder älter als die Fehlerbericht-Frist — rein, für den Selbsttest.

    Ohne Erstellzeit bleibt ein Objekt stehen: Die Liste liefert sie
    immer, und ein Sonderfall, der löscht, ist der falsche Sonderfall."""
    cutoff = now - timedelta(days=ERROR_REPORT_RETENTION_DAYS)
    return [path for path, created in objects if created is not None and created < cutoff]


def sweep_feedback_photos() -> None:
    now = datetime.now(timezone.utc)
    objects = list_bucket_objects(FEEDBACK_PHOTO_BUCKET)
    doomed = feedback_photo_sweep_plan(objects, now)
    if doomed:
        api("DELETE", f"/storage/v1/object/{FEEDBACK_PHOTO_BUCKET}", {"prefixes": doomed})
    print(f"Feedback-Bilder: {len(objects)} Objekte, {len(doomed)} entfernt.")


def main() -> None:
    # Before the early return below — otherwise digest and purge would only
    # ever run on the rare tick that also has unprocessed feedback.
    report_error_digest()
    purge_error_reports()
    # Ein Aussetzer des Storage-Dienstes darf die Issues nicht aufhalten:
    # Der nächste Tick räumt nach, die Zeilen laufen ohnehin ab.
    try:
        sweep_find_photos()
        sweep_feedback_photos()
    except Exception as e:  # noqa: BLE001 — jede Ursache ist hier gleich
        print(f"::warning::Bilder nicht abgeräumt: {e}")

    rows = api(
        "GET",
        "/rest/v1/feedback?processed_at=is.null&order=created_at"
        "&select=id,type,message,species_name,created_at,app_version,photo_path,photo_paths,photo_consent,profiles(username)",
    )
    if not rows:
        print("No unprocessed feedback.")
        return

    species_ids: list[str] = []
    species_additions: list[tuple[str, str]] = []
    species_authors: list[str] = []

    with open(SPECIES_FILE, encoding="utf-8") as f:
        species_content = f.read()
    known = existing_species(species_content)

    for row in rows:
        username = (row.get("profiles") or {}).get("username") or "unbekannt"
        name = (row.get("species_name") or "").strip()
        is_species = row["type"] == "species" and NAME_RE.match(name)

        if is_species:
            if name.lower() in known:
                print(f"Skip (already known): {name}")
                mark_processed([row["id"]])
            else:
                species_additions.append((name, group_for(name)))
                bild = " — mit Bild im Bucket" if feedback_photo_names(row) else ""
                species_authors.append(f"{name} (von {username}){bild}")
                known.add(name.lower())
                species_ids.append(row["id"])
        else:
            is_bug = row["type"] == "bug"
            prefix = "Bug report: " if is_bug else "Feature request: "
            label = "bug" if is_bug else "enhancement"
            title = row["message"].strip().replace("\n", " ")
            title = prefix + title[:60] + ("…" if len(title) > 60 else "")
            if issue_exists(title):
                print(f"Skip (issue already exists): {title}")
            else:
                # Aus welchem Stand die Meldung kam (#358). Ohne die
                # Angabe war bei einer Feldmeldung nicht entscheidbar, ob
                # sie ein Duplikat einer schon behobenen ist oder ein
                # neuer Fehler im frischen Stand — die Frage musste beim
                # Melder zurückgestellt werden. Alte Zeilen und ältere
                # Clients haben sie nicht; dann steht sie eben nicht da,
                # statt geraten zu werden.
                body = feedback_issue_body(row, username)
                issue_url = run("gh", "issue", "create", "--title", title,
                                "--body", body, "--label", label)
                print(f"Issue created [{label}]: {title}")
                # Issues created with GITHUB_TOKEN do not emit workflow
                # triggers — dispatch the Claude triage explicitly.
                issue_number = issue_url.rstrip("/").rsplit("/", 1)[-1]
                try:
                    run("gh", "workflow", "run", "claude-issue-triage.yml",
                        "-f", f"issue_number={issue_number}")
                    print(f"Triage dispatched for #{issue_number}")
                except subprocess.CalledProcessError:
                    print(f"::warning::Could not dispatch triage for #{issue_number}")
            # Stamp each row right away so a later crash never duplicates it.
            mark_processed([row["id"]])

    if species_additions:
        new_species = insert_species(species_content, species_additions)
        with open(SPECIES_FILE, "w", encoding="utf-8") as f:
            f.write(new_species)
        with open(PUBSPEC, encoding="utf-8") as f:
            pubspec, new_version = bump_pubspec(f.read())
        with open(PUBSPEC, "w", encoding="utf-8") as f:
            f.write(pubspec)

        branch = "bot/species-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        names = ", ".join(n for n, _ in species_additions)
        run("git", "config", "user.name", "github-actions[bot]")
        run("git", "config", "user.email",
            "github-actions[bot]@users.noreply.github.com")
        run("git", "checkout", "-b", branch)
        run("git", "add", SPECIES_FILE, PUBSPEC)
        run("git", "commit", "-m", f"feat: add requested species: {names}")
        run("git", "push", "origin", branch)
        pr_body = (
            "Requested in-app via the feedback form:\n\n"
            + "\n".join(f"- {line}" for line in species_authors)
            + f"\n\nVersion bumped to {new_version} — **merging releases "
            "automatically**; close the PR to reject.\n\n"
            "_Automatically created by the feedback bot._"
        )
        run("gh", "pr", "create", "--base", "main", "--head", branch,
            "--title", f"feat: add requested species: {names}", "--body", pr_body)
        # PRs created with GITHUB_TOKEN do not trigger CI automatically —
        # dispatch it explicitly so the required checks appear on the PR.
        run("gh", "workflow", "run", "ci.yml", "--ref", branch)
        print(f"Species PR created for: {names}")
        mark_processed(species_ids)

    print("Done.")


def self_test(names: list[str]) -> None:
    with open(SPECIES_FILE, encoding="utf-8") as f:
        content = f.read()
    known = existing_species(content)
    additions = []
    for name in names:
        assert NAME_RE.match(name), f"Name would be routed to an issue: {name}"
        if name.lower() in known:
            print(f"already known: {name}")
            continue
        additions.append((name, group_for(name)))
    updated = insert_species(content, additions)
    for name, group in additions:
        line = f"KnownSpecies('{name}', {group}), // via In-App-Wunsch"
        assert line in updated, line
        print(f"insert ok: {name} -> {group}")
    with open(PUBSPEC, encoding="utf-8") as f:
        _, version = bump_pubspec(f.read())
    print(f"pubspec bump ok -> {version}")
    print("self-test passed (no files were written)")


def self_test_sweep() -> None:
    """Der Abgleich, ohne Netz: was fliegt, was bleibt."""
    now = datetime(2026, 9, 22, 12, 0, tzinfo=timezone.utc)
    old = now - timedelta(days=2)
    fresh = now - timedelta(minutes=5)
    live = {"u1/a", "u2/b"}
    objects = [
        ("u1/a.jpg", old), ("u1/a_s.jpg", old),      # lebende Zeile: bleibt
        ("u2/b.jpg", old), ("u2/b_s.jpg", None),     # dito, auch ohne Zeit
        ("u1/x.jpg", old), ("u1/x_s.jpg", old),      # Zeile weg: fliegt
        ("u3/y.jpg", fresh),                          # im Aufbau: bleibt
        ("u3/z_s.jpg", None),                         # ohne Zeile, ohne Zeit: fliegt
    ]
    doomed = photo_sweep_plan(live, objects, now)
    assert doomed == ["u1/x.jpg", "u1/x_s.jpg", "u3/z_s.jpg"], doomed
    assert photo_key_of("u/k_s.jpg") == "u/k" and photo_key_of("u/k.jpg") == "u/k"
    assert _parse_ts("2026-09-22T10:00:00.000Z") == datetime(2026, 9, 22, 10, tzinfo=timezone.utc)
    assert _parse_ts(None) is None and _parse_ts("kaputt") is None

    # Feedback-Bilder: nur die alten fliegen, ohne Zeit bleibt es stehen.
    stale = now - timedelta(days=ERROR_REPORT_RETENTION_DAYS + 1)
    keep = now - timedelta(days=ERROR_REPORT_RETENTION_DAYS - 1)
    plan = feedback_photo_sweep_plan(
        [("u/a.jpg", stale), ("u/b.jpg", keep), ("u/c.jpg", None)], now)
    assert plan == ["u/a.jpg"], plan

    # Das Issue nennt das Bild ohne Pfad und ohne Nutzer-id.
    os.environ.setdefault("SUPABASE_URL", "https://abcdefgh.supabase.co")
    row = {"message": "Hut ist rot", "created_at": "2026-09-22T10:00:00Z",
           "app_version": "1.186.0", "photo_path": "1234-uid/deadbeef.jpg"}
    body = feedback_issue_body(row, "waldfee")
    assert "`deadbeef.jpg`" in body, body
    assert "1234-uid" not in body, body
    assert "storage/buckets/feedback-photos" in body, body
    assert "aus Version 1.186.0" in body, body
    # Drei Bilder (Patch 033): alle Namen, keiner mit Ordner.
    many = {**row, "photo_path": None,
            "photo_paths": ["1234-uid/a1.jpg", "1234-uid/b2.jpg", "1234-uid/c3.jpg"]}
    body = feedback_issue_body(many, "waldfee")
    assert "3 Bilder sind angehängt" in body, body
    assert "`a1.jpg`, `b2.jpg`, `c3.jpg`" in body, body
    assert "1234-uid" not in body, body
    # Beide Spalten gefüllt: jedes Bild einmal.
    both = {**row, "photo_paths": ["1234-uid/deadbeef.jpg", "1234-uid/x.jpg"]}
    assert feedback_photo_names(both) == ["deadbeef.jpg", "x.jpg"], feedback_photo_names(both)
    # Einwilligung (Patch 034): Name, Lizenz, Datum — und ohne Haken das
    # ausdrückliche Nein.
    assert "Nicht für die Artgalerie freigegeben" in body, body
    ok = feedback_issue_body({**many, "photo_consent": True}, "waldfee")
    assert "✅ Für die Artgalerie freigegeben" in ok, ok
    assert "CC BY-SA 4.0, Urheber **waldfee** (am 2026-09-22)" in ok, ok
    assert "Nicht für die Artgalerie" not in ok, ok
    plain = feedback_issue_body({"message": "x", "created_at": "2026-09-22"}, "w")
    assert "📎" not in plain and "aus Version" not in plain, plain
    assert "Artgalerie" not in plain, plain
    print("sweep self-test passed (no network, nothing written)")


def self_test_digest() -> None:
    """Grouping and body rendering without any network access."""
    framework_stack = (
        "#0      List.reduce (dart:core/list.dart:120:5)\n"
        "#1      _Chart.build (package:flutter/src/widgets/framework.dart:12:3)")
    app_stack = (
        "#0      List.reduce (dart:core/list.dart:120:5)\n"
        "#1      _FindsPerYearChart.build "
        "(package:pilzbuddy/features/profile/profile_screen.dart:707:38)")
    rows = [
        {"context": "Spots laden", "error_type": "PostgrestException",
         "message": "column spots.foo does not exist", "stack": framework_stack,
         "app_version": "1.26.4", "platform": "android"},
        {"context": "Spots laden", "error_type": "PostgrestException",
         "message": "column spots.foo does not exist", "stack": app_stack,
         "app_version": "1.27.0", "platform": "web"},
        {"context": "Fund eintragen", "error_type": "SocketException",
         "message": "Failed host lookup", "app_version": "1.27.0",
         "platform": "android"},
    ]
    body = digest_body(rows, "2026-W31")
    assert "3 caught errors" in body, body
    # Häufigste Gruppe zuerst — sonst muss man die Tabelle lesen, um zu
    # sehen, was am meisten weh tut.
    assert body.index("Spots laden") < body.index("Fund eintragen"), body
    assert "1.26.4, 1.27.0" in body, body
    assert "android, web" in body, body
    # Der Frame aus unserem Code gewinnt gegen den aus dem Framework, obwohl
    # die Framework-Zeile zuerst kommt — daran hängt der ganze Nutzen.
    assert "profile_screen.dart:707:38" in body, body
    assert "framework.dart:12:3" not in body, body

    # Ein ANR-Dump hat keinen Dart-Frame; dann ist der oberste native einer
    # besser als gar keiner.
    dump = ('"main" prio=5 tid=1 Native\n'
            "  | state=R schedstat=( 43932117853 1289361403 181077 )\n"
            "  native: #00 pc 00984478  base.apk (offset 9c0000)")
    assert top_frame(dump) == "native: #00 pc 00984478  base.apk (offset 9c0000)"
    # Kein Frame ist kein Frame — lieber nichts zeigen als eine beliebige
    # Zeile, die nach einem aussieht.
    assert top_frame("Error\n    at Object.wl (main.dart.js:1:2)") is None
    assert top_frame(None) is None
    assert top_frame("") is None

    # Wochengrenzen: KW30 2026 beginnt Montag, den 20. Juli.
    start, end = week_bounds("2026-W30")
    assert (start.year, start.month, start.day) == (2026, 7, 20), start
    assert (end - start).days == 7, (start, end)
    assert _stamp(start) == "2026-07-20T00:00:00Z", _stamp(start)

    print(body)
    print("\nself-test passed (no network, nothing written)")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--test-insert":
        self_test(sys.argv[2].split(","))
    elif len(sys.argv) > 1 and sys.argv[1] == "--test-digest":
        self_test_digest()
    elif len(sys.argv) > 1 and sys.argv[1] == "--test-sweep":
        self_test_sweep()
    elif len(sys.argv) > 2 and sys.argv[1] == "--digest-week":
        print_past_digest(sys.argv[2])
    else:
        main()
