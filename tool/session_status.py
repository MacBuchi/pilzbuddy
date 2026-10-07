#!/usr/bin/env python3
"""Lagebild zu Beginn einer Agenten-Sitzung (SessionStart-Hook).

Eingehängt in `.claude/settings.json`. Was dieses Skript ausgibt, steht im
Kontext, bevor die erste Anfrage kommt. Es beantwortet die Fragen, an denen
bisher Schleifen entstanden sind, BEVOR jemand Code schreibt:

- Liegt der Branch hinter `origin/main`? Dann zuerst neu aufsetzen — nach
  einem Squash-Merge trägt ein alter Branch den gemergten Commit doppelt.
- Liegt Unkommittiertes herum? Dann nichts per `git checkout` zurücknehmen.
- Welche offenen PRs bumpen ebenfalls die Version? Zwei Bump-PRs
  kollidieren zwangsläufig (Skill `github-flow`, Abschnitt 4).
- Was steht als Nächstes im Fahrplan #673? „Weiter im Plan" nach einem
  `/clear` heißt dieses Issue — nicht eine Plandatei, nicht der Verlauf,
  der gerade gelöscht wurde. Am 2026-10-07 fand eine Sitzung nach
  `/clear` nur eine längst erledigte Plandatei und musste nachfragen.

Jeder Netzschritt hat eine harte Grenze; ohne Netz oder ohne `gh` fällt die
betroffene Zeile weg, die Sitzung startet trotzdem. Das Skript wirft nie
und endet immer mit 0 — ein Hook, der scheitert, wäre ein Hindernis statt
einer Auskunft.

    python3 tool/session_status.py              # Lagebild
    python3 tool/session_status.py --self-test  # prüft die Auswertung
"""
import re
import subprocess
import sys

from roadmap_sort import ROADMAP_ISSUE, WHERE

NET_TIMEOUT_S = 5
ROADMAP_NEXT = 3  # so viele offene Punkte nennt das Lagebild
CLOUD = WHERE["cloud"]


def run(args, timeout=NET_TIMEOUT_S):
    """stdout eines Befehls oder None bei Fehler/Zeitüberschreitung."""
    try:
        r = subprocess.run(args, capture_output=True, text=True,
                           timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def version_of(pubspec_text):
    m = re.search(r"^version:\s*(\S+)", pubspec_text or "", re.MULTILINE)
    return m.group(1) if m else None


def bump_prs(prs_json_lines):
    """Zeilen 'nummer<TAB>branch<TAB>1/0' -> Liste 'nummer (branch)'."""
    out = []
    for line in prs_json_lines:
        parts = line.split("\t")
        if len(parts) == 3 and parts[2] == "1":
            out.append(f"#{parts[0]} ({parts[1]})")
    return out


def roadmap_summary(body):
    """(offene Punkte der Stufen in Reihenfolge, Zahl der Inbox-Einträge).

    Stufen heißt: alle `### `-Abschnitte außer Inbox und den
    Betreiber-Entscheidungen — die sind keine Arbeit für eine Sitzung."""
    open_items, inbox, section = [], 0, ""
    for line in (body or "").replace("\r\n", "\n").split("\n"):
        if line.startswith("### "):
            section = line[4:].strip().casefold()
            continue
        if not line.startswith("- [ ] "):
            continue
        if section.startswith("inbox"):
            inbox += 1
        elif not section.startswith("operator"):
            open_items.append(line[6:].strip())
    return open_items, inbox


def report(branch, fetched, behind, ahead, dirty, main_version, bumps,
           roadmap=None):
    lines = ["Lagebild (tool/session_status.py)"]
    if branch is None:
        return "\n".join(lines + ["Kein Git-Repository erkannt."])
    state = f"Branch: {branch}"
    if not fetched:
        state += " — fetch übersprungen (kein Netz?), Stand ggf. alt"
    if behind:
        state += f" — {behind} Commit(s) hinter origin/main"
        if branch != "main":
            state += " → vor dem Coden neu aufsetzen (rebase/neu abzweigen)"
        else:
            state += " → git pull --ff-only"
    if ahead and branch == "main":
        state += f" — {ahead} lokale Commit(s) auf main (main ist geschützt!)"
    lines.append(state)
    if dirty:
        lines.append(f"Unkommittiert: {dirty} Datei(en) — nichts per "
                     "git checkout zurücknehmen, erst ansehen")
    if main_version:
        lines.append(f"Version auf origin/main: {main_version}")
    if bumps is not None:
        lines.append("Offene PRs mit Versions-Bump: "
                     + (", ".join(bumps) if bumps else "keine"))
    head = (f"Fahrplan #{ROADMAP_ISSUE} („der Plan“, „weiter im Plan“ — "
            "dort nachsehen, nicht in Plandateien)")
    if roadmap is None:
        lines.append(head + ": nicht abrufbar, mit "
                     f"`gh api repos/MacBuchi/pilzbuddy/issues/{ROADMAP_ISSUE}`"
                     " lesen")
    else:
        items, inbox = roadmap
        lines.append(head + ":")
        for item in items[:ROADMAP_NEXT]:
            lines.append(f"  - {item[:140]}")
        if not items:
            lines.append("  - keine offenen Punkte in den Stufen")
        cloud = [i for i in items if CLOUD in i]
        if cloud and cloud[0] not in items[:ROADMAP_NEXT]:
            lines.append(f"  Nächster {CLOUD}-Punkt (in einer Cloud-Sitzung "
                         f"machbar): {cloud[0][:140]}")
        elif not cloud and items:
            lines.append(f"  Kein offener {CLOUD}-Punkt — alles Nächste "
                         "braucht den Rechner oder den Betreiber")
        if inbox:
            lines.append(f"  Inbox: {inbox} Issue(s) noch nicht eingeordnet")
    return "\n".join(lines)


def main():
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], timeout=2)
    if branch is None:
        print(report(None, False, 0, 0, 0, None, None))
        return
    branch = branch.strip()
    fetched = run(["git", "fetch", "--quiet", "origin", "main"]) is not None
    counts = run(["git", "rev-list", "--left-right", "--count",
                  "origin/main...HEAD"], timeout=2) or "0 0"
    behind, ahead = (int(x) for x in counts.split()[:2])
    status = run(["git", "status", "--porcelain"], timeout=3) or ""
    dirty = len([l for l in status.splitlines() if l.strip()])
    main_version = version_of(run(["git", "show", "origin/main:pubspec.yaml"],
                                  timeout=2))
    prs = run(["gh", "pr", "list", "--state", "open", "--json",
               "number,headRefName,files", "--jq",
               '.[] | "\\(.number)\\t\\(.headRefName)\\t'
               '\\(if ([.files[].path] | index("pubspec.yaml")) '
               'then 1 else 0 end)"'])
    bumps = bump_prs(prs.splitlines()) if prs is not None else None
    body = run(["gh", "api", f"repos/MacBuchi/pilzbuddy/issues/{ROADMAP_ISSUE}",
                "--jq", ".body"])
    roadmap = roadmap_summary(body) if body is not None else None
    print(report(branch, fetched, behind, ahead, dirty, main_version, bumps,
                 roadmap))


def self_test():
    assert version_of("name: x\nversion: 1.2.3+4\n") == "1.2.3+4"
    assert version_of("") is None
    assert bump_prs(["12\tfeat/a\t1", "13\tfix/b\t0", "kaputt"]) == \
        ["#12 (feat/a)"]
    r = report("feat/x", True, 3, 1, 2, "1.2.3+4", ["#12 (feat/a)"])
    assert "3 Commit(s) hinter origin/main" in r and "neu aufsetzen" in r, r
    assert "Unkommittiert: 2" in r and "#12 (feat/a)" in r, r
    r = report("main", False, 0, 2, 0, None, None)
    assert "fetch übersprungen" in r and "main ist geschützt" in r, r
    assert "Offene PRs" not in r, r
    r = report("feat/y", True, 0, 0, 0, "1.0.0+1", [])
    assert "hinter" not in r and "Bump: keine" in r, r
    road = ("Intro\r\n### Inbox\r\n- [ ] #9 neu\r\n### Stage 1 — x\r\n"
            "- [x] 1. #1 fertig\r\n- [ ] 2. #2 offen\r\n### Stage 2\r\n"
            "- [ ] 3. #3 später\r\n### Operator decisions\r\n- [ ] #4 du\r\n")
    assert roadmap_summary(road) == (["2. #2 offen", "3. #3 später"], 1), \
        roadmap_summary(road)
    r = report("feat/y", True, 0, 0, 0, None, None, roadmap_summary(road))
    assert "Fahrplan #673" in r and "weiter im Plan" in r, r
    assert "  - 2. #2 offen" in r and "Inbox: 1" in r and "#4" not in r, r
    assert "Nächster" not in r and "Kein offener" in r, r
    later = (["1. #5 💻 a", "2. #6 👤 b", "3. #7 💻 c", "4. #8 ☁️ d"], 0)
    r = report("feat/y", True, 0, 0, 0, None, None, later)
    assert "Nächster ☁️-Punkt (in einer Cloud-Sitzung machbar): 4. #8" in r, r
    near = (["1. #8 ☁️ d", "2. #6 👤 b"], 0)
    r = report("feat/y", True, 0, 0, 0, None, None, near)
    assert "Nächster" not in r and "Kein offener" not in r, r
    r = report("feat/y", True, 0, 0, 0, None, None, None)
    assert "nicht abrufbar" in r and "issues/673" in r, r
    print("session_status self-test ok")


if __name__ == "__main__":
    try:
        if "--self-test" in sys.argv:
            self_test()
        else:
            main()
    except AssertionError:
        raise
    except Exception as e:  # noqa: BLE001 — ein Hook darf nie scheitern
        print(f"Lagebild nicht verfügbar: {e}")
