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


def main() -> None:
    # Before the early return below — otherwise digest and purge would only
    # ever run on the rare tick that also has unprocessed feedback.
    report_error_digest()
    purge_error_reports()

    rows = api(
        "GET",
        "/rest/v1/feedback?processed_at=is.null&order=created_at"
        "&select=id,type,message,species_name,created_at,app_version,profiles(username)",
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
                species_authors.append(f"{name} (von {username})")
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
                version = row.get("app_version")
                aus = f" aus Version {version}" if version else ""
                body = (
                    f"> {row['message']}\n\n"
                    f"Eingereicht in der App von **{username}**{aus} "
                    f"am {row['created_at'][:10]}.\n\n"
                    f"_Automatisch erstellt vom Feedback-Bot._"
                )
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
    elif len(sys.argv) > 2 and sys.argv[1] == "--digest-week":
        print_past_digest(sys.argv[2])
    else:
        main()
