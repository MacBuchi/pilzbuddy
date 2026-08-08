#!/usr/bin/env python3
"""Baut das Waldtypen-Gitter der App (#213) aus dem Copernicus-HRL
„Dominant Leaf Type" (DLT, 10 m, jährlich).

Läuft in CI (.github/workflows/forest-data.yml), quartalsweise und von
Hand. Ergebnis ist ein Workflow-Artefakt — KEIN Release-Tag: Das Gitter
ist ein Asset im APK, sein Update gehört in einen menschengeprüften PR
mit Versions-Bump (der Changelog-Test erzwingt das ohnehin).

Zwei erklärte Abweichungen von der Stdlib-Regel des Regen-Werkzeugs
(`rain_grid.py`), beide nur im Quartals-Workflow und nie in der App:

1. Der Token-Tausch der CLMS-API ist ein RS256-signiertes JWT →
   `pip install pyjwt cryptography` im Workflow. RSA von Hand wäre
   Leichtsinn. Der Import liegt in der Funktion, damit `--self-test`
   ohne die Pakete läuft (er läuft in „Analyze & Test" mit).
2. Das gelieferte GeoTIFF ist komprimiert und mit ~13 Gigapixeln zu
   groß, um es am Stück zu entpacken (unkomprimiert ~13 GB, der Runner
   trägt das nicht). Deshalb bandweise: `gdal_translate -srcwin` schneidet
   einen unkomprimierten Streifen, der eigene strenge Reader liest ihn,
   aggregiert wird von Hand — GDAL ist nur der Dekompressor, nie der
   Rechner. Wie beim Regen gilt: lieber ablehnen als raten.

Byte-Vertrag je 250-m-Zelle (das Pendant liest
`lib/features/map/forest_grid.dart`):
  0        kein Wald (Baumanteil unter TREE_THRESHOLD)
  1..101   Zelle ist Wald, Wert−1 = Nadelanteil in Prozent
  255      keine Daten (alle Quellpixel außerhalb/unklassifizierbar)

DLT-Pixelwerte der Quelle: 0 = kein Baum, 1 = Laub, 2 = Nadel,
254 = unklassifizierbar, 255 = außerhalb.

Nutzung:
  python3 tool/forest_grid.py --self-test
  python3 tool/forest_grid.py build --source dlt.tif --year 2021 --out build/forest
  python3 tool/forest_grid.py fetch --key service_key.json --out build/forest
  python3 tool/forest_grid.py verify --source dlt.tif --out build/forest
"""

from __future__ import annotations

import argparse
import calendar
import csv
import gzip
import hashlib
import io
import json
import os
import random
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

CLMS_BASE = "https://land.copernicus.eu"

# Ehrlicher Absender für die Downloads — urllib meldet sich sonst als
# „Python-urllib", und genau solche Standard-UAs filtern CDNs gern weg.
USER_AGENT = "pilzbuddy-forest-grid (github.com/MacBuchi/pilzbuddy)"

# DACH — weiter als die Regen-Box: ganz Österreich (bis 17,2° O), die
# Schweiz (ab 45,8° N). west, south, east, north.
BOUNDS = (5.8, 45.7, 17.3, 55.1)

# Aggregation: 25 × 25 Quellpixel (10 m) je Zelle ≈ 250 m.
CELL_FACTOR = 25

# Ab diesem Baumanteil (unter den gültigen Pixeln der Zelle) gilt sie als
# Wald. 20 %: Ein lichter Bestand zählt noch, eine Baumreihe am Feldrand
# nicht mehr. Steht im Manifest, damit die Zahl nie geraten werden muss.
TREE_THRESHOLD = 0.20

NO_DATA = 255
NO_FOREST = 0

# DLT-Klassen der Quelle.
DLT_NO_TREE = 0
DLT_BROADLEAF = 1
DLT_CONIFER = 2


# ---------------------------------------------------------------------------
# Aggregation: DLT-Pixelblock → ein Byte
# ---------------------------------------------------------------------------

def aggregate_block(pixels):
    """Ein Byte für einen Block von DLT-Pixelwerten.

    `pixels` ist eine flache Folge. 254/255 sind keine Aussage und zählen
    nicht als „gültig" — eine Zelle ganz ohne gültige Pixel ist NO_DATA,
    nicht „kein Wald": Der Unterschied entscheidet in der App, ob die
    Ebene schweigt oder „kein Wald" sagt.
    """
    valid = 0
    broadleaf = 0
    conifer = 0
    for value in pixels:
        if value == DLT_NO_TREE:
            valid += 1
        elif value == DLT_BROADLEAF:
            valid += 1
            broadleaf += 1
        elif value == DLT_CONIFER:
            valid += 1
            conifer += 1
    if valid == 0:
        return NO_DATA
    trees = broadleaf + conifer
    if trees / valid < TREE_THRESHOLD:
        return NO_FOREST
    share = round(100 * conifer / trees)
    return 1 + share


# ---------------------------------------------------------------------------
# Kodierung — wortgleich mit rain_grid.py: Zeilen-Delta, dann gzip.
# ---------------------------------------------------------------------------

def encode(rows):
    delta = bytearray()
    for row in rows:
        previous = 0
        for byte in row:
            delta.append((byte - previous) & 0xFF)
            previous = byte
    return gzip.compress(bytes(delta), 9)


def decode(payload, width, height):
    """Referenz-Umkehrung für Tests und verify."""
    flat = gzip.decompress(payload)
    if len(flat) != width * height:
        raise ValueError(f"{len(flat)} Bytes, erwartet {width * height}")
    rows = []
    index = 0
    for _ in range(height):
        previous = 0
        row = bytearray()
        for _ in range(width):
            previous = (previous + flat[index]) & 0xFF
            row.append(previous)
            index += 1
        rows.append(bytes(row))
    return rows


# ---------------------------------------------------------------------------
# Strenger uint8-GeoTIFF-Reader für die unkomprimierten Streifen aus
# gdal_translate. Wie beim Regen: Alles, was nicht exakt dem erwarteten
# Format entspricht, wird abgelehnt statt geraten.
# ---------------------------------------------------------------------------

def read_geotiff_u8(data):
    """Liest ein unkomprimiertes 1-Band-uint8-GeoTIFF (Streifen ODER
    Kacheln). Gibt (rows, transform) zurück; transform ist der
    ModelTransformation/ModelTiepoint-Auszug als (origin_x, origin_y,
    pixel_w, pixel_h)."""
    if data[:2] == b"II":
        endian = "<"
    elif data[:2] == b"MM":
        endian = ">"
    else:
        raise ValueError("kein TIFF")
    magic, offset = struct.unpack(endian + "HI", data[2:8])
    if magic != 42:
        raise ValueError("kein klassisches TIFF")

    (count,) = struct.unpack(endian + "H", data[offset:offset + 2])
    tags = {}
    for i in range(count):
        entry = data[offset + 2 + i * 12:offset + 14 + i * 12]
        tag, kind, num = struct.unpack(endian + "HHI", entry[:8])
        size = {1: 1, 3: 2, 4: 4, 12: 8}.get(kind)
        if size is None:
            continue
        if size * num <= 4:
            raw = entry[8:8 + size * num]
        else:
            (pointer,) = struct.unpack(endian + "I", entry[8:12])
            raw = data[pointer:pointer + size * num]
        fmt = {1: "B", 3: "H", 4: "I", 12: "d"}[kind]
        tags[tag] = struct.unpack(endian + fmt * num, raw)

    width = tags[256][0]
    height = tags[257][0]
    if tags.get(258, (0,))[0] != 8:
        raise ValueError("nicht 8 Bit")
    if tags.get(259, (0,))[0] != 1:
        raise ValueError("komprimiert — erwartet war ein Streifen aus "
                         "gdal_translate -co COMPRESS=NONE")
    if tags.get(277, (1,))[0] != 1:
        raise ValueError("mehr als ein Band")

    rows = [bytearray(width) for _ in range(height)]
    if 322 in tags:  # gekachelt
        tile_w = tags[322][0]
        tile_h = tags[323][0]
        offsets = tags[324]
        across = (width + tile_w - 1) // tile_w
        for index, pointer in enumerate(offsets):
            tx = (index % across) * tile_w
            ty = (index // across) * tile_h
            for line in range(min(tile_h, height - ty)):
                start = pointer + line * tile_w
                chunk = data[start:start + min(tile_w, width - tx)]
                rows[ty + line][tx:tx + len(chunk)] = chunk
    else:  # Streifen
        rows_per_strip = tags.get(278, (height,))[0]
        offsets = tags[273]
        for index, pointer in enumerate(offsets):
            top = index * rows_per_strip
            for line in range(min(rows_per_strip, height - top)):
                start = pointer + line * width
                rows[top + line][:] = data[start:start + width]

    if 34264 in tags:  # ModelTransformation
        t = tags[34264]
        transform = (t[3], t[7], t[0], t[5])
    elif 33922 in tags and 33550 in tags:  # Tiepoint + PixelScale
        tie = tags[33922]
        scale = tags[33550]
        transform = (tie[3], tie[4], scale[0], -scale[1])
    else:
        raise ValueError("keine Georeferenz")
    return [bytes(r) for r in rows], (width, height, transform)


# ---------------------------------------------------------------------------
# GDAL-Umweg: Metadaten und unkomprimierte Streifen
# ---------------------------------------------------------------------------

def gdal_info(path):
    out = subprocess.run(["gdalinfo", "-json", path], capture_output=True,
                         check=True, text=True)
    info = json.loads(out.stdout)
    width, height = info["size"]
    gt = info["geoTransform"]
    return width, height, gt


def gdal_band(path, x, y, w, h, out_path):
    subprocess.run([
        "gdal_translate", "-q", "-srcwin", str(x), str(y), str(w), str(h),
        "-co", "COMPRESS=NONE", "-co", "TILED=NO", path, out_path,
    ], check=True)


# ---------------------------------------------------------------------------
# build: Quell-Raster → Gitter + Manifest
# ---------------------------------------------------------------------------

def build(source, year, out_dir, band_rows=2000,
          info_fn=None, band_fn=None):
    """Aggregiert das (komprimierte) Quell-GeoTIFF bandweise.

    `band_rows` ist ein Vielfaches von CELL_FACTOR (geprüft), damit keine
    Zelle über eine Bandgrenze läuft.
    """
    if band_rows % CELL_FACTOR:
        raise ValueError("band_rows muss ein Vielfaches von CELL_FACTOR sein")
    os.makedirs(out_dir, exist_ok=True)
    info_fn = info_fn or gdal_info
    band_fn = band_fn or gdal_band

    src_w, src_h, gt = info_fn(source)
    # Nur volle Zellen — der Rand, der keine 25 Pixel mehr füllt, fällt weg.
    grid_w = src_w // CELL_FACTOR
    grid_h = src_h // CELL_FACTOR

    grid_rows = []
    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        y = 0
        while y + CELL_FACTOR <= src_h:
            h = min(band_rows, (src_h - y) // CELL_FACTOR * CELL_FACTOR)
            band_fn(source, 0, y, grid_w * CELL_FACTOR, h, strip)
            with open(strip, "rb") as f:
                rows, _ = read_geotiff_u8(f.read())
            for cell_y in range(h // CELL_FACTOR):
                out_row = bytearray(grid_w)
                block_rows = rows[cell_y * CELL_FACTOR:(cell_y + 1) * CELL_FACTOR]
                for cell_x in range(grid_w):
                    x0 = cell_x * CELL_FACTOR
                    pixels = bytearray()
                    for r in block_rows:
                        pixels += r[x0:x0 + CELL_FACTOR]
                    out_row[cell_x] = aggregate_block(pixels)
                grid_rows.append(bytes(out_row))
            y += h
            print(f"  {y}/{src_h} Zeilen", file=sys.stderr)

    payload = encode(grid_rows)
    grid_path = os.path.join(out_dir, "forest_grid.bin.gz")
    with open(grid_path, "wb") as f:
        f.write(payload)

    origin_x, origin_y, px_w, px_h = gt[0], gt[3], gt[1], gt[5]
    west = origin_x
    north = origin_y
    east = origin_x + grid_w * CELL_FACTOR * px_w
    south = origin_y + grid_h * CELL_FACTOR * px_h

    counts = {"no_data": 0, "no_forest": 0, "forest": 0}
    conifer_values = []
    for row in grid_rows:
        for byte in row:
            if byte == NO_DATA:
                counts["no_data"] += 1
            elif byte == NO_FOREST:
                counts["no_forest"] += 1
            else:
                counts["forest"] += 1
                conifer_values.append(byte - 1)
    conifer_values.sort()
    known = counts["no_forest"] + counts["forest"]
    manifest = {
        "source": "Copernicus HRL Dominant Leaf Type",
        "reference_year": year,
        "width": grid_w,
        "height": grid_h,
        "west": round(west, 6),
        "east": round(east, 6),
        "north": round(north, 6),
        "south": round(south, 6),
        "cell_factor": CELL_FACTOR,
        "tree_threshold": TREE_THRESHOLD,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "forest_percent":
            round(100 * counts["forest"] / known, 1) if known else None,
        "median_conifer_percent":
            conifer_values[len(conifer_values) // 2] if conifer_values else None,
    }
    with open(os.path.join(out_dir, "forest_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


# ---------------------------------------------------------------------------
# verify: N Zufallszellen aus dem QUELL-Raster nachrechnen
# ---------------------------------------------------------------------------

def verify(source, out_dir, samples=24, band_fn=None):
    """Rechnet Zellen direkt aus der Quelle nach — fängt Indexfehler und
    verrutschte Geometrie in der Bandschleife.

    Fester Seed wie beim Regen: Eine Prüfung, die jede Nacht andere
    Punkte zieht, scheitert jedes Mal woanders und wird zu Rauschen.

    KEIN GetFeatureInfo-Zweitkanal wie beim Regen: Die anonymen Dienste
    enden 2018 und weichen nach der Borkenkäfer-Kalamität legitim ab.
    Plausibilität stattdessen über den Waldanteil (DACH grob 30–40 %).
    """
    with open(os.path.join(out_dir, "forest_manifest.json")) as f:
        manifest = json.load(f)
    with open(os.path.join(out_dir, "forest_grid.bin.gz"), "rb") as f:
        rows = decode(f.read(), manifest["width"], manifest["height"])

    band_fn = band_fn or gdal_band
    rng = random.Random(20260807)
    mismatches = 0
    with tempfile.TemporaryDirectory() as tmp:
        window = os.path.join(tmp, "window.tif")
        for _ in range(samples):
            cx = rng.randrange(manifest["width"])
            cy = rng.randrange(manifest["height"])
            band_fn(source, cx * CELL_FACTOR, cy * CELL_FACTOR,
                    CELL_FACTOR, CELL_FACTOR, window)
            with open(window, "rb") as f:
                block, _ = read_geotiff_u8(f.read())
            expected = aggregate_block(b"".join(block))
            actual = rows[cy][cx]
            if expected != actual:
                mismatches += 1
                print(f"  Zelle ({cx},{cy}): Gitter {actual}, "
                      f"Quelle {expected}", file=sys.stderr)

    forest_percent = manifest.get("forest_percent")
    report = [
        f"verify: {samples} Zellen, {mismatches} Abweichungen",
        f"Waldanteil: {forest_percent} % "
        f"(plausibel: 25–50), Median Nadel: "
        f"{manifest.get('median_conifer_percent')} %",
    ]
    print("\n".join(report))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("\n".join(report) + "\n")
    if mismatches:
        raise SystemExit("verify: Gitter weicht von der Quelle ab")
    if forest_percent is not None and not 25 <= forest_percent <= 50:
        raise SystemExit(
            f"verify: Waldanteil {forest_percent} % außerhalb 25–50 — "
            "Klassenzuordnung oder Schwelle prüfen")


# ---------------------------------------------------------------------------
# fetch: CLMS-Download-API (braucht Service-Key; nur im Workflow)
# ---------------------------------------------------------------------------

def clms_token(key_path):
    """Service-Key-JSON → kurzlebiges Bearer-Token (RS256-JWT-Grant)."""
    import jwt  # noqa: PLC0415 — bewusst hier, siehe Kopfkommentar

    with open(key_path) as f:
        key = json.load(f)
    now = int(time.time())
    grant = jwt.encode(
        {
            "iss": key["client_id"],
            "sub": key["user_id"],
            "aud": key["token_uri"],
            "iat": now,
            "exp": now + 3600,
        },
        key["private_key"],
        algorithm="RS256",
    )
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": grant,
    }).encode()
    request = urllib.request.Request(
        key["token_uri"], data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)["access_token"]


class ClmsSession:
    """Hält das Bearer-Token frisch, statt eines durchzureichen.

    CLMS-Tokens leben eine Stunde, die Download-Queue braucht gern
    länger: Der erste Echtlauf bestellte korrekt, pollte 61 Minuten
    „In_progress" und starb dann an einem 401 — abgelaufenes Token,
    kein Rechteproblem. fresh() mintet deshalb nach 45 Minuten neu,
    deutlich vor dem Ablauf; ein Mint ist ein einzelner HTTPS-Aufruf.
    """

    refresh_after_seconds = 45 * 60

    def __init__(self, key_path, now_fn=time.time, mint_fn=None):
        # now_fn/mint_fn nur für den Selbsttest — wie info_fn/band_fn
        # beim Build: die Logik läuft netzfrei, der Echtweg unverändert.
        self._now = now_fn
        self._mint = mint_fn or (lambda: clms_token(key_path))
        self._token = None
        self._minted = 0.0

    def fresh(self):
        age = self._now() - self._minted
        if self._token is None or age > self.refresh_after_seconds:
            self._token = self._mint()
            self._minted = self._now()
        return self._token


def clms_json(path, token=None, payload=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode()
    request = urllib.request.Request(CLMS_BASE + path, data=data,
                                     headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # Der Fehlertext der API ist die einzige Diagnose, die es gibt —
        # verschluckt kostete er beim ersten Echtlauf eine ganze Runde.
        body = error.read().decode(errors="replace")[:2000]
        raise SystemExit(
            f"CLMS {error.code} auf {path}\n"
            f"Anfrage: {json.dumps(payload)[:500] if payload else '-'}\n"
            f"Antwort: {body}")


def parse_title_year(title):
    """(offene Reihe?, Jahr) aus dem Katalog-Titel, (False, None) ohne Jahr.

    Die gepflegte Reihe heißt „Dominant Leaf Type 2018-present … yearly"
    — „2018-present" ist kein isdigit()-Wort. Genau daran lief der erste
    Echtlauf vorbei und bestellte den festen Jahrgang 2015.
    """
    open_ended = False
    year = None
    for word in title.replace("(", " ").replace(")", " ").split():
        if word.isdigit() and 2012 <= int(word) <= 2100:
            year = int(word)
        elif word.endswith("-present"):
            head = word[:-len("-present")]
            if head.isdigit() and 2012 <= int(head) <= 2100:
                year = int(head)
                open_ended = True
    return open_ended, year


def pick_download(downloads):
    """Das Geotiff-Download-Item der eigentlichen DLT-Kachel.

    Der Datensatz führt ZWEI Geotiff-Items: die DLT-Werte und den
    Confidence-Layer. „Erstes Geotiff" wäre reine Reihenfolgen-Lotterie
    — deshalb nach der Collection wählen.
    """
    geotiffs = [d for d in downloads if d.get("full_format") == "Geotiff"]
    for d in geotiffs:
        if "leaf type" in (d.get("collection") or "").lower():
            return d
    if geotiffs:
        return geotiffs[0]
    return downloads[0] if downloads else None


def pick_dataset(items):
    """Wählt aus der Katalog-Suche: offene Reihe vor festem Jahrgang.

    Nur die jährlich fortgeschriebene Reihe besteht den Borkenkäfer-Test
    (#213); die festen Jahrgänge 2012/2015 sind 20-m-Altbestand.
    Rückgabe (open_ended, jahr, uid, download_item) oder None.
    """
    best = None
    for item in items:
        title = item.get("title", "").lower()
        if "dominant leaf type" not in title:
            continue
        if "change" in title:
            continue  # die Änderungs-Produkte sind ein anderes Raster
        open_ended, year = parse_title_year(item.get("title", ""))
        if year is None:
            continue
        if best is None or (open_ended, year) > (best[0], best[1]):
            downloads = (item.get("dataset_download_information") or
                         {}).get("items", [])
            best = (open_ended, year, item["UID"], pick_download(downloads))
    return best


def newest_year_in_csv(text):
    """Neuestes Bezugsjahr aus der Granulat-Liste des CDSE-Spiegels."""
    years = set()
    for row in csv.DictReader(io.StringIO(text), delimiter=";"):
        start = (row.get("content_date_start") or "")[:4]
        if start.isdigit():
            years.add(int(start))
    if not years:
        raise SystemExit("fetch: Granulat-Liste ohne Bezugsjahre — "
                         "hat sich das CSV-Format geändert?")
    return max(years)


def newest_reference_year(full_path, fetch_fn=None):
    """Neuestes WIRKLICH vorhandenes Jahr der offenen Reihe.

    Der Katalogeintrag nennt als Abdeckung auch geplante Jahre (Stand
    2026-08 listet er bis „2026", Granulate liegen bis 2024). Was es
    gibt, steht in der Granulat-Liste, auf die full_path zeigt: eine
    HTML-Seite mit einem Link auf ein CSV. Ein geratenes Jahr kostet
    einen ganzen Queue-Umlauf (eine Stunde) — deshalb nachsehen.
    """
    fetch_fn = fetch_fn or _http_text
    page = fetch_fn(full_path)
    match = re.search(r'href="([^"]+\.csv)"', page)
    if not match:
        raise SystemExit("fetch: keine Granulat-Liste unter " + full_path)
    return newest_year_in_csv(fetch_fn(match.group(1)))


def _http_text(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode("utf-8", errors="replace")


def find_dataset(session):
    """Datensatz, Download-Item und echtes Bezugsjahr bestimmen."""
    result = clms_json(
        "/api/@search?portal_type=DataSet"
        "&SearchableText=dominant+leaf+type"
        "&metadata_fields=UID&metadata_fields=dataset_download_information"
        "&b_size=50",
        token=session.fresh())
    best = pick_dataset(result.get("items", []))
    if best is None:
        raise SystemExit("fetch: kein DLT-Datensatz gefunden — "
                         "hat sich die Katalogstruktur geändert?")
    open_ended, year, uid, download = best
    if download is None:
        raise SystemExit("fetch: Datensatz ohne Download-Information — "
                         "Suchantwort prüfen")
    if open_ended:
        full_path = download.get("full_path")
        if not full_path:
            raise SystemExit("fetch: offene Reihe ohne full_path — "
                             "Suchantwort prüfen")
        year = newest_reference_year(full_path)
    return open_ended, year, uid, download["@id"]


def year_window_ms(year):
    """Epoch-Millisekunden [1. Jan, 31. Dez] eines Jahres in UTC.

    Das Format des TemporalFilter laut API-Doku; das Fenster bleibt
    unter deren Grenze von 366 Tagen (download_limit_temporal_extent).
    """
    start = calendar.timegm((year, 1, 1, 0, 0, 0, 0, 0, 0))
    end = calendar.timegm((year, 12, 31, 0, 0, 0, 0, 0, 0))
    return start * 1000, end * 1000


def request_download(session, uid, download_id, year_filter=None):
    west, south, east, north = BOUNDS
    dataset = {
        "DatasetID": uid,
        "DatasetDownloadInformationID": download_id,
        "OutputFormat": "Geotiff",
        "OutputGCS": "EPSG:4326",
        # Reihenfolge nach dem KONKRETEN BEISPIEL der API-Doku:
        # [W, N, E, S]. Deren Prosa behauptet [max.lat, max.lon,
        # min.lat, min.lon] und widerspricht dem eigenen Beispiel
        # ([2.35, 46.85, 4.64, 45.88] ist erkennbar Frankreich,
        # also Länge, Breite, Länge, Breite).
        "BoundingBox": [west, north, east, south],
    }
    if year_filter is not None:
        # Ohne Zeitfenster wäre bei der Jahres-Reihe unklar, welcher
        # Jahrgang kommt — dieselbe stille Falle wie beim Regen-WCS
        # (dort verschmolz GeoServer kommentarlos alle Granulate).
        start, end = year_window_ms(year_filter)
        dataset["TemporalFilter"] = {"StartDate": start, "EndDate": end}
    result = clms_json("/api/@datarequest_post", token=session.fresh(),
                       payload={"Datasets": [dataset]})
    return str(result["TaskIds"][0]["TaskID"]) if "TaskIds" in result \
        else str(result["TaskID"])


def poll_download(session, task_id, timeout_minutes=120):
    deadline = time.time() + timeout_minutes * 60
    while time.time() < deadline:
        status = clms_json("/api/@datarequest_status_get?TaskID=" + task_id,
                           token=session.fresh())
        state = status.get("Status", status.get("status", ""))
        if state.lower() in ("finished_ok", "finished", "done"):
            return status["DownloadURL"]
        if state.lower() in ("finished_nok", "cancelled", "rejected"):
            raise SystemExit(f"fetch: Auftrag {task_id} gescheitert: {status}")
        print(f"  Warte auf Auftrag {task_id}: {state}", file=sys.stderr)
        time.sleep(60)
    raise SystemExit("fetch: Zeitüberschreitung beim Warten auf den Download")


def download_archive(url, archive, attempts=10, sleep_fn=time.sleep,
                     open_fn=None):
    """Lädt das Ergebnis-Zip — mit Wiederholung im Minutenabstand.

    Der dritte Echtlauf bekam auf die frisch gemeldete DownloadURL ein
    403; dieselbe URL lieferte Minuten später anonym 200 mit vollem
    Inhalt. FME meldet den Auftrag also fertig, bevor die Datei
    abrufbar ist. Ein hartes 403 (etwa IP-Sperre) fällt nach zehn
    Versuchen trotzdem auf — mitsamt letztem Fehler.
    """
    open_fn = open_fn or _open_stream
    last = None
    for attempt in range(attempts):
        if attempt:
            sleep_fn(60)
        try:
            stream = open_fn(url)
        except urllib.error.HTTPError as error:
            last = f"HTTP {error.code}"
        except urllib.error.URLError as error:
            last = str(error.reason)
        else:
            with stream, open(archive, "wb") as out:
                shutil.copyfileobj(stream, out, 1024 * 1024)
            return
        print(f"  Download-Versuch {attempt + 1}/{attempts}: {last}",
              file=sys.stderr)
    raise SystemExit(
        f"fetch: Download nach {attempts} Versuchen gescheitert ({last})")


def _open_stream(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    return urllib.request.urlopen(request, timeout=600)


def fetch(key_path, out_dir):
    session = ClmsSession(key_path)
    open_ended, year, uid, download_id = find_dataset(session)
    print(f"fetch: DLT {year} (UID {uid}, Download {download_id}, "
          f"{'offene Reihe' if open_ended else 'fester Jahrgang'})",
          file=sys.stderr)
    if not download_id:
        raise SystemExit("fetch: Datensatz ohne Download-Information — "
                         "Suchantwort prüfen")
    task = request_download(session, uid, download_id,
                            year_filter=year if open_ended else None)
    url = poll_download(session, task)
    os.makedirs(out_dir, exist_ok=True)
    archive = os.path.join(out_dir, "dlt_download.zip")
    print(f"fetch: lade {url}", file=sys.stderr)
    download_archive(url, archive)
    print(f"fetch: {os.path.getsize(archive)} Bytes", file=sys.stderr)
    subprocess.run(["unzip", "-o", "-d",
                    os.path.join(out_dir, "dlt_source"), archive], check=True)
    tifs = []
    for root, _, files in os.walk(os.path.join(out_dir, "dlt_source")):
        tifs += [os.path.join(root, f) for f in files
                 if f.lower().endswith((".tif", ".tiff"))]
    if not tifs:
        raise SystemExit("fetch: kein GeoTIFF im Download")
    if len(tifs) > 1:
        # Mehrere Kacheln → zu einem virtuellen Raster zusammenfassen.
        vrt = os.path.join(out_dir, "dlt_source.vrt")
        subprocess.run(["gdalbuildvrt", vrt] + sorted(tifs), check=True)
        source = vrt
    else:
        source = tifs[0]
    print(f"fetch: Quelle {source}", file=sys.stderr)
    return source, year


# ---------------------------------------------------------------------------
# Selbsttest — netzfrei, ohne GDAL, ohne pyjwt.
# ---------------------------------------------------------------------------

def _fake_tiff_u8(rows, tiled=False):
    """Minimales unkomprimiertes uint8-TIFF, little-endian, Streifen."""
    width = len(rows[0])
    height = len(rows)
    pixel_data = b"".join(bytes(r) for r in rows)
    # Header (8) + Pixel + IFD danach.
    data_offset = 8
    ifd_offset = data_offset + len(pixel_data)
    tags = [
        (256, 3, 1, width),
        (257, 3, 1, height),
        (258, 3, 1, 8),
        (259, 3, 1, 1),
        (262, 3, 1, 1),
        (273, 4, 1, data_offset),
        (277, 3, 1, 1),
        (278, 3, 1, height),
        (279, 4, 1, len(pixel_data)),
    ]
    # Georeferenz: Tiepoint (0,0 → 10° O, 55° N) + PixelScale, als
    # nachgestellte Double-Blöcke. Der Offset ist NACHGERECHNET, nicht
    # geschätzt: IFD = Zähler (2) + Einträge (n × 12) + Nächster-IFD-
    # Zeiger (4); die Blöcke folgen direkt dahinter.
    total_tags = len(tags) + 2
    extra_offset = ifd_offset + 2 + total_tags * 12 + 4
    tie = struct.pack("<6d", 0, 0, 0, 10.0, 55.0, 0)
    scale = struct.pack("<3d", 0.0001, 0.0001, 0)
    all_tags = tags + [
        (33550, 12, 3, extra_offset),
        (33922, 12, 6, extra_offset + len(scale)),
    ]
    all_tags.sort()
    out = bytearray(b"II*\x00")
    out += struct.pack("<I", ifd_offset)
    out += pixel_data
    out += struct.pack("<H", len(all_tags))
    for tag, kind, num, value in all_tags:
        out += struct.pack("<HHI", tag, kind, num)
        out += struct.pack("<I", value)
    out += struct.pack("<I", 0)
    out += scale
    out += tie
    return bytes(out)


def self_test():
    # Kodierung: Roundtrip mit Zeilen, die verschieden anfangen.
    rows = [bytes([0, 50, 101]), bytes([101, 1, 0]), bytes([255, 255, 80])]
    assert decode(encode(rows), 3, 3) == rows
    try:
        decode(encode(rows), 2, 2)
        raise AssertionError("falsche Größe nicht erkannt")
    except ValueError:
        pass

    # Aggregation: der Byte-Vertrag.
    assert aggregate_block([255] * 625) == NO_DATA
    assert aggregate_block([254] * 625) == NO_DATA
    assert aggregate_block([0] * 625) == NO_FOREST
    # 19 % Baum → kein Wald; 20 % → Wald.
    assert aggregate_block([1] * 19 + [0] * 81) == NO_FOREST
    assert aggregate_block([1] * 20 + [0] * 80) == 1  # 0 % Nadel
    assert aggregate_block([2] * 20 + [0] * 80) == 101  # 100 % Nadel
    assert aggregate_block([1] * 10 + [2] * 10 + [0] * 80) == 51  # 50 %
    # Ungültige Pixel verschieben den Anteil nicht.
    assert aggregate_block([1] * 10 + [2] * 10 + [255] * 80) == 51

    # Reader: Roundtrip über das Fake-TIFF, inkl. Georeferenz.
    tiff = _fake_tiff_u8(rows)
    read_rows, (w, h, transform) = read_geotiff_u8(tiff)
    assert read_rows == rows, read_rows
    assert (w, h) == (3, 3)
    assert transform[0] == 10.0 and transform[1] == 55.0
    assert abs(transform[2] - 0.0001) < 1e-12
    assert transform[3] < 0, "Pixelhöhe muss nach Süden zeigen"
    # Ablehnungen.
    for broken in [b"PNG?", tiff[:40]]:
        try:
            read_geotiff_u8(broken)
            raise AssertionError("kaputtes TIFF nicht erkannt")
        except (ValueError, struct.error, KeyError, IndexError):
            pass

    # Anfragebau: Bounding Box in API-Reihenfolge [W, N, E, S] — die
    # des BEISPIELS der Doku, nicht ihrer (widersprüchlichen) Prosa.
    west, south, east, north = BOUNDS
    assert north > south and east > west
    box = [west, north, east, south]
    assert box[0] == 5.8 and box[1] == 55.1

    # Die Kachel-Rechnung: 25er-Blöcke, Rand fällt weg.
    assert 107 // CELL_FACTOR == 4

    # Datensatz-Wahl: Die offene Reihe („2018-present") schlägt jeden
    # festen Jahrgang — der erste Echtlauf bestellte 2015, weil ihr
    # Titel kein isdigit()-Jahr trägt und sie übersprungen wurde.
    assert parse_title_year("Dominant Leaf Type 2015 (raster 20 m)") == \
        (False, 2015)
    assert parse_title_year(
        "Dominant Leaf Type 2018-present (raster 10 m), Europe, yearly") == \
        (True, 2018)
    assert parse_title_year("Dominant Leaf Type") == (False, None)
    items = [
        {"title": "Dominant Leaf Type 2015 (raster 20 m)", "UID": "alt",
         "dataset_download_information": {"items": [
             {"@id": "alt-dl", "full_format": "Geotiff",
              "collection": "Dominant Leaf Type"}]}},
        {"title": "Dominant Leaf Type Change 2018-2021", "UID": "change",
         "dataset_download_information": {"items": []}},
        {"title": "Dominant Leaf Type 2018-present (raster 10 m), yearly",
         "UID": "reihe",
         "dataset_download_information": {"items": [
             # Confidence-Layer ZUERST — die Wahl darf nicht an der
             # Reihenfolge hängen.
             {"@id": "conf-dl", "full_format": "Geotiff",
              "collection": "Confidence Layer"},
             {"@id": "dlt-dl", "full_format": "Geotiff",
              "collection": "Dominant Leaf Type",
              "full_path": "https://beispiel/pfad/"}]}},
    ]
    open_ended, year, uid, download = pick_dataset(items)
    assert (open_ended, year, uid) == (True, 2018, "reihe"), (year, uid)
    assert download["@id"] == "dlt-dl", download

    # Bezugsjahr: aus der Granulat-Liste, nicht aus der Plan-Abdeckung.
    csv_text = ("id;name;content_date_start;s3_path\n"
                "a;K1;2018-01-01T00:00:00.000;s3://x\n"
                "b;K2;2024-01-01T00:00:00.000;s3://y\n"
                "c;K3;2021-01-01T00:00:00.000;s3://z\n")
    assert newest_year_in_csv(csv_text) == 2024
    try:
        newest_year_in_csv("id;name\n1;kaputt\n")
        raise AssertionError("leere Jahresliste nicht erkannt")
    except SystemExit:
        pass
    pages = {"seite": '<a href="https://s3/granulate.csv">liste</a>',
             "https://s3/granulate.csv": csv_text}
    assert newest_reference_year("seite", fetch_fn=pages.__getitem__) == 2024

    # Zeitfenster: Epoch-Millisekunden in UTC, Jahresanfang und -ende.
    start, end = year_window_ms(2024)
    assert start == 1704067200000, start  # 2024-01-01T00:00:00Z
    assert end == 1735603200000, end      # 2024-12-31T00:00:00Z
    assert end - start < 366 * 86400 * 1000

    # Download-Retry: 403 beim Fertigmelden ist ein Race, kein Urteil —
    # der dritte Echtlauf scheiterte daran, Minuten später kam 200.
    calls = []

    def _flaky_open(_url):
        calls.append("versuch")
        if len(calls) < 3:
            raise urllib.error.HTTPError("u", 403, "Forbidden", None, None)
        return io.BytesIO(b"zipdaten")

    naps = []
    with tempfile.TemporaryDirectory() as tmp:
        target = os.path.join(tmp, "a.zip")
        download_archive("u", target, attempts=5,
                         sleep_fn=naps.append, open_fn=_flaky_open)
        with open(target, "rb") as f:
            assert f.read() == b"zipdaten"
    assert len(calls) == 3 and naps == [60, 60], (calls, naps)

    def _dead_open(_url):
        raise urllib.error.HTTPError("u", 403, "Forbidden", None, None)

    try:
        download_archive("u", "/unbenutzt", attempts=2,
                         sleep_fn=lambda _s: None, open_fn=_dead_open)
        raise AssertionError("hartes 403 nicht gemeldet")
    except SystemExit as error:
        assert "403" in str(error)

    # Token-Verwaltung: Der erste Echtlauf bestellte korrekt, pollte
    # 61 Minuten und starb an einem 401 — das Token lebt nur eine
    # Stunde. fresh() muss also innerhalb der Frist dasselbe Token
    # liefern (kein Mint je Anfrage) und nach der Frist neu minten.
    clock = [0.0]
    mints = []

    def _fake_mint():
        mints.append(clock[0])
        return f"token-{len(mints)}"

    session = ClmsSession("unbenutzt", now_fn=lambda: clock[0],
                          mint_fn=_fake_mint)
    assert session.fresh() == "token-1"
    clock[0] = ClmsSession.refresh_after_seconds - 1
    assert session.fresh() == "token-1", "vor der Frist neu gemintet"
    clock[0] = ClmsSession.refresh_after_seconds + 1
    assert session.fresh() == "token-2", "nach der Frist nicht erneuert"
    assert mints == [0.0, ClmsSession.refresh_after_seconds + 1]

    _self_test_build()

    print("self-test: ok")


def _self_test_build():
    """Build + verify einmal komplett, mit gefakten GDAL-Aufrufen — die
    Bandschleife, der Zellzusammenbau und die Manifest-Ecken sind sonst
    erst im Echtlauf dran, und dort ist ein Indexfehler nicht von einer
    komischen Quelle zu unterscheiden."""
    # Synthetische Quelle: 100 × 75 Pixel → 4 × 3 Zellen. Jede Zelle
    # bekommt ein bekanntes Muster; Zelle (0,0) reiner Nadelwald, (1,0)
    # reines Laub, (2,0) 50/50, (3,0) baumlos, zweite Zeile NO_DATA,
    # dritte Zeile wieder Wald — Waldanteil unter den bekannten Zellen:
    # 7 von 8 = 87,5 %? Nein: verify prüft 25–50 — deshalb unten mehr
    # baumlose Zellen.
    patterns = [
        [2, 1, [1, 2], 0],       # Nadel, Laub, Misch, baumlos
        [255, 255, 255, 255],    # keine Daten
        [0, 0, [1, 2], 0],       # baumlos, baumlos, Misch, baumlos
    ]
    src_rows = []
    for cell_row in patterns:
        for _ in range(CELL_FACTOR):
            row = bytearray()
            for pattern in cell_row:
                if isinstance(pattern, list):
                    for i in range(CELL_FACTOR):
                        row.append(pattern[i % len(pattern)])
                else:
                    row += bytes([pattern]) * CELL_FACTOR
            src_rows.append(bytes(row))

    def info_fn(_source):
        return 100, 75, [10.0, 0.0001, 0, 55.0, 0, -0.0001]

    def band_fn(_source, x, y, w, h, out_path):
        window = [r[x:x + w] for r in src_rows[y:y + h]]
        with open(out_path, "wb") as f:
            f.write(_fake_tiff_u8(window))

    import tempfile as _tempfile
    with _tempfile.TemporaryDirectory() as out:
        manifest = build("fake", 2021, out, band_rows=50,
                         info_fn=info_fn, band_fn=band_fn)
        assert (manifest["width"], manifest["height"]) == (4, 3), manifest
        assert manifest["west"] == 10.0 and manifest["north"] == 55.0
        assert abs(manifest["east"] - 10.01) < 1e-9
        assert abs(manifest["south"] - 54.9925) < 1e-9
        with open(os.path.join(out, "forest_grid.bin.gz"), "rb") as f:
            rows = decode(f.read(), 4, 3)
        # Das 1/2-Wechselmuster ist bei 25 Pixeln je Zeile UNGERADE:
        # 13 Laub + 12 Nadel je Zeile, über 25 Zeilen 325:300 →
        # 300/625 = 48 % Nadel → Byte 49. Wer hier 51 erwartet, hat
        # die ungerade Kachelbreite übersehen (so geschehen).
        assert rows[0] == bytes([101, 1, 49, 0]), rows[0]
        assert rows[1] == bytes([255] * 4), rows[1]
        assert rows[2] == bytes([0, 0, 49, 0]), rows[2]
        # Waldanteil: 4 Wald von 4+4=8 bekannten Zellen = 50 % → passiert
        # die Plausibilität knapp.
        assert manifest["forest_percent"] == 50.0, manifest

        verify("fake", out, samples=12, band_fn=band_fn)

        # Gegenprobe: ein verfälschtes Gitter fällt auf. ALLE Zellen
        # verfälscht, nicht eine — eine einzelne können die Stichproben
        # verfehlen (mit diesem Seed taten sie es). verify fängt
        # SYSTEMATISCHE Fehler (verrutschte Geometrie, vertauschte
        # Klassen), keine Einzelzelle.
        broken = [bytes([7] * len(r)) for r in rows]
        with open(os.path.join(out, "forest_grid.bin.gz"), "wb") as f:
            f.write(encode(broken))
        try:
            verify("fake", out, samples=12, band_fn=band_fn)
            raise AssertionError("verify hat das kaputte Gitter geschluckt")
        except SystemExit:
            pass


# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", nargs="?", default="",
                        choices=["", "build", "fetch", "verify"])
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--source")
    parser.add_argument("--year", type=int)
    parser.add_argument("--key")
    parser.add_argument("--out", default="build/forest")
    parser.add_argument("--samples", type=int, default=24)
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if args.command == "build":
        manifest = build(args.source, args.year, args.out)
        print(json.dumps(manifest, indent=2))
    elif args.command == "fetch":
        source, year = fetch(args.key, args.out)
        manifest = build(source, year, args.out)
        print(json.dumps(manifest, indent=2))
        verify(source, args.out, samples=args.samples)
    elif args.command == "verify":
        verify(args.source, args.out, samples=args.samples)
    else:
        parser.error("Kommando oder --self-test angeben")


if __name__ == "__main__":
    main()
