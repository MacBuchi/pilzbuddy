#!/usr/bin/env python3
"""Spots für die Store-Screenshots anlegen — und sie dorthin setzen, wo
sie im BILD stehen sollen.

Warum das ein Werkzeug ist und kein Handgriff: Ein Screenshot der Karte
soll mehrere Arten zeigen, die einander nicht überdecken und die weder
in der FAB-Spalte noch unter dem „Neuer Spot"-Knopf oder dem Hinweisband
verschwinden. Von Hand in die Karte getippt trifft man das nicht
reproduzierbar — und beim nächsten Mal schon gar nicht wieder.

Der Weg stattdessen: zwei sichtbare Marker im laufenden Emulator
ausmessen, daraus die Abbildung Pixel↔Grad bestimmen, sie umkehren und
jeden Spot auf seine Ziel-Pixelposition setzen.

    # 1. anlegen (irgendwo in der Gegend, Position folgt)
    PB_EMAIL=… PB_PASSWORD=… python3 tool/seed_screenshot_data.py --seed

    # 2. aufnehmen, im Bild zwei Marker ausmessen, dann setzen
    python3 tool/seed_screenshot_data.py --place \
        --ref 47.9040,8.1245=175,612 --ref 47.9015,8.1300=845,1065

    # 3. hinterher
    python3 tool/seed_screenshot_data.py --cleanup

Die Zugangsdaten des Testkontos stehen im Austauschordner
(`Claude_exchange/Testkonten.md`) und gehören NICHT hierher.

Nur Standardbibliothek, wie feedback_bot.py und rain_grid.py.
"""

import argparse
import json
import math
import os
import sys
import urllib.error
import urllib.request

URL = 'https://tntlujexvdtkynxbrdsn.supabase.co'
# Derselbe öffentliche Publishable Key wie in lib/core/supabase_config.dart —
# die Sicherheit liegt in den RLS-Policies, nicht in diesem Wert.
KEY = 'sb_publishable_uJvwpsHNh3lkD7gd-8Ym2Q_t7TBnqpO'

# Gegend um Titisee-Neustadt im Schwarzwald. Bewusst NICHT die Ecke, in
# der jemand wirklich sammelt: Die Bilder gehen in den Store, und ein
# echter Fundort gehört dort nicht hin (store/README.md).
FALLBACK_CENTER = (47.9025, 8.1275)

# Je Eintrag eine ANDERE Artengruppe — die Gruppe bestimmt das Icon
# (lib/core/mushroom_species.dart), zwei Röhrlinge nebeneinander sähen
# aus wie zweimal dasselbe. Die Pixelwerte gelten für 1080x1920 und
# halten Abstand zur FAB-Spalte (x ab ~915), zum „Neuer Spot"-Knopf
# (unten rechts), zum Hinweisband (unten links) und zum eigenen
# Standort in der Bildmitte.
LAYOUT = [
    # Name,                 Art,              Anzahl, Ziel-Pixel
    ('Am Winterhaldenweg', 'Pfifferling',     23, (180, 430)),
    ('Buchenhang',         'Steinpilz',        7, (520, 400)),
    ('Lichtung Oberau',    'Parasol',          3, (800, 470)),
    ('Alter Bachlauf',     'Krause Glucke',    1, (300, 730)),
    ('Fichtenschonung',    'Perlpilz',         5, (700, 1150)),
    ('Bergackerweg',       'Riesenbovist',     2, (330, 1250)),
]

FOUND_ON = '2026-08-20'


# --------------------------------------------------------------- Geometrie

class Projection:
    """Abbildung Pixel↔Grad, aus zwei ausgemessenen Markern bestimmt.

    Die Karte steht nordwärts, es braucht also keine Drehung: x hängt
    allein an der Länge, y allein an der Breite.
    """

    def __init__(self, ref_a, ref_b):
        (lat_a, lon_a), (x_a, y_a) = ref_a
        (lat_b, lon_b), (x_b, y_b) = ref_b
        if lon_a == lon_b or lat_a == lat_b:
            raise SystemExit('Die zwei Bezugspunkte müssen sich in Breite '
                             'UND Länge unterscheiden.')
        self.px_per_lon = (x_b - x_a) / (lon_b - lon_a)
        self.px_per_lat = (y_b - y_a) / (lat_b - lat_a)   # negativ: y wächst südwärts
        self.x0, self.lon0 = x_a, lon_a
        self.y0, self.lat0 = y_a, lat_a
        self.lat_mid = (lat_a + lat_b) / 2

    def to_degrees(self, px_x, px_y):
        lon = self.lon0 + (px_x - self.x0) / self.px_per_lon
        lat = self.lat0 + (px_y - self.y0) / self.px_per_lat
        return round(lat, 6), round(lon, 6)

    def to_pixels(self, lat, lon):
        return (self.x0 + (lon - self.lon0) * self.px_per_lon,
                self.y0 + (lat - self.lat0) * self.px_per_lat)

    def plausibility(self):
        """Wie gut die Messung zur Mercator-Erwartung passt.

        In Mercator kostet ein Grad Breite um 1/cos(Breite) mehr Pixel
        als ein Grad Länge. Weicht das Gemessene stark davon ab, ist ein
        Bezugspunkt falsch abgelesen — der häufigste Fehler, und einer,
        der sonst erst am krumm liegenden Bild auffällt.
        """
        measured = abs(self.px_per_lat) / abs(self.px_per_lon)
        expected = 1 / math.cos(math.radians(self.lat_mid))
        return measured, expected, abs(measured - expected) / expected


def parse_ref(text):
    """„47.9040,8.1245=175,612" → ((lat, lon), (x, y))"""
    try:
        degrees, pixels = text.split('=')
        lat, lon = (float(v) for v in degrees.split(','))
        x, y = (float(v) for v in pixels.split(','))
    except ValueError:
        raise SystemExit(f'--ref erwartet lat,lon=x,y — bekam: {text}')
    return (lat, lon), (x, y)


# ------------------------------------------------------------------- API

def request(method, path, payload=None, token=None, prefer=None):
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {'apikey': KEY, 'Content-Type': 'application/json',
               'Authorization': f'Bearer {token or KEY}'}
    if prefer:
        headers['Prefer'] = prefer
    req = urllib.request.Request(URL + path, data=data, headers=headers,
                                 method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            body = response.read().decode()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        raise SystemExit(f'{method} {path} → {error.code}: '
                         f'{error.read().decode()[:200]}')


def sign_in():
    email = os.environ.get('PB_EMAIL')
    password = os.environ.get('PB_PASSWORD')
    if not email or not password:
        raise SystemExit('PB_EMAIL und PB_PASSWORD setzen (Testkonto, siehe '
                         'Austauschordner). Nie ein echtes Konto benutzen — '
                         'sonst stehen eigene Fundorte im Store.')
    auth = request('POST', '/auth/v1/token?grant_type=password',
                   {'email': email, 'password': password})
    return auth['access_token'], auth['user']['id']


def own_spots(token, uid):
    return request('GET', f'/rest/v1/spots?owner_id=eq.{uid}'
                          '&select=id,name,lat,lng', token=token)


def by_name(rows):
    """Nur die BENANNTEN Spots, nach Namen greifbar.

    Ein Spot darf namenlos sein — das Anlege-Blatt verlangt keinen Namen.
    Die hier landeten sonst alle unter demselben Schlüssel `None` und
    verdeckten einander; und weil dieses Werkzeug ausschließlich über
    seine eigenen Namen aus [LAYOUT] greift, fehlt ihm nichts.
    """
    return {row['name']: row for row in rows if row['name']}


# --------------------------------------------------------------- Befehle

def cmd_seed(token, uid):
    existing = by_name(own_spots(token, uid))
    lat, lon = FALLBACK_CENTER
    for index, (name, species, count, _) in enumerate(LAYOUT):
        if name in existing:
            print(f'  steht schon: {name}')
            continue
        # Vorläufig fächerförmig ablegen; --place rückt sie danach
        # dorthin, wo sie im Bild stehen sollen.
        spot = request('POST', '/rest/v1/spots',
                       {'owner_id': uid, 'name': name,
                        'lat': round(lat + 0.001 * index, 6),
                        'lng': round(lon + 0.001 * index, 6)},
                       token, prefer='return=representation')[0]
        request('POST', '/rest/v1/finds',
                [{'spot_id': spot['id'], 'species': species, 'count': count,
                  'found_on': FOUND_ON, 'blank': False}], token)
        print(f'  angelegt:    {name:22s} {species}')


def cmd_place(token, uid, refs):
    projection = Projection(*refs)
    measured, expected, deviation = projection.plausibility()
    print(f'Abbildung: {projection.px_per_lon:.0f} px/Grad Länge, '
          f'{abs(projection.px_per_lat):.0f} px/Grad Breite')
    print(f'  Verhältnis {measured:.3f}, Mercator erwartet {expected:.3f} '
          f'({deviation * 100:.1f} % Abweichung)')
    if deviation > 0.05:
        print('  ! Mehr als 5 % daneben — ist ein Bezugspunkt falsch '
              'abgelesen?', file=sys.stderr)

    spots = by_name(own_spots(token, uid))
    for name, species, count, (px, py) in LAYOUT:
        spot = spots.get(name)
        if not spot:
            print(f'  ! kein Spot namens {name} — erst --seed', file=sys.stderr)
            continue
        lat, lon = projection.to_degrees(px, py)
        request('PATCH', f"/rest/v1/spots?id=eq.{spot['id']}",
                {'lat': lat, 'lng': lon}, token)
        request('PATCH', f"/rest/v1/finds?spot_id=eq.{spot['id']}",
                {'species': species, 'count': count}, token)
        print(f'  {name:22s} Pixel({px:4d},{py:4d})  {lat}, {lon}')
    print('Gesetzt. Jetzt `tool/store_screenshots.sh restart`, sonst zeigt '
          'die App noch die alten Positionen.')


def cmd_cleanup(token, uid):
    spots = by_name(own_spots(token, uid))
    for name, *_ in LAYOUT:
        spot = spots.get(name)
        if not spot:
            continue
        # Die Funde hängen per `on delete cascade` am Spot.
        request('DELETE', f"/rest/v1/spots?id=eq.{spot['id']}", token=token)
        print(f'  gelöscht: {name}')


def cmd_list(token, uid):
    ours = {row[0] for row in LAYOUT}
    rows = own_spots(token, uid)
    # Namenlose Spots gibt es wirklich — nach `(name or '')` sortieren,
    # sonst vergleicht `sorted` None mit str und bricht ab.
    for spot in sorted(rows, key=lambda row: (row['name'] or '').lower()):
        name = spot['name'] or '(ohne Namen)'
        marker = '*' if spot['name'] in ours else ' '
        print(f' {marker} {name:24s} {spot["lat"]}, {spot["lng"]}')
    print(f'\n{len(rows)} Spots, * = Screenshot-Spot dieses Werkzeugs')


def self_test():
    """Netzfrei: die Umkehrung muss treffen, und der Plausibilitätstest
    muss einen falsch abgelesenen Bezugspunkt auch wirklich melden."""
    refs = (((47.9040, 8.1245), (175, 612)),
            ((47.9015, 8.1300), (845, 1065)))
    projection = Projection(*refs)

    # Hin und zurück: was auf Pixel (x, y) gesetzt wird, muss dort landen.
    for px, py in [(180, 430), (800, 470), (330, 1250)]:
        lat, lon = projection.to_degrees(px, py)
        back_x, back_y = projection.to_pixels(lat, lon)
        assert abs(back_x - px) < 0.5, (px, back_x)
        assert abs(back_y - py) < 0.5, (py, back_y)

    # Die Bezugspunkte selbst bleiben, wo sie gemessen wurden.
    for (lat, lon), (px, py) in refs:
        back_x, back_y = projection.to_pixels(lat, lon)
        assert abs(back_x - px) < 0.5 and abs(back_y - py) < 0.5

    # Nordwärts ist im Bild oben: mehr Breite, kleineres y.
    assert projection.px_per_lat < 0
    assert projection.to_degrees(0, 0)[0] > projection.to_degrees(0, 500)[0]

    # Diese Messung ist gut (unter 1 % daneben) …
    _, _, deviation = projection.plausibility()
    assert deviation < 0.01, deviation

    # … und ein um 200 px verlesener Bezugspunkt fällt auf.
    wrong = Projection(refs[0], ((47.9015, 8.1300), (845, 1265)))
    assert wrong.plausibility()[2] > 0.05

    # Zwei Punkte auf derselben Breite tragen keine Abbildung.
    try:
        Projection(((47.9, 8.1), (0, 0)), ((47.9, 8.2), (100, 0)))
    except SystemExit:
        pass
    else:
        raise AssertionError('entartete Bezugspunkte nicht erkannt')

    print('seed_screenshot_data self-test: ok')


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--seed', action='store_true',
                        help='fehlende Screenshot-Spots anlegen')
    parser.add_argument('--place', action='store_true',
                        help='Spots auf ihre Ziel-Pixelpositionen setzen')
    parser.add_argument('--ref', action='append', default=[], metavar='lat,lon=x,y',
                        help='ausgemessener Marker; genau zwei für --place')
    parser.add_argument('--cleanup', action='store_true',
                        help='die Screenshot-Spots wieder löschen')
    parser.add_argument('--list', action='store_true',
                        help='Spots des Kontos zeigen')
    parser.add_argument('--self-test', action='store_true',
                        help='netzfreier Selbsttest der Geometrie')
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if not (args.seed or args.place or args.cleanup or args.list):
        parser.print_help()
        return
    if args.place and len(args.ref) != 2:
        raise SystemExit('--place braucht genau zwei --ref.')

    token, uid = sign_in()
    if args.seed:
        cmd_seed(token, uid)
    if args.place:
        cmd_place(token, uid, [parse_ref(text) for text in args.ref])
    if args.cleanup:
        cmd_cleanup(token, uid)
    if args.list:
        cmd_list(token, uid)


if __name__ == '__main__':
    main()
