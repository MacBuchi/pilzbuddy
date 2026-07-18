#!/usr/bin/env python3
"""Feedback bot for PilzBuddy.

Reads unprocessed rows from the Supabase `feedback` table and
- creates a GitHub issue for every feature request,
- opens one pull request adding all requested mushroom species to
  lib/core/mushroom_species.dart (group guessed from the name; the
  maintainer accepts by merging or rejects by closing the PR),
then stamps the rows with processed_at.

Required environment: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GH_TOKEN
(the workflow provides these). Self-test without any network access:
    python3 tool/feedback_bot.py --test-insert "Violetter Lacktrichterling"
"""
import json
import os
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone

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
    (("morchel", "lorchel"), "_mor"),
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


def main() -> None:
    rows = api(
        "GET",
        "/rest/v1/feedback?processed_at=is.null&order=created_at"
        "&select=id,type,message,species_name,created_at,profiles(username)",
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
            title = row["message"].strip().replace("\n", " ")
            title = "Feature request: " + title[:60] + ("…" if len(title) > 60 else "")
            if issue_exists(title):
                print(f"Skip (issue already exists): {title}")
            else:
                body = (
                    f"> {row['message']}\n\n"
                    f"Eingereicht in der App von **{username}** am {row['created_at'][:10]}.\n\n"
                    f"_Automatisch erstellt vom Feedback-Bot._"
                )
                run("gh", "issue", "create", "--title", title, "--body", body)
                print(f"Issue created: {title}")
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


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--test-insert":
        self_test(sys.argv[2].split(","))
    else:
        main()
