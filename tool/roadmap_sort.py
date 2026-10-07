#!/usr/bin/env python3
"""Sortiert ein neues Issue in den Fahrplan ein (#673).

Die Issue-Triage (`.github/workflows/claude-issue-triage.yml`) entscheidet,
WOHIN ein neues Issue gehört, schreibt den Fahrplan aber nicht selbst: Sie
hängt an ihren Kommentar eine unsichtbare Marke

    <!-- roadmap: Stage 2 | one-line summary in English -->

und dieses Skript fügt daraus genau EINE Zeile `- [ ] #N summary` am Ende
des genannten Abschnitts ein. Der Grund für die Trennung: Die Triage liest
Titel und Text des Issues, und die kommen aus dem In-App-Formular, also
von irgendwem. Dürfte die KI den Fahrplan schreiben, könnte ein Issue-Text
ihn über sie umschreiben lassen. So kann der schlimmste Fall eine falsch
einsortierte oder seltsam formulierte Zeile sein — sichtbar, und mit einem
Klick entfernt.

Regeln, die hier stehen und nirgends sonst:
- Ohne Marke, mit unbekanntem Abschnitt oder ohne Kommentar landet das
  Issue im Abschnitt `Inbox`, beschriftet mit seinem Titel.
- Steht `#N` schon irgendwo im Fahrplan, wird nichts eingefügt (ein
  zweiter Triage-Lauf desselben Issues verdoppelt nichts).
- Gelesen wird nur die Marke aus dem JÜNGSTEN Kommentar eines Bots —
  eine Marke, die ein Mensch in einen Kommentar tippt, zählt nicht.
- `check` ist die Gegenprobe: Der neue Text muss der alte sein plus diese
  eine Zeile. Zeilenenden werden vorher vereinheitlicht (im Browser
  bearbeitete Issue-Texte tragen `\\r\\n`, über die API geschriebene `\\n`).

    python3 tool/roadmap_sort.py sort ROADMAP.md ISSUE.json COMMENTS.json N
        ISSUE.json: `gh api repos/…/issues/N`, COMMENTS.json:
        `gh api repos/…/issues/N/comments`. Exit 0 und der neue Text auf
        stdout; Exit 3, wenn nichts einzufügen ist (Grund auf stderr).
    python3 tool/roadmap_sort.py --self-test
"""
import difflib
import json
import pathlib
import re
import sys

ROADMAP_ISSUE = 673
ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/claude-issue-triage.yml"
INBOX = "Inbox"
MAX_SUMMARY = 110
MARKER = re.compile(r"<!--\s*roadmap:\s*([^|>]*?)\s*(?:\|\s*(.*?))?\s*-->",
                    re.S)


def _lines(text):
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line.rstrip() for line in text.split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    return lines


def _clean(text):
    """Eine Zeile, ohne Markdown-Sprengstoff, gekürzt."""
    text = re.sub(r"\s+", " ", text or "").strip()
    text = re.sub(r"[<>`]", "", text)
    text = re.sub(r"^\W*(feature request|bug report)\s*:\s*", "", text,
                  flags=re.I)
    if len(text) > MAX_SUMMARY:
        text = text[:MAX_SUMMARY - 1].rstrip() + "…"
    return text


def marker_from(comments):
    """(Abschnitt, Zusammenfassung) aus dem jüngsten Bot-Kommentar."""
    for comment in reversed(comments):
        user = comment.get("user") or {}
        if user.get("type") != "Bot" and not user.get(
                "login", "").endswith("[bot]"):
            continue
        found = MARKER.findall(comment.get("body") or "")
        if found:
            section, summary = found[-1]
            return _clean(section), _clean(summary)
    return None, None


def _section_start(lines, section):
    """Index der Überschrift, deren Text mit `section` beginnt."""
    want = section.casefold()
    for i, line in enumerate(lines):
        if not line.startswith("### "):
            continue
        heading = line[4:].strip().casefold()
        if heading == want or (heading.startswith(want) and
                               not heading[len(want)].isalnum()):
            return i
    return None


def insert(roadmap, issue, section, summary):
    """Neuer Fahrplantext, oder None mit Grund."""
    lines = _lines(roadmap)
    if re.search(r"#%d(?!\d)" % issue, roadmap):
        return None, "#%d is already on the roadmap" % issue
    start = _section_start(lines, section) if section else None
    if start is None:
        start = _section_start(lines, INBOX)
    if start is None:
        return None, "no section %r and no %s on the roadmap" % (
            section, INBOX)
    end = start + 1
    while end < len(lines) and not lines[end].startswith("#"):
        end += 1
    at = start + 1
    for i in range(start + 1, end):
        if lines[i].startswith("- ["):
            at = i + 1
    line = "- [ ] #%d %s" % (issue, summary)
    new = lines[:at] + [line] + lines[at:]
    return "\n".join(new) + "\n", None


def check(before, after, issue):
    """Ist `after` genau `before` plus eine Zeile für #issue?"""
    old, new = _lines(before), _lines(after)
    item = re.compile(r"^- \[ \] #%d(?!\d)" % issue)
    matcher = difflib.SequenceMatcher(a=old, b=new, autojunk=False)
    added = []
    for op, _i1, _i2, j1, j2 in matcher.get_opcodes():
        if op == "equal":
            continue
        if op != "insert":
            return False
        added += new[j1:j2]
    return len(added) == 1 and bool(item.match(added[0]))


def sort(roadmap, issue_json, comments, number):
    section, summary = marker_from(comments)
    if not summary:
        summary = _clean(issue_json.get("title")) or "(no title)"
    new, reason = insert(roadmap, number, section or INBOX, summary)
    if new is None:
        return None, reason
    if not check(roadmap, new, number):
        return None, "self-check failed, nothing written"
    return new, None


def _self_test():
    road = (
        "Intro naming #12 in passing.\r\n\r\n### Inbox — new\r\n\r\n"
        "### Stage 1 — bugs\r\n- [ ] 1. #10 first\r\n- [x] 2. #11 done\r\n"
        "\r\n### Stage 10 — late\r\n- [ ] 3. #13 later\r\n\r\n---\r\n_foot_\r\n"
    )
    bot = {"type": "Bot", "login": "claude[bot]"}
    human = {"type": "User", "login": "someone"}

    def com(user, body):
        return [{"user": user, "body": body}]

    fails = []

    def expect(name, cond):
        if not cond:
            fails.append(name)

    issue = {"title": "Feature request: Karte\nzeigt <b>nix</b>"}
    new, _ = sort(road, issue, com(bot, "Text\n<!-- roadmap: Stage 1 | "
                                        "Map shows nothing -->"), 99)
    expect("stage 1, after the last item",
           "- [x] 2. #11 done\n- [ ] #99 Map shows nothing\n\n### Stage 10"
           in new)
    new, _ = sort(road, issue, com(bot, "<!-- roadmap: stage 10 | x -->"), 99)
    expect("stage 10 is not stage 1", "#13 later\n- [ ] #99 x\n" in new)
    new, _ = sort(road, issue, com(bot, "kein Marker"), 99)
    expect("no marker: inbox with cleaned title",
           "### Inbox — new\n- [ ] #99 Karte zeigt bnix/b\n" in new)
    new, _ = sort(road, issue, com(human, "<!-- roadmap: Stage 1 | x -->"),
                  99)
    expect("a human's marker does not count", "### Inbox — new\n- [ ] #99"
           in new)
    new, _ = sort(road, issue, com(bot, "<!-- roadmap: Nowhere | y -->"), 99)
    expect("unknown section: inbox", "### Inbox — new\n- [ ] #99 y" in new)
    new, _ = sort(road, issue, com(bot, "<!-- roadmap: Stage 1 | a\nb\n"
                                        "- [x] #1 evil -->"), 99)
    expect("summary stays one line", new.count("\n") ==
           road.replace("\r\n", "\n").count("\n") + 1)
    new, why = sort(road, issue, [], 12)
    expect("already mentioned: nothing", new is None and "already" in why)
    new, _ = sort(road, issue, [], 1)
    expect("#1 is not #10/#11/#12/#13", new is not None)
    new, _ = sort(road, {"title": "x" * 300}, [], 99)
    expect("long title is cut", max(len(l) for l in new.split("\n")) < 130)
    expect("check: removal", not check(road, road.replace(
        "- [ ] 3. #13 later\r\n", "- [ ] #99 x\r\n"), 99))
    expect("check: tick", not check(road, road.replace(
        "- [ ] 1.", "- [x] 1.") + "- [ ] #99 x\n", 99))
    expect("check: foreign item", not check(road, road + "- [ ] #98 x\n", 99))
    expect("check: two items", not check(road, road + "- [ ] #99 a\n"
                                         "- [ ] #99 b\n", 99))
    expect("check: unchanged is not an insert", not check(road, road, 99))
    # Die Nummer steht dreimal, und `if:` auf Job-Ebene kennt kein `env` —
    # ein neuer Fahrplan muss alle drei Stellen umstellen.
    flow = WORKFLOW.read_text(encoding="utf-8")
    expect("workflow env names #%d" % ROADMAP_ISSUE,
           'ROADMAP_ISSUE: "%d"' % ROADMAP_ISSUE in flow)
    expect("workflow job if names #%d" % ROADMAP_ISSUE,
           "!= '%d'" % ROADMAP_ISSUE in flow)
    expect("CLAUDE.md names #%d" % ROADMAP_ISSUE,
           "Der Fahrplan ist #%d" % ROADMAP_ISSUE in
           (ROOT / "CLAUDE.md").read_text(encoding="utf-8"))
    for name in fails:
        print("FAIL " + name)
    print("roadmap_sort self-test: %d failed" % len(fails))
    return 1 if fails else 0


def main(argv):
    if argv[1:] == ["--self-test"]:
        return _self_test()
    if len(argv) != 6 or argv[1] != "sort":
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[2], encoding="utf-8") as f:
        roadmap = f.read()
    with open(argv[3], encoding="utf-8") as f:
        issue_json = json.load(f)
    with open(argv[4], encoding="utf-8") as f:
        comments = json.load(f)
    new, reason = sort(roadmap, issue_json, comments, int(argv[5]))
    if new is None:
        print(reason, file=sys.stderr)
        return 3
    sys.stdout.write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
