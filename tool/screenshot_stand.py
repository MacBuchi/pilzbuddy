#!/usr/bin/env python3
"""Wie alt sind die Store-Screenshots? — als Zeile für die Run-Summary.

Das Problem, gegen das es hilft: Bilder veralten still. Am 2026-08-18
ersetzte #321 den Karten-Screenshot durch die Pilzwetter-Ebene bei 10 km,
in der kein einziger Spot-Marker vorkommt — vier Tage lang zeigte damit
KEINES der fünf Bilder, wofür die App da ist. Aufgefallen ist es einem
Menschen beim Draufschauen, nicht einem Werkzeug.

Warum nicht einfach neu erzeugen: Pilzwetter und Regen rechnen sich
täglich neu, die OSM-Kacheln ändern sich unter uns. Ein Job, der die
Bilder nachzieht, lieferte jeden Lauf einen Diff — und ein Alarm, der
immer angeht, wird weggeklickt (dieselbe Lehre wie beim Asset-Wächter,
siehe CLAUDE.md).

Deshalb kein Tor, sondern ein Hinweis an der einzigen Stelle, an der er
etwas ändern kann: beim Befördern eines Releases, wo ohnehin jemand
hinsieht. `promote.yml` schreibt die Ausgabe in seine Run-Summary.

Der Stand steht in der Screenshot-Tabelle von `store/README.md` — dort,
wo auch beschrieben ist, was jedes Bild zeigt, und damit an genau einer
Stelle. Diesen Leser hält `--self-test` am Leben (im Job „Analyze &
Test"): Zerbricht das Tabellenformat, wird CI rot, statt dass der
Hinweis still verschwindet.
"""

import argparse
import pathlib
import re
import sys

README = pathlib.Path('store/README.md')
PUBSPEC = pathlib.Path('pubspec.yaml')

# | `01-karte-spots.png` | 1.99.1 | Karte bei 100 m mit sechs Spots … |
ROW = re.compile(r'^\|\s*`(?P<file>\d\d-[\w.-]+\.png)`\s*\|\s*'
                 r'(?P<version>\d+\.\d+\.\d+)\s*\|')


def parse_rows(text):
    return [(match['file'], match['version'])
            for line in text.splitlines()
            if (match := ROW.match(line))]


def as_tuple(version):
    return tuple(int(part) for part in version.split('.'))


def gap(older, newer):
    """Abstand in Minor-Versionen — die Einheit, in der dieses Projekt
    zählt: Ein `feat` erhöht die Minor, und genau ein solches ändert das
    Aussehen.

    `None` über eine Hauptversion hinweg. Das ist keine Faulheit: Wie
    viele Minors zwischen 1.99.0 und 2.1.0 liegen, hängt davon ab, wie
    weit die 1er-Reihe gezählt hat — jede Zahl wäre hier geraten. Der
    Aufrufer sagt dann „aus einer früheren Hauptversion", und das
    stimmt immer.
    """
    old, new = as_tuple(older), as_tuple(newer)
    return None if old[0] != new[0] else new[1] - old[1]


def report(rows, current):
    if not rows:
        return ['### Store-Screenshots', '',
                'Kein Stand ablesbar — Tabelle in `store/README.md` geprüft?']

    oldest_file, oldest = min(rows, key=lambda row: as_tuple(row[1]))
    distance = gap(oldest, current)
    abstand = ('aus einer früheren Hauptversion' if distance is None
               else f'{distance} Minor-Versionen dazwischen')
    lines = ['### Store-Screenshots', '',
             f'Ältestes Bild: `{oldest_file}` aus **{oldest}**, '
             f'ausgeliefert wird **{current}** — {abstand}.', '']
    if distance is None or distance >= 5:
        lines += ['Das ist viel. Lohnt ein Blick, ob die Bilder noch zeigen, '
                  'was die App heute kann — neu aufnehmen mit '
                  '`tool/store_screenshots.sh` und `tool/seed_screenshot_data.py`, '
                  'Verfahren in `store/README.md`.', '']
    lines += ['| Bild | Stand |', '|---|---|']
    lines += [f'| `{file}` | {version} |' for file, version in rows]
    return lines


def current_version():
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)', PUBSPEC.read_text(),
                      re.MULTILINE)
    if not match:
        raise SystemExit('Keine version: in pubspec.yaml gefunden.')
    return match[1]


def self_test():
    table = '\n'.join([
        '| Datei | Stand | Zeigt |',
        '|---|---|---|',
        '| `01-karte-spots.png` | 1.99.1 | sechs Spots |',
        '| `02-karte-pilzwetter.png` | 1.96.0 | Wald + Pilzwetter |',
        '| `nicht-nummeriert.png` | 1.0.0 | wird nicht gezählt |',
    ])
    rows = parse_rows(table)
    assert rows == [('01-karte-spots.png', '1.99.1'),
                    ('02-karte-pilzwetter.png', '1.96.0')], rows

    assert gap('1.96.0', '1.99.1') == 3
    assert gap('1.99.0', '1.99.1') == 0
    # Über eine Hauptversion hinweg wird NICHT geraten.
    assert gap('1.99.0', '2.1.0') is None
    assert 'aus einer früheren Hauptversion' in '\n'.join(report(rows, '2.1.0'))
    assert 'Das ist viel' in '\n'.join(report(rows, '2.1.0'))

    # Der Hinweis nennt das älteste Bild, nicht das erste der Tabelle.
    text = '\n'.join(report(rows, '1.99.1'))
    assert '02-karte-pilzwetter.png` aus **1.96.0**' in text, text
    assert 'ausgeliefert wird **1.99.1**' in text

    # Ab fünf Minor-Versionen kommt die Empfehlung dazu, davor nicht.
    assert 'Das ist viel' not in text
    assert 'Das ist viel' in '\n'.join(report(rows, '1.101.0'))

    # Und die echte Datei muss lesbar bleiben — genau das ist der Punkt.
    live = parse_rows(README.read_text())
    assert live, 'Aus store/README.md liest sich kein Stand mehr heraus.'
    assert len(live) >= 5, live

    print('screenshot_stand self-test: ok')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    print('\n'.join(report(parse_rows(README.read_text()), current_version())))


if __name__ == '__main__':
    sys.exit(main())
