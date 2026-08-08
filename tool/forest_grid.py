#!/usr/bin/env python3
"""Baut das Waldtypen-Gitter der App (#213) aus dem Copernicus-HRL
„Dominant Leaf Type" (DLT, 10 m, jährlich).

Läuft in CI (.github/workflows/forest-data.yml), quartalsweise und von
Hand. Ergebnis ist ein Workflow-Artefakt — KEIN Release-Tag: Das Gitter
ist ein Asset im APK, sein Update gehört in einen menschengeprüften PR
mit Versions-Bump (der Changelog-Test erzwingt das ohnehin).

Datenweg (Standard): **Direktdownload** der COG-Kacheln aus dem
CDSE-Objektspeicher (s3://eodata) — die anonyme Granulat-Liste nennt
Kacheln, Größen, MD5 und Bounding Boxes, bestellt wird nichts. Braucht
das CDSE-S3-Schlüsselpaar (Secrets CDSE_S3_ACCESS_KEY/_SECRET_KEY).
Der frühere Bestell-Weg über die CLMS-Download-API (`fetch-order`,
Secret CLMS_SERVICE_KEY) bleibt übergangsweise erhalten; warum er
verlassen wurde, dokumentieren die sechs Echtläufe in der Git-Historie
(FME-Queue mit Stunden-Latenz, bei jedem Quartalslauf erneut).

Erklärte Abweichungen von der Stdlib-Regel des Regen-Werkzeugs
(`rain_grid.py`), alle nur im Quartals-Workflow und nie in der App:

1. Nur noch fetch-order: Der Token-Tausch der CLMS-API ist ein
   RS256-signiertes JWT → `pip install pyjwt cryptography` im Workflow.
   RSA von Hand wäre Leichtsinn. Der Import liegt in der Funktion,
   damit `--self-test` ohne die Pakete läuft. Stirbt mit fetch-order.
2. GDAL als Dekompressor UND Reprojektor: Die Kacheln sind EPSG:3035
   (LAEA) und die App rechnet linear in Grad — `gdalwarp -r near`
   macht daraus einmal ein EPSG:4326-Raster (nearest, weil die Werte
   Klassen sind). Danach bandweise `gdal_translate -srcwin`, der
   eigene strenge Reader, Aggregation von Hand — GDAL ist nie der
   Rechner, und --verify rechnet gegen das gewarpte Raster nach.
   Der Download läuft über die AWS-CLI (auf den Runnern
   vorinstalliert), verifiziert per MD5 aus der Granulat-Liste.

Byte-Vertrag je 250-m-Zelle (das Pendant liest
`lib/features/map/forest_grid.dart`):
  0        kein Wald (Baumanteil unter TREE_THRESHOLD)
  1..101   Zelle ist Wald, Wert−1 = Nadelanteil in Prozent
  255      keine Daten (alle Quellpixel außerhalb/unklassifizierbar)

DLT-Pixelwerte der Quelle: 0 = kein Baum, 1 = Laub, 2 = Nadel,
254 = unklassifizierbar, 255 = außerhalb.

Nutzung:
  python3 tool/forest_grid.py --self-test
  python3 tool/forest_grid.py build --source dlt.tif --year 2024 --out build/forest
  python3 tool/forest_grid.py fetch --out build/forest          # Direktweg (S3-Env)
  python3 tool/forest_grid.py fetch-order --key service_key.json --out build/forest
  python3 tool/forest_grid.py verify --source dlt.tif --out build/forest
"""

from __future__ import annotations

import argparse
import calendar
import csv
import datetime
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


def granule_csv_text(full_path, fetch_fn=None):
    """Die Granulat-Liste hinter der CSV-Verzeichnisseite von full_path.

    full_path zeigt auf eine HTML-Seite des CDSE-CSV-Katalogs mit genau
    einem Link auf das CSV; beides ist anonym abrufbar.
    """
    fetch_fn = fetch_fn or _http_text
    page = fetch_fn(full_path)
    match = re.search(r'href="([^"]+\.csv)"', page)
    if not match:
        raise SystemExit("fetch: keine Granulat-Liste unter " + full_path)
    return fetch_fn(match.group(1))


def newest_reference_year(full_path, fetch_fn=None):
    """Neuestes WIRKLICH vorhandenes Jahr der offenen Reihe.

    Der Katalogeintrag nennt als Abdeckung auch geplante Jahre (Stand
    2026-08 listet er bis „2026", Granulate liegen bis 2024). Was es
    gibt, steht in der Granulat-Liste — ein geratenes Jahr kostet beim
    Bestell-Weg einen ganzen Queue-Umlauf, deshalb nachsehen.
    """
    return newest_year_in_csv(granule_csv_text(full_path, fetch_fn))


def select_tiles(csv_text, year, bounds):
    """Kacheln des Jahres, deren Bounding Box das Zielgebiet schneidet.

    Die bbox-Spalte ist ein POLYGON in Länge/Breite; der grobe
    Rechteck-Schnitt reicht, weil gdalwarp auf BOUNDS zuschneidet und
    Fehlendes als NO_DATA endet. MD5 kommt mit — damit wird jeder
    Download verifiziert statt nur über die Größe geraten.
    """
    west, south, east, north = bounds
    tiles = []
    for row in csv.DictReader(io.StringIO(csv_text), delimiter=";"):
        if (row.get("content_date_start") or "")[:4] != str(year):
            continue
        s3_path = row.get("s3_path") or ""
        numbers = [float(x) for x in
                   re.findall(r"-?\d+\.?\d*", row.get("bbox") or "")]
        if len(numbers) < 8 or not s3_path:
            raise SystemExit("fetch: Granulat-Zeile ohne bbox/s3_path "
                             f"({row.get('name')}) — CSV-Format geändert?")
        lons, lats = numbers[0::2], numbers[1::2]
        if (min(lons) > east or max(lons) < west or
                min(lats) > north or max(lats) < south):
            continue
        is_md5 = (row.get("checksum_algorithm") or "").upper() == "MD5"
        tiles.append({
            "name": row.get("name") or os.path.basename(s3_path),
            "s3_path": s3_path,
            "bytes": int(row.get("content_length") or 0),
            "md5": (row.get("checksum_value") or "").lower()
                   if is_md5 else "",
        })
    if not tiles:
        raise SystemExit(f"fetch: keine Kacheln für {year} im Zielgebiet "
                         "— CSV-Format geändert?")
    return sorted(tiles, key=lambda tile: tile["name"])


def _http_text(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode("utf-8", errors="replace")


def search_dataset(token=None):
    """Datensatz und Download-Item aus der Katalog-Suche.

    Die Suche ist anonym abrufbar — der Direktweg braucht deshalb gar
    kein CLMS-Token mehr, nur der Bestell-Weg reicht seines durch.
    """
    result = clms_json(
        "/api/@search?portal_type=DataSet"
        "&SearchableText=dominant+leaf+type"
        "&metadata_fields=UID&metadata_fields=dataset_download_information"
        "&b_size=50",
        token=token)
    best = pick_dataset(result.get("items", []))
    if best is None:
        raise SystemExit("fetch: kein DLT-Datensatz gefunden — "
                         "hat sich die Katalogstruktur geändert?")
    open_ended, year, uid, download = best
    if download is None:
        raise SystemExit("fetch: Datensatz ohne Download-Information — "
                         "Suchantwort prüfen")
    return open_ended, year, uid, download


def find_dataset(session):
    """Bestell-Weg: Datensatz, Download-Id und echtes Bezugsjahr."""
    open_ended, year, uid, download = search_dataset(session.fresh())
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


def filter_year(value):
    """Jahr aus einem TemporalFilter-Datum der API.

    Bestellt wird in Epoch-Millisekunden, aber @datarequest_search gibt
    Strings wie „2019-01-01 10:00:00" zurück — genau daran scheiterte
    Lauf 5: int() warf, der laufende Auftrag galt als fremd, die
    Neubestellung wurde von CLMS als Duplikat abgewiesen.
    """
    if value is None:
        return None
    if isinstance(value, (int, float)):
        try:
            return time.gmtime(value / 1000).tm_year
        except (ValueError, OverflowError, OSError):
            return None
    text = str(value).strip()
    match = re.match(r"(\d{4})-", text)
    if match:
        return int(match.group(1))
    if text.isdigit():
        try:
            return time.gmtime(int(text) / 1000).tm_year
        except (ValueError, OverflowError, OSError):
            return None
    return None


def task_matches(task, uid, year_filter):
    """Ist dieser Auftrag unsere Bestellung (Datensatz + Jahrgang)?

    Der Service-Key wird ausschließlich von diesem Workflow benutzt,
    eine andere Bounding Box kann es unter ihm also nicht geben —
    geprüft wird, was die Bestellung eindeutig macht: Datensatz-UID
    und, bei der Jahres-Reihe, das Jahr des Zeitfensters. Ein Auftrag
    der Reihe OHNE erkennbares Jahr wird nicht angefasst.
    """
    datasets = task.get("Datasets") or []
    if not any(d.get("DatasetID") == uid for d in datasets):
        return False
    if year_filter is None:
        return True
    for d in datasets:
        window = d.get("TemporalFilter") or {}
        year = filter_year(window.get("StartDate"))
        if year is None:
            # Falls eine Zeitzonen-Verschiebung den Jahresanfang
            # verrückt hätte: das Ende desselben Fensters liegt bei
            # Ganzjahres-Bestellungen sicher im richtigen Jahr.
            year = filter_year(window.get("EndDate"))
        if year is None:
            continue
        return year == year_filter
    return False


def pick_existing_task(finished, in_progress, uid, year_filter,
                       now_s, max_age_hours=66):
    """Wiederverwendbaren Auftrag wählen: fertig vor laufend, neu vor alt.

    Lauf 4 bestellte korrekt, lief nach 120 Minuten in sein
    Poll-Timeout — und der Auftrag kochte serverseitig weiter. Neu
    bestellen hieße, die CLMS-Queue mit Duplikaten zu füllen (CLMS
    weist das ohnehin als Duplikat ab, siehe Lauf 5) und jedes Mal bei
    null zu warten. Fertige Aufträge nur, solange ihr Ergebnis-Zip
    noch liegt: laut Doku 72 Stunden ab Fertigstellung, hier mit
    Sicherheitsabstand ab FinalizationDateTime gerechnet (Zeitstempel
    kommen ohne Zeitzone und gelten als UTC).
    """
    def _fresh(task):
        stamp = (task.get("FinalizationDateTime") or
                 task.get("RegistrationDateTime"))
        if not stamp:
            return False
        try:
            finished_at = datetime.datetime.fromisoformat(stamp).replace(
                tzinfo=datetime.timezone.utc)
        except ValueError:
            return False
        age = now_s - finished_at.timestamp()
        return 0 <= age <= max_age_hours * 3600

    candidates = [
        (task.get("RegistrationDateTime") or "", task_id, task)
        for task_id, task in (finished or {}).items()
        if task_matches(task, uid, year_filter) and _fresh(task)
        and task.get("DownloadURL")]
    if candidates:
        _, task_id, task = max(candidates)
        return "finished", str(task_id), task["DownloadURL"]
    running = [
        (task.get("RegistrationDateTime") or "", task_id)
        for task_id, task in (in_progress or {}).items()
        if task_matches(task, uid, year_filter)]
    if running:
        return "in_progress", str(max(running)[1]), None
    return None


def find_existing_task(session, uid, year_filter):
    finished = clms_json("/api/@datarequest_search?status=Finished_ok",
                         token=session.fresh())
    in_progress = clms_json("/api/@datarequest_search?status=In_progress",
                            token=session.fresh())
    return pick_existing_task(finished, in_progress, uid, year_filter,
                              now_s=time.time())


def poll_download(session, task_id, timeout_minutes=240):
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


def download_tiles(tiles, tiles_dir, copy_fn=None):
    """Jede Kachel einzeln per AWS CLI, MD5 gegen die Granulat-Liste.

    Ein Granulat ist genau EIN Objekt — das GeoTIFF ohne Endung, laut
    OData-Katalog ContentType application/tiff —, deshalb schlichtes
    cp je Kachel statt --recursive. Die CLI ist auf den GitHub-Runnern
    vorinstalliert; Zugang über das CDSE-Schlüsselpaar in
    AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY. Eine Wiederholung je
    Kachel; unvollständig nach zwei Versuchen bricht ab.
    """
    copy_fn = copy_fn or _aws_copy
    os.makedirs(tiles_dir, exist_ok=True)
    paths = []
    for index, tile in enumerate(tiles, 1):
        target = os.path.join(tiles_dir, tile["name"] + ".tif")
        for attempt in (1, 2):
            try:
                copy_fn(tile["s3_path"], target)
            except subprocess.CalledProcessError:
                pass  # zählt wie eine unvollständige Datei: neuer Versuch
            if tile_checksum_ok(target, tile):
                break
            print(f"  {tile['name']}: unvollständig (Versuch {attempt})",
                  file=sys.stderr)
        else:
            raise SystemExit(f"fetch: Kachel {tile['name']} nach zwei "
                             "Versuchen unvollständig")
        paths.append(target)
        print(f"  {index}/{len(tiles)} {tile['name']}", file=sys.stderr)
    return paths


def tile_checksum_ok(path, tile):
    if not os.path.exists(path) or os.path.getsize(path) != tile["bytes"]:
        return False
    if not tile["md5"]:
        return True
    digest = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest() == tile["md5"]


def _aws_copy(s3_path, target):
    subprocess.run(
        ["aws", "s3", "cp", "--only-show-errors",
         "--endpoint-url", "https://eodata.dataspace.copernicus.eu",
         s3_path, target],
        check=True)


# Zielraster der Reprojektion: ~10 m am mittleren Breitengrad, beide
# Achsen Vielfache von CELL_FACTOR (81600/25 = 3264, 104000/25 = 4160
# Zellen). Die Zellweite in Metern variiert mit der Breite — echte
# 250 m nur in der Mitte; das Manifest trägt die Geometrie, die App
# rechnet linear in Grad, dieselbe bewusste Gröbe wie beim Regen.
WARP_WIDTH = 81600
WARP_HEIGHT = 104000


def warp_mosaic(tile_paths, out_dir):
    """Mosaik der LAEA-Kacheln (EPSG:3035), einmal nach EPSG:4326.

    -r near, weil die Werte Klassen sind (0/1/2/254/255) — jede andere
    Interpolation erfände Werte. GDAL ist hier Reprojektor, nicht
    Rechner: Aggregation und Kodierung bleiben handgeschrieben und
    selbstgetestet, und --verify rechnet gegen das GEWARPTE Raster
    nach, sieht also alles ab diesem Punkt.
    """
    west, south, east, north = BOUNDS
    vrt = os.path.join(out_dir, "dlt_tiles.vrt")
    subprocess.run(["gdalbuildvrt", "-q", vrt] + sorted(tile_paths),
                   check=True)
    warped = os.path.join(out_dir, "dlt_4326.tif")
    subprocess.run([
        "gdalwarp", "-q", "-overwrite",
        "-t_srs", "EPSG:4326",
        "-te", str(west), str(south), str(east), str(north),
        "-ts", str(WARP_WIDTH), str(WARP_HEIGHT),
        "-r", "near", "-ot", "Byte", "-dstnodata", "255",
        "-multi", "-wo", "NUM_THREADS=ALL_CPUS", "-wm", "1024",
        "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES",
        "-co", "BIGTIFF=YES", "-co", "NUM_THREADS=ALL_CPUS",
        vrt, warped], check=True)
    return warped


def fetch_direct(out_dir):
    """Direktweg (Standard): COG-Kacheln aus dem CDSE-Objektspeicher.

    Kein Bestellen, keine Queue: Die anonyme Granulat-Liste nennt die
    Kacheln samt Größe, MD5 und Bounding Box; geladen wird direkt aus
    s3://eodata. Der Bestell-Weg (fetch-order) bleibt übergangsweise
    erreichbar — warum er verlassen wurde, steht in der Git-Historie
    der sechs Echtläufe: eine FME-Queue mit Stunden-Latenz und ohne
    Zusage, bei jedem Quartalslauf aufs Neue.
    """
    for var in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
        if not os.environ.get(var):
            raise SystemExit(
                f"fetch: {var} fehlt — CDSE-Konto anlegen "
                "(dataspace.copernicus.eu), dort S3-Schlüssel erzeugen "
                "(eodata-s3keysmanager.dataspace.copernicus.eu) und als "
                "Repo-Secrets CDSE_S3_ACCESS_KEY/CDSE_S3_SECRET_KEY "
                "hinterlegen.")
    open_ended, _title_year, _uid, download = search_dataset()
    if not open_ended:
        raise SystemExit("fetch: Katalog nennt keine offene Reihe mehr — "
                         "Datensatz-Wahl prüfen")
    full_path = download.get("full_path")
    if not full_path:
        raise SystemExit("fetch: offene Reihe ohne full_path — "
                         "Suchantwort prüfen")
    csv_text = granule_csv_text(full_path)
    year = newest_year_in_csv(csv_text)
    tiles = select_tiles(csv_text, year, BOUNDS)
    total = sum(tile["bytes"] for tile in tiles)
    print(f"fetch: DLT {year}, {len(tiles)} Kacheln, {total / 1e6:.0f} MB",
          file=sys.stderr)
    os.makedirs(out_dir, exist_ok=True)
    tile_paths = download_tiles(tiles, os.path.join(out_dir, "tiles"))
    source = warp_mosaic(tile_paths, out_dir)
    print(f"fetch: Quelle {source}", file=sys.stderr)
    return source, year


def fetch_order(key_path, out_dir):
    """Übergangsweise erhaltener Bestell-Weg über die CLMS-Download-API.

    Fliegt raus, sobald der Direktweg einmal verifiziert geliefert hat
    — zusammen mit ClmsSession, dem JWT-Tausch und dem Secret
    CLMS_SERVICE_KEY.
    """
    session = ClmsSession(key_path)
    open_ended, year, uid, download_id = find_dataset(session)
    print(f"fetch: DLT {year} (UID {uid}, Download {download_id}, "
          f"{'offene Reihe' if open_ended else 'fester Jahrgang'})",
          file=sys.stderr)
    if not download_id:
        raise SystemExit("fetch: Datensatz ohne Download-Information — "
                         "Suchantwort prüfen")
    year_filter = year if open_ended else None
    url = None
    existing = find_existing_task(session, uid, year_filter)
    if existing is not None:
        kind, task, url = existing
        print(f"fetch: übernehme Auftrag {task} ({kind})", file=sys.stderr)
    else:
        task = request_download(session, uid, download_id,
                                year_filter=year_filter)
        print(f"fetch: neuer Auftrag {task}", file=sys.stderr)
    if url is None:
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

    # Direktweg: Zielraster muss in CELL_FACTOR-Blöcke teilbar sein,
    # sonst verwirft die Aggregation stillschweigend den Rand.
    assert WARP_WIDTH % CELL_FACTOR == 0
    assert WARP_HEIGHT % CELL_FACTOR == 0

    # Kachel-Auswahl: Jahr-Filter und bbox-Schnitt gegen BOUNDS-artige
    # Grenzen; teilweise Überlappung bleibt, ganz außerhalb fliegt.
    kachel_csv = (
        "id;name;content_length;content_date_start;checksum_algorithm;"
        "checksum_value;s3_path;bbox\n"
        "a;DRIN;100;2024-01-01T00:00:00.000;MD5;ABCD12;s3://e/drin;"
        "POLYGON((9.7 41.1,9.7 40.1,10.9 40.1,10.9 41.1,9.7 41.1))\n"
        "b;RAND;200;2024-01-01T00:00:00.000;MD5;ffee99;s3://e/rand;"
        "POLYGON((11.5 39.9,11.5 40.2,12.5 40.2,12.5 39.9,11.5 39.9))\n"
        "c;WEIT_WEG;300;2024-01-01T00:00:00.000;MD5;aa;s3://e/weit;"
        "POLYGON((32.5 34.7,32.5 33.5,33.8 33.5,33.8 34.7,32.5 34.7))\n"
        "d;ALTES_JAHR;400;2018-01-01T00:00:00.000;MD5;bb;s3://e/alt;"
        "POLYGON((9.7 41.1,9.7 40.1,10.9 40.1,10.9 41.1,9.7 41.1))\n"
        "e;OHNE_MD5;500;2024-01-01T00:00:00.000;SHA1;cc;s3://e/ohne;"
        "POLYGON((9.0 40.5,9.0 40.6,9.1 40.6,9.1 40.5,9.0 40.5))\n")
    testgebiet = (8.9, 40.0, 12.0, 41.0)
    tiles = select_tiles(kachel_csv, 2024, testgebiet)
    assert [t["name"] for t in tiles] == ["DRIN", "OHNE_MD5", "RAND"], tiles
    assert tiles[0]["md5"] == "abcd12", "MD5 muss kleingeschrieben sein"
    assert tiles[1]["md5"] == "", "fremder Algorithmus ist kein MD5"
    assert tiles[0]["bytes"] == 100
    try:
        select_tiles(kachel_csv, 2030, testgebiet)
        raise AssertionError("leere Kachelliste nicht erkannt")
    except SystemExit:
        pass

    # Download: MD5 aus der Liste entscheidet, ein Retry, dann Abbruch.
    with tempfile.TemporaryDirectory() as tiles_tmp:
        inhalt = b"kacheldaten"
        richtig = {"name": "K1", "s3_path": "s3://e/k1",
                   "bytes": len(inhalt),
                   "md5": hashlib.md5(inhalt).hexdigest()}
        versuche = []

        def _copy_kaputt_dann_gut(_s3, target):
            versuche.append(target)
            data = b"kaputt" if len(versuche) < 2 else inhalt
            with open(target, "wb") as f:
                f.write(data)

        paths = download_tiles([richtig], tiles_tmp,
                               copy_fn=_copy_kaputt_dann_gut)
        assert len(versuche) == 2 and paths[0].endswith("K1.tif")
        with open(paths[0], "rb") as f:
            assert f.read() == inhalt

        falsch = dict(richtig, md5="0" * 32)
        try:
            download_tiles([falsch], tiles_tmp,
                           copy_fn=lambda _s3, t: open(t, "wb").write(inhalt))
            raise AssertionError("falsche Prüfsumme nicht erkannt")
        except SystemExit:
            pass

    # Wiederaufnahme: Lauf 4 lief ins Poll-Timeout, der Auftrag kochte
    # serverseitig weiter — der nächste Lauf muss ihn übernehmen statt
    # die Queue mit einem Duplikat zu füllen.
    jan_2024_ms = year_window_ms(2024)[0]
    passend = {"Datasets": [{"DatasetID": "uid1",
                             "TemporalFilter": {"StartDate": jan_2024_ms}}],
               "RegistrationDateTime": "2026-08-08T00:36:00"}
    anderes_jahr = {"Datasets": [{
        "DatasetID": "uid1",
        "TemporalFilter": {"StartDate": year_window_ms(2023)[0]}}],
        "RegistrationDateTime": "2026-08-08T00:36:00"}
    ohne_jahr = {"Datasets": [{"DatasetID": "uid1"}],
                 "RegistrationDateTime": "2026-08-08T00:36:00"}
    assert task_matches(passend, "uid1", 2024)
    assert not task_matches(passend, "anderes-uid", 2024)
    assert not task_matches(anderes_jahr, "uid1", 2024)
    assert not task_matches(ohne_jahr, "uid1", 2024), \
        "Reihe ohne erkennbares Jahr darf nicht übernommen werden"
    assert task_matches(ohne_jahr, "uid1", None)
    # Die Live-Gestalt: @datarequest_search liefert Datums-STRINGS
    # („2019-01-01 10:00:00"), bestellt wird in Epoch-Millisekunden —
    # Lauf 5 scheiterte, weil nur Letzteres verstanden wurde.
    live = {"Datasets": [{"DatasetID": "uid1",
                          "TemporalFilter": {
                              "StartDate": "2024-01-01 01:00:00",
                              "EndDate": "2024-12-31 01:00:00"}}],
            "RegistrationDateTime": "2026-08-08T00:36:00"}
    assert task_matches(live, "uid1", 2024)
    assert not task_matches(live, "uid1", 2023)
    assert filter_year("2019-01-01 10:00:00") == 2019
    assert filter_year(1704067200000) == 2024
    assert filter_year("1704067200000") == 2024
    assert filter_year("gestern") is None and filter_year(None) is None

    now_s = datetime.datetime(2026, 8, 8, 3, 0,
                              tzinfo=datetime.timezone.utc).timestamp()
    fertig = dict(passend, DownloadURL="https://ergebnis/1.zip")
    # Fertig schlägt laufend; unter mehreren fertigen gewinnt der neueste.
    aelter = dict(fertig, RegistrationDateTime="2026-08-07T00:00:00",
                  DownloadURL="https://ergebnis/alt.zip")
    picked = pick_existing_task({"7": aelter, "9": fertig}, {"5": passend},
                                "uid1", 2024, now_s)
    assert picked == ("finished", "9", "https://ergebnis/1.zip"), picked
    # Laufender Auftrag, wenn nichts Fertiges passt.
    picked = pick_existing_task({}, {"5": passend}, "uid1", 2024, now_s)
    assert picked == ("in_progress", "5", None), picked
    # Zu alt (Ergebnis-Zip liegt nicht mehr) → nicht übernehmen.
    veraltet = dict(fertig, RegistrationDateTime="2026-07-20T00:00:00")
    assert pick_existing_task({"7": veraltet}, {}, "uid1", 2024,
                              now_s) is None
    # Die 72-h-Frist zählt ab FERTIGSTELLUNG, nicht ab Bestellung: ein
    # vor fünf Tagen bestellter, vor einer Stunde fertig gewordener
    # Auftrag ist frisch — andersherum nicht.
    frisch_fertig = dict(passend, DownloadURL="https://ergebnis/2.zip",
                         RegistrationDateTime="2026-08-03T00:00:00",
                         FinalizationDateTime="2026-08-08T02:00:00")
    picked = pick_existing_task({"11": frisch_fertig}, {}, "uid1", 2024,
                                now_s)
    assert picked == ("finished", "11", "https://ergebnis/2.zip"), picked
    lang_fertig = dict(frisch_fertig,
                       FinalizationDateTime="2026-08-04T00:00:00")
    assert pick_existing_task({"11": lang_fertig}, {}, "uid1", 2024,
                              now_s) is None
    # Fertig ohne DownloadURL ist nichts wert.
    kaputt = dict(passend)
    assert pick_existing_task({"7": kaputt}, {}, "uid1", 2024, now_s) is None
    # Nichts vorhanden → None (dann wird bestellt).
    assert pick_existing_task({}, {}, "uid1", 2024, now_s) is None

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
                        choices=["", "build", "fetch", "fetch-order",
                                 "verify"])
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
        source, year = fetch_direct(args.out)
        manifest = build(source, year, args.out)
        print(json.dumps(manifest, indent=2))
        verify(source, args.out, samples=args.samples)
    elif args.command == "fetch-order":
        if not args.key:
            raise SystemExit("fetch-order braucht --key (Service-Key-JSON)")
        source, year = fetch_order(args.key, args.out)
        manifest = build(source, year, args.out)
        print(json.dumps(manifest, indent=2))
        verify(source, args.out, samples=args.samples)
    elif args.command == "verify":
        verify(args.source, args.out, samples=args.samples)
    else:
        parser.error("Kommando oder --self-test angeben")


if __name__ == "__main__":
    main()
