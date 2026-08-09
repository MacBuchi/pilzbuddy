#!/usr/bin/env python3
"""Release-Notizen für eine Beförderung sammeln (#262).

Nimmt aus `CHANGELOG.md` alle Blöcke, die eine Version ÜBER dem letzten
stabilen Stand nennen — nicht nur den der beförderten Version. Wer nur
den einen Block einsetzt, lässt die Nutzer alles dazwischen verpassen;
bei zwei Wochen Bündelung sind das schnell fünf Versionen.

**Warum ein eigenes Werkzeug und kein awk-Einzeiler wie im Nachbarrepo:**
Dort ist der Changelog nach Versionen gegliedert (`## [1.2.3]`), hier
nach THEMEN — die Versionen stehen in einer kursiven Metazeile, oft
mehrere pro Block:

    ## Die Pilzampel leuchtet jetzt IM Wald

    *10. August 2026 · Version 1.76.0*

    ## Zum Ausprobieren: die Pilzwetter-Ampel

    *9. August 2026 · Versionen 1.72.0 und 1.73.0*

Das ist Absicht (CLAUDE.md: 68 Releases in neun Tagen wären als Liste
wertlos), macht die Auswahl aber zu einer Rechnung statt zu einem
Zeilenschnitt.

Nur Standardbibliothek, wie `feedback_bot.py` und `rain_grid.py`.
Selbsttest: `python3 tool/release_notes.py --self-test` (netzfrei, läuft
im Job „Analyze & Test" mit).
"""

import argparse
import re
import sys
from pathlib import Path

# Eine Version im Text: 1.76.0. Absichtlich ohne „v" — im Changelog steht
# sie ausgeschrieben („Version 1.76.0", „Versionen 1.72.0 und 1.73.0").
VERSION_RE = re.compile(r"\b(\d+\.\d+\.\d+)\b")

# Ein Block beginnt bei einer `##`-Überschrift. `#` (Titel) und alles
# davor gehören niemandem.
HEADING_RE = re.compile(r"^## ")


def parse_version(text):
    """'1.76.0' -> (1, 76, 0); für den Vergleich, nicht für die Anzeige."""
    return tuple(int(part) for part in text.split("."))


def split_blocks(changelog):
    """Der Changelog als Liste von Blöcken (Überschrift + Rumpf)."""
    blocks = []
    current = None
    for line in changelog.splitlines():
        if HEADING_RE.match(line):
            if current is not None:
                blocks.append(current)
            current = [line]
        elif current is not None:
            current.append(line)
    if current is not None:
        blocks.append(current)
    return ["\n".join(block).rstrip() + "\n" for block in blocks]


def versions_in(block):
    """Die Versionen, die die Metazeile eines Blocks nennt.

    Gesucht wird nur in den ersten Zeilen: Im Rumpf stehen manchmal
    Versionen im Fließtext („seit 1.44.0 …"), und die dürfen einen Block
    nicht in die Notizen ziehen.
    """
    head = "\n".join(block.splitlines()[:4])
    return {parse_version(v) for v in VERSION_RE.findall(head)}


def collect(changelog, version, since=None):
    """Alle Blöcke, die etwas Neues für den stabilen Kanal enthalten.

    [version] ist die beförderte Version, [since] der letzte stabile
    Stand (oder None). Ein Block kommt mit, wenn er eine Version nennt,
    die über [since] und nicht über [version] liegt — die obere Grenze
    zählt, weil ein Prerelease über der beförderten Version schon im
    Changelog stehen kann, wenn währenddessen weitergearbeitet wurde.
    """
    upper = parse_version(version)
    lower = parse_version(since) if since else None
    out = []
    for block in split_blocks(changelog):
        found = versions_in(block)
        if not found:
            continue
        if any(v <= upper and (lower is None or v > lower) for v in found):
            out.append(block)
    return out


def render(blocks, version, repository=None):
    if not blocks:
        # Kein Block heißt: Der Changelog kennt diese Version nicht. Das
        # kann CI nicht heilen — aber ein Release ohne Notizen ist
        # schlechter als ein Verweis.
        link = (
            f"https://github.com/{repository}/blob/main/CHANGELOG.md"
            if repository
            else "CHANGELOG.md"
        )
        return f"Änderungen dieser Version: {link}\n"
    return "\n".join(blocks)


def self_test():
    sample = """# Änderungen in PilzBuddy

Vorspann, der nirgends auftauchen darf.

## Drittes Thema

*10. August 2026 · Version 1.77.0*

Neu und noch nicht stabil.

## Zweites Thema

*9. August 2026 · Versionen 1.75.0 und 1.76.0*

Zwei Versionen in einem Block.

## Erstes Thema

*8. August 2026 · Version 1.74.0*

Das kennen die Nutzer schon — seit 1.44.0 sogar.
"""
    # Beförderung 1.76.0, stabil war 1.74.0: Der Block mit 1.75/1.76 muss
    # mit, der ältere nicht, der neuere auch nicht.
    blocks = collect(sample, "1.76.0", since="1.74.0")
    assert len(blocks) == 1, blocks
    assert "Zweites Thema" in blocks[0]
    assert "Drittes Thema" not in "".join(blocks)
    assert "Erstes Thema" not in "".join(blocks)

    # Ohne stabilen Vorgänger: alles bis zur beförderten Version.
    blocks = collect(sample, "1.76.0")
    assert len(blocks) == 2, blocks
    assert "Erstes Thema" in blocks[1]

    # Die Version im Fließtext („seit 1.44.0") zieht keinen Block herein.
    blocks = collect(sample, "1.50.0", since="1.40.0")
    assert blocks == [], blocks

    # Der Vorspann ist kein Block, auch wenn er Versionen nennt.
    assert "Vorspann" not in "".join(collect(sample, "1.77.0"))

    # Mehrere Blöcke bleiben in Changelog-Reihenfolge (neueste zuerst).
    blocks = collect(sample, "1.77.0", since="1.74.0")
    assert len(blocks) == 2
    assert blocks[0].startswith("## Drittes Thema")

    # Ohne Treffer steht wenigstens ein Verweis da.
    assert "CHANGELOG.md" in render([], "9.9.9", repository="a/b")
    print("Selbsttest bestanden.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="beförderte Version, z. B. 1.77.0")
    parser.add_argument("--since", default="", help="letzter stabiler Stand")
    parser.add_argument("--out", help="Zieldatei (Standard: stdout)")
    parser.add_argument("--changelog", default="CHANGELOG.md")
    parser.add_argument("--repository", default="MacBuchi/pilzbuddy")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0

    if not args.version:
        parser.error("--version fehlt")
    changelog = Path(args.changelog).read_text(encoding="utf-8")
    body = render(
        collect(changelog, args.version, args.since or None),
        args.version,
        args.repository,
    )
    if args.out:
        Path(args.out).write_text(body, encoding="utf-8")
    else:
        sys.stdout.write(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
