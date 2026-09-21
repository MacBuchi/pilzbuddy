#!/usr/bin/env python3
"""Holt die Artfotos für die Verwechslungspaare von Wikimedia Commons.

Nachvollziehbarkeit, nicht Automatik: Die AUSWAHL trifft ein Mensch, der
die Kandidaten ansieht — ein Werkzeug kann nicht beurteilen, ob ein Foto
das Merkmal zeigt, um das es geht, und auf Commons ist die Bestimmung
nicht garantiert (zwei Kandidaten für #511 zeigten eine andere Art als
ihr Dateiname). Das Skript beschafft, beschneidet und rechnet um; die
Dateinamen stehen unten fest eingetragen.

    python3 tool/species_photos.py --candidates 'Amanita rubescens'
        Kandidaten einer Commons-Kategorie auflisten (Lizenz, Größe,
        Auszeichnung) — die Vorarbeit fürs Ansehen.

    python3 tool/species_photos.py --build
        Die eingetragenen Dateien holen, quadratisch mittig beschneiden,
        auf 700x700 bringen und als WebP nach assets/species/ schreiben.
        Gibt die Lizenzangaben aus, die nach species_photos.dart gehören.

Braucht `cwebp` (brew install webp) und `sips` (macOS).
"""
import argparse, json, os, re, subprocess, sys, urllib.parse, urllib.request

UA = ('PilzBuddy-asset-tool/1.0 '
      '(https://github.com/MacBuchi/pilzbuddy)')
API = 'https://commons.wikimedia.org/w/api.php'
OUT = 'assets/species'
SIZE = 700

# Die ausgewählten Dateien: deutscher Name -> (Commons-Dateiname, Slug).
# Wer hier tauscht, hat das neue Bild ANGESEHEN und geprüft, ob es das
# Merkmal zeigt, das der Unterschiedssatz in species_lookalikes.dart nennt.
CHOSEN = {
    'Stockschwämmchen': (
        '2025-10-11 D500-920 Achim-Lammerts Kuehneromyces-mutabilis.jpg',
        'stockschwaemmchen'),
    'Gifthäubling': (
        'Galerina marginata - Bundelmosklokje.jpg', 'gifthaeubling'),
    'Samtfußrübling': (
        'Collybie à pied velouté (Flammulina velutipes).jpg',
        'samtfussruebling'),
    'Speisemorchel': (
        '2026-04-04 Z5-3750E Achim-Lammerts Morchella-esculenta.jpg',
        'speisemorchel'),
    'Spitzmorchel': (
        'Lukas Large - Morchella elata (53588923052).jpg', 'spitzmorchel'),
    'Frühjahrslorchel': (
        'Gyromitra esculenta (27717088958).jpg', 'fruehjahrslorchel'),
    'Perlpilz': ('Amanita rubescens (2) (48337725171).jpg', 'perlpilz'),
    'Pantherpilz': ('Amanita pantherina (42556666615).jpg', 'pantherpilz'),
    'Wiesenchampignon': (
        'Agaricus campestris (48647010296).jpg', 'wiesenchampignon'),
    'Grüner Knollenblätterpilz': (
        'Amanita phalloides (29069664382).jpg',
        'gruenerknollenblaetterpilz'),
    'Flaschenstäubling': (
        '2025-10-15 D500-1015 Achim-Lammerts Lycoperdon-perlatum.jpg',
        'flaschenstaeubling'),
    'Flockenstieliger Hexenröhrling': (
        'Boletus erythropus 2010 G3.jpg', 'flockenstieligerhexenroehrling'),
    'Satansröhrling': (
        'Frankenwarte 10.08.2016 Satan's Bolete - Rubroboletus satanas (29135732512).jpg', 'satansroehrling'),
}

# Nur diese Lizenzen kommen in Frage. NC- und ND-Varianten sind
# ausgeschlossen: Die App liegt im Play Store, und „nicht kommerziell"
# ist dort eine Frage, die man nicht offen lassen will.
OK_LICENCES = ('cc0', 'cc by', 'cc-by', 'public domain')


def api(params):
    url = API + '?' + urllib.parse.urlencode(
        {**params, 'format': 'json', 'formatversion': '2'})
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def strip(html):
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', html or '')).strip()


def info(titles, width=1280):
    out = api({'action': 'query', 'titles': '|'.join(titles),
               'prop': 'imageinfo', 'iiprop': 'url|size|extmetadata',
               'iiurlwidth': width})
    return out.get('query', {}).get('pages', [])


def candidates(category):
    out = api({'action': 'query', 'generator': 'categorymembers',
               'gcmtitle': f'Category:{category}', 'gcmtype': 'file',
               'gcmlimit': 50, 'prop': 'imageinfo|categories',
               'iiprop': 'url|size|extmetadata', 'iiurlwidth': 900,
               'cllimit': 500})
    for page in out.get('query', {}).get('pages', []):
        ii = (page.get('imageinfo') or [{}])[0]
        meta = ii.get('extmetadata', {})
        lic = strip(meta.get('LicenseShortName', {}).get('value'))
        if not any(t in lic.lower() for t in OK_LICENCES):
            continue
        cats = {c['title'] for c in page.get('categories', [])}
        mark = ('FP' if 'Category:Featured pictures on Wikimedia Commons'
                in cats else 'QI' if 'Category:Quality images' in cats
                else '  ')
        print(f'{mark} {ii.get("width")}x{ii.get("height")} {lic:14} '
              f'{page["title"][5:]}')
        print(f'   {ii.get("thumburl")}')
        desc = strip(meta.get('ImageDescription', {}).get('value'))
        if desc:
            print(f'   „{desc[:160]}"')


def build():
    os.makedirs(OUT, exist_ok=True)
    tmp = '.species_photos_tmp'
    os.makedirs(tmp, exist_ok=True)
    total = 0
    for german, (filename, slug) in CHOSEN.items():
        page = info([f'File:{filename}'])[0]
        ii = page['imageinfo'][0]
        meta = ii['extmetadata']
        licence = strip(meta.get('LicenseShortName', {}).get('value'))
        if not any(t in licence.lower() for t in OK_LICENCES):
            sys.exit(f'{german}: Lizenz „{licence}" ist nicht zulässig')
        src = f'{tmp}/{slug}.jpg'
        req = urllib.request.Request(ii['thumburl'],
                                     headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=120) as r, \
                open(src, 'wb') as f:
            f.write(r.read())
        dims = subprocess.run(['sips', '-g', 'pixelWidth', '-g',
                               'pixelHeight', src],
                              capture_output=True, text=True).stdout
        w = int(re.search(r'pixelWidth: (\d+)', dims).group(1))
        h = int(re.search(r'pixelHeight: (\d+)', dims).group(1))
        side = min(w, h)
        subprocess.run(['sips', '-c', str(side), str(side), src,
                        '--out', f'{tmp}/{slug}_q.jpg'], capture_output=True)
        subprocess.run(['sips', '-z', str(SIZE), str(SIZE),
                        f'{tmp}/{slug}_q.jpg', '--out', f'{tmp}/{slug}_s.jpg'],
                       capture_output=True)
        dst = f'{OUT}/{slug}.webp'
        subprocess.run(['cwebp', '-q', '80', '-quiet', f'{tmp}/{slug}_s.jpg',
                        '-o', dst], capture_output=True)
        size = os.path.getsize(dst)
        total += size
        author = strip(meta.get('Artist', {}).get('value'))[:70]
        print(f"  '{german}': (")
        print(f"    asset: '{OUT}/{slug}.webp',")
        print(f"    author: '{author}',")
        print(f"    licence: '{licence}',")
        print(f"    licenceUrl: "
              f"'{strip(meta.get('LicenseUrl', {}).get('value'))}',")
        print(f"    source: '{ii['descriptionurl']}',")
        print(f'  ),  // {size} Bytes')
    print(f'\n{len(CHOSEN)} Bilder, {total} Bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidates', metavar='KATEGORIE')
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    if args.candidates:
        candidates(args.candidates)
    elif args.build:
        build()
    else:
        parser.print_help()
