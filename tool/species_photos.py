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

    python3 tool/species_photos.py --large DIR [slug-1.webp …]
        Die 1200x1200-Fassung für die Vergrößerung (#537, #588) — aus
        DEMSELBEN Commons-Original wie das 400er in assets/species/ und
        mit DEMSELBEN Ausschnitt. Ohne Dateinamen: alle, die auf dem
        Branch `species-photos` noch fehlen.

    python3 tool/species_photos.py --check-large
        Bricht ab, wenn ein Bild aus assets/species/ keine große Fassung
        auf `species-photos` hat. Läuft in CI.

Braucht `cwebp` (brew install webp) und `sips` (macOS); --large und
--check-large brauchen stattdessen ffmpeg und git (laufen auch auf Linux).
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
        "Frankenwarte 10.08.2016 Satan's Bolete - Rubroboletus satanas (29135732512).jpg",
        'satansroehrling'),
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


# ---------------------------------------------------------------------------
# Große Fassungen (#588)
# ---------------------------------------------------------------------------

LARGE = 1200

# Gibt das Original keine 1200 her, wird es in SEINER Größe abgelegt —
# nie hochgerechnet, das erfände Schärfe. Unter dem Doppelten des
# mitgelieferten 400ers lohnt die große Fassung nicht: Dann bleibt es beim
# 400er, und der Wächter nimmt die Datei in [TOO_SMALL] als bekannt hin.
MIN_LARGE = 800

# Originale, die nicht einmal [MIN_LARGE] hergeben (gemessen 2026-09-24).
# Ein besseres Bild ersetzt sie irgendwann — dann fliegen sie hier raus.
TOO_SMALL = {'judasohr-1.webp'}  # 1024x683
BRANCH = 'origin/species-photos'
PHOTOS_DART = 'lib/core/species_photos.dart'

# Ab dieser Ähnlichkeit (SSIM, 0..1) zeigt der Ausschnitt dasselbe wie das
# 400er. Gemessen am 2026-09-24 (Birkenpilz, Schwefelporling): derselbe
# Ausschnitt 0,966/0,967, um 5 % versetzt schon 0,30/0,35, um 20 %
# 0,27/0,32. Die Lücke ist so groß, dass die Schwelle nicht fein
# eingestellt werden muss — und streng sein darf: Eine große Fassung mit
# anderem Ausschnitt SPRINGT, wenn die Vergrößerung sie einblendet.
MIN_SSIM = 0.85


def sources():
    """Asset → Commons-Seite, aus species_photos.dart (die EINE Liste)."""
    text = open(PHOTOS_DART).read()
    out = {}
    for m in re.finditer(r"asset: '(assets/species/[^']+)',.*?source: '([^']+)'",
                         text, re.S):
        out.setdefault(os.path.basename(m.group(1)), m.group(2))
    return out


def branch_files():
    subprocess.run(['git', 'fetch', '-q', 'origin', 'species-photos'],
                   check=True)
    listing = subprocess.run(['git', 'ls-tree', '--name-only', BRANCH],
                             capture_output=True, text=True, check=True)
    return set(listing.stdout.split())


def missing_large():
    small = {f for f in os.listdir(OUT) if f.endswith('.webp')}
    return sorted(small - branch_files() - TOO_SMALL)


def ffmpeg(*args):
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', *args], check=True)


def ssim(a, b):
    out = subprocess.run(['ffmpeg', '-i', a, '-i', b, '-lavfi', 'ssim',
                          '-f', 'null', '-'], capture_output=True, text=True)
    m = re.search(r'All:([0-9.]+)', out.stderr)
    return float(m.group(1)) if m else 0.0


def best_crop(src, w, h, reference, tmp):
    """Der quadratische Ausschnitt von [src], der dem 400er am ähnlichsten
    ist: erst die Mitte (so hat das Werkzeug immer beschnitten), sonst
    eine Suche entlang der langen Seite."""
    side = min(w, h)

    def score(x, y):
        ffmpeg('-i', src, '-vf', f'crop={side}:{side}:{x}:{y},scale=400:400',
               f'{tmp}/probe.png')
        return ssim(f'{tmp}/probe.png', reference)

    centre = ((w - side) // 2, (h - side) // 2)
    best = (score(*centre), centre)
    if best[0] >= MIN_SSIM or w == h:
        return best
    span = max(w, h) - side
    for k in range(0, 21):
        off = span * k // 20
        pos = (off, 0) if w > h else (0, off)
        s = score(*pos)
        if s > best[0]:
            best = (s, pos)
    return best


def build_large(out_dir, names):
    os.makedirs(out_dir, exist_ok=True)
    # Außerhalb des Repos: Die Originale sind bis 20 MB je Stück.
    import tempfile
    tmp = tempfile.mkdtemp(prefix='species_large_')
    src_of = sources()
    failed = []
    for name in names:
        page_url = src_of.get(name)
        if not page_url or 'commons.wikimedia.org' not in page_url:
            failed.append(f'{name}: keine Commons-Quelle ({page_url})')
            continue
        title = urllib.parse.unquote(page_url.rsplit('/wiki/', 1)[1])
        page = info([title.replace('_', ' ')], width=2400)[0]
        ii = page['imageinfo'][0]
        url = ii.get('thumburl') or ii['url']
        src = f'{tmp}/{name}.src'
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=120) as r, \
                open(src, 'wb') as f:
            f.write(r.read())
        probe = subprocess.run(['ffprobe', '-v', 'error', '-select_streams',
                                'v:0', '-show_entries', 'stream=width,height',
                                '-of', 'csv=p=0', src],
                               capture_output=True, text=True).stdout.strip()
        w, h = (int(v) for v in probe.split(',')[:2])
        if min(w, h) < MIN_LARGE:
            # Hochrechnen erfände Schärfe, die nicht da ist — dann lieber
            # beim 400er bleiben und es sagen.
            failed.append(f'{name}: Original nur {w}x{h}, zu klein für '
                          f'{MIN_LARGE} (in TOO_SMALL eintragen)')
            continue
        score, (x, y) = best_crop(src, w, h, f'{OUT}/{name}', tmp)
        if score < MIN_SSIM:
            failed.append(f'{name}: kein passender Ausschnitt (SSIM {score:.2f})')
            continue
        side = min(w, h)
        target = min(LARGE, side)
        ffmpeg('-i', src, '-vf',
               f'crop={side}:{side}:{x}:{y},'
               f'scale={target}:{target}:flags=lanczos',
               f'{tmp}/{name}.png')
        dst = os.path.join(out_dir, name)
        subprocess.run(['cwebp', '-q', '80', '-m', '6', '-quiet',
                        f'{tmp}/{name}.png', '-o', dst], check=True)
        print(f'  {name}: {w}x{h} → {target}, Ausschnitt {side}@({x},{y}), '
              f'SSIM {score:.3f}, {os.path.getsize(dst) // 1024} KB')
    for line in failed:
        print(f'  ✗ {line}')
    return failed


def check_large():
    gaps = missing_large()
    if gaps:
        print(f'{len(gaps)} Artbilder ohne große Fassung auf species-photos:')
        for name in gaps:
            print(f'  - {name}')
        print('Nachbauen: python3 tool/species_photos.py --large DIR, dann '
              'auf den Branch legen (pilz-fotos-Skill).')
        sys.exit(1)
    print('Alle Artbilder haben eine große Fassung.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidates', metavar='KATEGORIE')
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--large', metavar='DIR')
    parser.add_argument('--check-large', action='store_true')
    parser.add_argument('names', nargs='*')
    args = parser.parse_args()
    if args.candidates:
        candidates(args.candidates)
    elif args.build:
        build()
    elif args.large:
        failed = build_large(args.large, args.names or missing_large())
        sys.exit(1 if failed else 0)
    elif args.check_large:
        check_large()
    else:
        parser.print_help()
