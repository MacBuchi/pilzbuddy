#!/usr/bin/env python3
"""Was zeigt das Neuheiten-Blatt nach dieser Beförderung? — für die Run-Summary.

Das Blatt nach einem Update (#596) sucht sich seinen Inhalt SELBST: Es
zeigt die Highlights aus `kFeatureHighlights`, deren `since` neuer ist
als der Stand, den das Gerät kennt. Bei der Beförderung kuratiert niemand
etwas — und genau deshalb fällt ein vergessener Eintrag nirgends auf.
Eine große Funktion ohne Highlight kommt einfach ohne Ankündigung an.

Dieses Werkzeug sagt es an der Stelle, an der es noch etwas ändert: in
der Run-Summary von `promote.yml`, wo ohnehin jemand hinsieht (dieselbe
Linie wie `screenshot_stand.py`). Kein Tor — manche Beförderungen bringen
ehrlich nur Korrekturen, und ein Alarm, der dann angeht, wird weggeklickt.

Gezählt wird wie im Gerät: `since` > letzter stabiler Stand und
<= beförderte Version. Nur `HighlightKind.highlight` kommt ins Blatt;
Tipps stehen nur in „Entdecken" und werden getrennt aufgeführt.

`--self-test` (im Job „Analyze & Test") liest die ECHTE Datei: Zerbricht
ihr Format, wird CI rot, statt dass der Hinweis still verschwindet.
"""

import argparse
import pathlib
import re
import sys

SOURCE = pathlib.Path('lib/features/highlights/feature_highlights.dart')
SHEET_MAX = 3  # kHighlightSheetMax

# Ab hier gilt der Merker, welche Neuheiten ein Gerät kennt — seit dem
# Zurücksetzen für alle (`highlights_seen_version_3`, Betreiber
# 2026-09-25). Wer von einem ÄLTEREN stabilen Stand kommt, hat keinen und
# bekommt einmal den Rückblick (`kRecapLead` zuerst); dann ist „kein
# neues Highlight" kein Befund. Wird der Merker je wieder zurückgesetzt,
# gehört die Version hierher.
LAST_RESET = '1.208.0'

ENTRY = re.compile(
    r"FeatureHighlight\(\s*id:\s*'(?P<id>[^']+)',\s*"
    r"since:\s*'(?P<since>\d+\.\d+\.\d+)',\s*"
    r"kind:\s*HighlightKind\.(?P<kind>\w+),.*?"
    r"title:\s*'(?P<title>(?:[^'\\]|\\.)*)'",
    re.S)


def version_key(v):
    return tuple(int(p) for p in v.split('.'))


def parse(text):
    return [m.groupdict() for m in ENTRY.finditer(text)]


def report(entries, previous, version):
    """Markdown für die Summary."""
    lo = version_key(previous) if previous else (0, 0, 0)
    hi = version_key(version)
    new = [e for e in entries if lo < version_key(e['since']) <= hi]
    highlights = sorted((e for e in new if e['kind'] == 'highlight'),
                        key=lambda e: version_key(e['since']), reverse=True)
    tips = [e for e in new if e['kind'] == 'tip']
    out = [f'### Neuheiten-Blatt für {version}', '']
    if lo < version_key(LAST_RESET):
        out.append('Nutzer des bisherigen stabilen Stands bekommen den '
                   '**Rückblick** (einmal, `kRecapLead` zuerst) — ihre App '
                   'hat sich noch keine Version gemerkt.')
    elif not highlights:
        out.append('> ⚠️ **Kein Highlight seit '
                   f'{previous or "dem Anfang"}.** Das Blatt bleibt nach '
                   'dem Update aus. Stimmt das, oder fehlt ein Eintrag in '
                   '`kFeatureHighlights`?')
    else:
        out.append(f'Das Blatt zeigt (höchstens {SHEET_MAX}, jüngste zuerst):')
        out.append('')
        for i, e in enumerate(highlights):
            mark = '' if i < SHEET_MAX else ' — *nur in „Entdecken"*'
            out.append(f"- {e['title']} ({e['since']}){mark}")
    if tips:
        out.append('')
        out.append('Neue Tipps (nur in „Entdecken"): ' +
                   ', '.join(e['title'] for e in tips))
    return '\n'.join(out) + '\n'


def self_test():
    entries = parse(SOURCE.read_text(encoding='utf-8'))
    assert len(entries) >= 15, f'nur {len(entries)} Einträge gelesen'
    ids = [e['id'] for e in entries]
    assert len(ids) == len(set(ids)), 'doppelte Kennung gelesen'
    assert {e['kind'] for e in entries} <= {'highlight', 'tip'}
    # Die Datei zählt ihre Einträge mit `id:` — keiner darf dem Muster
    # entgehen, sonst fehlte er still in der Summary.
    declared = SOURCE.read_text(encoding='utf-8').count('FeatureHighlight(\n')
    assert declared == len(entries), f'{declared} deklariert, {len(entries)} gelesen'

    sample = [
        {'id': 'a', 'since': '1.10.0', 'kind': 'highlight', 'title': 'A'},
        {'id': 'b', 'since': '1.12.0', 'kind': 'highlight', 'title': 'B'},
        {'id': 'c', 'since': '1.12.0', 'kind': 'tip', 'title': 'C'},
        {'id': 'd', 'since': '1.9.0', 'kind': 'highlight', 'title': 'D'},
    ]
    sample = [dict(e, since='1.2' + e['since'][2:]) for e in sample]
    text = report(sample, '1.209.0', '1.212.0')
    assert '- B (1.212.0)' in text and '- A (1.210.0)' in text, text
    assert 'D (' not in text, 'der alte Stand gehört nicht dazu'
    assert text.index('- B') < text.index('- A'), 'jüngste zuerst'
    assert 'Neue Tipps' in text and 'C' in text
    assert '⚠️' in report(sample, '1.212.0', '1.212.1'), 'kein Highlight = Warnung'
    first = report(sample, '1.203.0', '1.207.0')
    assert 'Rückblick' in first and '⚠️' not in first, first
    # Versionen numerisch, nicht als Text: Als Text wäre 1.210 älter
    # als 1.99.
    assert version_key('1.210.0') > version_key('1.99.0')
    print('ok')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--version', help='beförderte Version, ohne v')
    parser.add_argument('--since', default='', help='letzter stabiler Stand')
    parser.add_argument('--source', type=pathlib.Path, default=SOURCE)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.version:
        parser.error('--version fehlt')
    if not args.source.exists():
        print(f'### Neuheiten-Blatt für {args.version}\n\n'
              '(Keine Highlight-Liste in diesem Stand.)')
        return
    entries = parse(args.source.read_text(encoding='utf-8'))
    sys.stdout.write(report(entries, args.since.lstrip('v'), args.version))


if __name__ == '__main__':
    main()
