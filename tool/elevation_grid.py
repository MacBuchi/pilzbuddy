#!/usr/bin/env python3
"""Baut das Höhengitter fürs Spot-Blatt und die Pilzampel (#279-Rest).

Die nächste Wetterstation kann Hunderte Höhenmeter neben dem Spot
liegen — die Zugspitze (2956 m) war zeitweise Referenz für die Täler um
sie herum. Ohne Höhenmodell auf dem Gerät ließ sich das bisher nur
DANEBENSCHREIBEN statt herausrechnen. Dieses Werkzeug liefert das
Höhenmodell: die mittlere Geländehöhe je Wabe, EIN Byte je Zelle in
20-m-Stufen, auf EXAKT demselben Hex-Gitter wie Wald- und
Baumartengitter (odd-r, 3038 × 4470). Die App schlägt alle drei mit
demselben `hexNearestCell` nach; eine zweite Geometrie wäre die Falle,
vor der schon `forest_species.py` warnt.

Warum die Korrektur zum validierten Modell HINführt statt von ihm weg:
`ampel_validate.py` holt seine Temperaturen von Open-Meteo an der
Fundkoordinate, und dessen Archiv rechnet sie über ein 90-m-Höhenmodell
auf die Zielhöhe herunter. Validiert wurde also immer schon die
Temperatur AUF SPOTHÖHE — die unkorrigierte Stationstemperatur der App
ist die Abweichung.

Quelle: Copernicus DEM GLO-90 (© DLR 2010–2014, © Airbus Defence and
Space 2014–2018, bereitgestellt unter COPERNICUS durch EU und ESA),
90 m, als offene COG-Kacheln ohne Konto vom AWS-Open-Data-Bucket. Für
eine 250-m-Wabe ist 90 m Auflösung reichlich; GLO-30 wäre nur ein
zehnfacher Download für dieselben Wabenmittel.

Kodierung: Zeilen-Delta + gzip wie beim Regengitter — Höhen sind ein
glattes Feld, das Delta macht aus Hängen kleine Zahlen. Anders als bei
den KLASSEN der Baumarten (dort verschlechtert das Delta, gemessen in
#227) lohnt es hier; `build` misst beide Wege und schreibt den
gewählten ins Manifest, statt ihn im Code zu verstecken.

Meer und Senken unter Null zählen als 0 m: Der tiefste Landpunkt
Deutschlands liegt bei −3,5 m, das sind 0,02 K Korrekturfehler — eine
eigene Nodata-Buchführung wäre mehr Code für weniger Ehrlichkeit.
0xFF bleibt als „keine Aussage" reserviert und entsteht nur in
Randzellen ohne ein einziges Quellpixel: Die letzte Spalte ragt in den
ungeraden (versetzten) Hexzeilen über den Ostrand des Rasters hinaus.
Die App behandelt 0xFF als „keine Höhe bekannt" — dort liegt ohnehin
kein deutscher, österreichischer oder Schweizer Wald.

Nutzung:
  python3 tool/elevation_grid.py --self-test          # netzfrei, läuft in CI
  python3 tool/elevation_grid.py fetch --out build/elevation
  python3 tool/elevation_grid.py build --source warped.tif --out ...
  python3 tool/elevation_grid.py verify --source warped.tif --out ...
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from array import array
from itertools import accumulate

from forest_grid import (
    BOUNDS,
    CELL_FACTOR,
    WARP_HEIGHT,
    WARP_WIDTH,
    gdal_band,
    gdal_info,
    hex_at,
    hex_center,
    hex_metrics,
    hex_runs,
    read_geotiff,
)

BUCKET = "https://copernicus-dem-90m.s3.amazonaws.com/"
USER_AGENT = "pilzbuddy-elevation (github.com/MacBuchi/pilzbuddy)"

# 20-m-Stufen: 0…254 deckt 0…5080 m — über dem höchsten Punkt des
# Kastens (Finsteraarhorn, 4274 m). Für die Temperaturkorrektur sind
# 20 m gleich 0,13 K, weit unter jeder Stationsunsicherheit.
QUANT_M = 20
MAX_BYTE = 254
ELEVATION_NO_DATA = 0xFF

# Bekannte Punkte als Richtungs- und Vorzeichenprobe des GANZEN Wegs
# (Download → Warp → Aggregation → Kodierung → Nachschlag). Ein
# vertauschtes Vorzeichen im Geotransform bestünde jede
# Zufallszellen-Probe — die rechnet ja mit demselben Fehler nach.
LANDMARKS = (
    ("Zugspitze", 47.4212, 10.9853, 2500, 3100),
    ("Feldberg", 47.8737, 8.0043, 1150, 1550),
    ("Hamburg", 53.5510, 9.9940, 0, 80),
)


# ---------------------------------------------------------------------------
# Kodierung
# ---------------------------------------------------------------------------

def quantize(mean_m):
    """Meter → Byte: 20-m-Stufen, unter Null wird 0, oben gedeckelt."""
    if mean_m <= 0:
        return 0
    return min(MAX_BYTE, int(round(mean_m / QUANT_M)))


def encode_delta(rows):
    """Zeilen-Delta + gzip, mtime=0 (Determinismus wie beim Waldgitter)."""
    delta = bytearray()
    for row in rows:
        previous = 0
        for byte in row:
            delta.append((byte - previous) & 0xFF)
            previous = byte
    return gzip.compress(bytes(delta), 9, mtime=0)


def encode_plain(rows):
    return gzip.compress(b"".join(rows), 9, mtime=0)


def decode(payload, width, height, encoding):
    """Referenz-Umkehrung für Tests und verify — beide Kodierungen."""
    flat = gzip.decompress(payload)
    if len(flat) != width * height:
        raise ValueError(f"{len(flat)} Bytes, erwartet {width * height}")
    rows = [bytearray(flat[y * width:(y + 1) * width]) for y in range(height)]
    if encoding == "gzip+row-delta":
        for row in rows:
            previous = 0
            for x, byte in enumerate(row):
                previous = (previous + byte) & 0xFF
                row[x] = previous
    elif encoding != "gzip":
        raise ValueError(f"unbekannte Kodierung: {encoding}")
    return [bytes(row) for row in rows]


# ---------------------------------------------------------------------------
# Zeilen lesen und summieren
# ---------------------------------------------------------------------------

def row_values(row_bytes, little):
    """Eine Rasterzeile als signierte 16-Bit-Werte."""
    values = array("h")
    values.frombytes(row_bytes)
    if little != (sys.byteorder == "little"):
        values.byteswap()
    return values


def row_prefix(values):
    """Präfixsummen — macht jede Lauf-Summe zu EINER Subtraktion.

    Eine Python-Schleife über die Läufe selbst (25 Pixel × 316 Mio.
    Läufe) wäre Stunden; accumulate läuft in C.
    """
    return [0, *accumulate(values)]


# ---------------------------------------------------------------------------
# build: gewarptes Int16-Raster → Gitter + Manifest
# ---------------------------------------------------------------------------

def build(source, out_dir, band_rows=2048, info_fn=None, band_fn=None,
          progress=True):
    """Mittlere Höhe je Wabe, Aufbau wie `forest_species.build`."""
    os.makedirs(out_dir, exist_ok=True)
    info_fn = info_fn or gdal_info
    band_fn = band_fn or gdal_band

    src_w, src_h, gt = info_fn(source)
    w, r = hex_metrics()
    rows = max(1, int((src_h - r) / (1.5 * r)) + 1)
    cols = int(src_w / w) + 1

    acc = {}  # hy -> (sums[], counts[])
    grid_rows = [None] * rows

    def flush(hy):
        sums, counts = acc.pop(hy)
        out = bytearray(cols)
        for hx in range(cols):
            out[hx] = (quantize(sums[hx] / counts[hx]) if counts[hx]
                       else ELEVATION_NO_DATA)
        grid_rows[hy] = bytes(out)

    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        y0 = 0
        while y0 < src_h:
            h = min(band_rows, src_h - y0)
            band_fn(source, 0, y0, src_w, h, strip)
            with open(strip, "rb") as f:
                raw = f.read()
            little = raw[:2] == b"II"
            pixel_rows, _meta, _bits = read_geotiff(raw, allowed_bits=(16,))
            for j, row in enumerate(pixel_rows):
                prefix = row_prefix(row_values(row, little))
                y = y0 + j + 0.5
                for hx, hy, x0, x1 in hex_runs(y, src_w, w, r, rows, cols):
                    if hy not in acc:
                        acc[hy] = ([0] * cols, [0] * cols)
                    sums, counts = acc[hy]
                    sums[hx] += prefix[x1] - prefix[x0]
                    counts[hx] += x1 - x0
            done_before = int(((y0 + h) - 2 * r) / (1.5 * r))
            for hy in [k for k in acc if k < done_before]:
                flush(hy)
            y0 += h
            if progress:
                print(f"  {y0}/{src_h} Zeilen", file=sys.stderr)
    for hy in list(acc):
        flush(hy)
    empty = sum(1 for row in grid_rows if row is None)
    blank = bytes([ELEVATION_NO_DATA]) * cols
    grid_rows = [blank if row is None else row for row in grid_rows]

    # Beide Kodierungen messen; die kleinere wird ausgeliefert und im
    # Manifest benannt — der Dart-Leser richtet sich nach dem Manifest.
    delta_payload = encode_delta(grid_rows)
    plain_payload = encode_plain(grid_rows)
    if len(delta_payload) <= len(plain_payload):
        payload, encoding = delta_payload, "gzip+row-delta"
    else:
        payload, encoding = plain_payload, "gzip"
    if progress:
        print(f"  Delta {len(delta_payload) / 1e6:.2f} MB, "
              f"plain {len(plain_payload) / 1e6:.2f} MB → {encoding}",
              file=sys.stderr)
    with open(os.path.join(out_dir, "elevation.bin.gz"), "wb") as f:
        f.write(payload)

    origin_x, origin_y, px_w, px_h = gt[0], gt[3], gt[1], gt[5]
    filled = [b for row in grid_rows for b in row if b != ELEVATION_NO_DATA]
    manifest = {
        "source": "Copernicus DEM GLO-90",
        "license": ("© DLR e.V. 2010–2014 und © Airbus Defence and Space "
                    "GmbH 2014–2018, bereitgestellt unter COPERNICUS durch "
                    "die Europäische Union und die ESA"),
        "lattice": "hex-odd-r",
        "encoding": encoding,
        "quant_m": QUANT_M,
        "width": cols,
        "height": rows,
        "west": round(origin_x, 6),
        "east": round(origin_x + src_w * px_w, 6),
        "north": round(origin_y, 6),
        "south": round(origin_y + src_h * px_h, 6),
        "hex_lon_step": round(w * px_w, 9),
        "hex_lat_step": round(1.5 * r * abs(px_h), 9),
        "cell_factor": CELL_FACTOR,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "no_data_cells": cols * rows - len(filled),
        "empty_rows": empty,
        "min_m": min(filled) * QUANT_M,
        "max_m": max(filled) * QUANT_M,
        "mean_m": round(sum(filled) * QUANT_M / len(filled), 1),
    }
    with open(os.path.join(out_dir, "elevation_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def assert_matches_forest_grid(manifest):
    """Dasselbe Raster wie Wald- und Baumartengitter — die Zusicherung,
    die den Entwurf trägt (Muster `forest_species`)."""
    w, r = hex_metrics()
    cols = int(WARP_WIDTH / w) + 1
    rows = max(1, int((WARP_HEIGHT - r) / (1.5 * r)) + 1)
    if (manifest["width"], manifest["height"]) != (cols, rows):
        raise SystemExit(
            f"Gitter passt nicht zum Waldgitter: "
            f"{manifest['width']}x{manifest['height']} statt {cols}x{rows}")


# ---------------------------------------------------------------------------
# verify: Zufallszellen nachrechnen + Landmarken
# ---------------------------------------------------------------------------

def _load(out_dir):
    with open(os.path.join(out_dir, "elevation_manifest.json")) as f:
        manifest = json.load(f)
    with open(os.path.join(out_dir, "elevation.bin.gz"), "rb") as f:
        rows = decode(f.read(), manifest["width"], manifest["height"],
                      manifest["encoding"])
    return manifest, rows


def verify(source, out_dir, samples=24, band_fn=None):
    band_fn = band_fn or gdal_band
    manifest, rows = _load(out_dir)
    src_w, src_h, _ = gdal_info(source)
    w, r = hex_metrics()
    hrows, hcols = manifest["height"], manifest["width"]

    rng = random.Random(20260817)
    checked = bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        while checked < samples:
            hx = rng.randrange(hcols)
            hy = rng.randrange(hrows)
            stored = rows[hy][hx]
            _, cy = hex_center(hx, hy, w, r)
            y0 = max(0, int(cy - r))
            y1 = min(src_h, int(math.ceil(cy + r)) + 1)
            band_fn(source, 0, y0, src_w, y1 - y0, strip)
            with open(strip, "rb") as f:
                raw = f.read()
            little = raw[:2] == b"II"
            pixel_rows, _meta, _bits = read_geotiff(raw, allowed_bits=(16,))
            total = count = 0
            for j, row in enumerate(pixel_rows):
                prefix = row_prefix(row_values(row, little))
                y = y0 + j + 0.5
                for rhx, rhy, x0, x1 in hex_runs(y, src_w, w, r,
                                                 hrows, hcols):
                    if (rhx, rhy) != (hx, hy):
                        continue
                    total += prefix[x1] - prefix[x0]
                    count += x1 - x0
            expect = (quantize(total / count) if count
                      else ELEVATION_NO_DATA)
            if expect != stored:
                bad += 1
                print(f"  Hex ({hx},{hy}): gespeichert {stored}, "
                      f"nachgerechnet {expect}", file=sys.stderr)
            checked += 1

    landmark_lines, landmark_bad = check_landmarks(manifest, rows)
    report = [
        f"verify: {checked} Hexe, {bad} Abweichungen",
        *landmark_lines,
        f"Gitter: {manifest['width']}x{manifest['height']}, "
        f"{manifest['bytes'] / 1e6:.2f} MB gepackt ({manifest['encoding']}), "
        f"{manifest['min_m']}–{manifest['max_m']} m, "
        f"Mittel {manifest['mean_m']} m",
    ]
    print("\n".join(report))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("\n".join(report) + "\n")
    if bad or landmark_bad:
        raise SystemExit(f"verify: {bad} Abweichungen, "
                         f"{landmark_bad} Landmarken daneben")
    return manifest


def cell_at(manifest, lat, lon):
    """Geo → Wabe, über die Pixelkoordinaten und `hex_at` — exakt der
    Weg, den auch die App nimmt, keine zweite Geometrie.

    Die Pixelgröße kommt aus dem Manifest selbst (`hex_lon_step` ist
    Wabenbreite × Pixelbreite), nicht aus den WARP-Konstanten — so
    stimmt die Rechnung auch für das kleine Selbsttest-Raster.
    """
    w, r = hex_metrics()
    px_w = manifest["hex_lon_step"] / w
    px_h = manifest["hex_lat_step"] / (1.5 * r)
    x = (lon - manifest["west"]) / px_w
    y = (manifest["north"] - lat) / px_h
    return hex_at(x, y, w, r, manifest["height"], manifest["width"])


def check_landmarks(manifest, rows):
    lines, bad = [], 0
    for name, lat, lon, low, high in LANDMARKS:
        hx, hy = cell_at(manifest, lat, lon)
        metres = rows[hy][hx] * QUANT_M
        ok = low <= metres <= high
        bad += 0 if ok else 1
        lines.append(f"  {name}: {metres} m "
                     f"({'ok' if ok else f'erwartet {low}–{high}'})")
    return lines, bad


# ---------------------------------------------------------------------------
# fetch: Kacheln holen, warpen
# ---------------------------------------------------------------------------

def tile_names(bounds=BOUNDS):
    west, south, east, north = bounds
    for lat in range(int(math.floor(south)), int(math.ceil(north))):
        for lon in range(int(math.floor(west)), int(math.ceil(east))):
            yield (f"Copernicus_DSM_COG_30_N{lat:02d}_00_"
                   f"E{lon:03d}_00_DEM")


def download_tiles(out_dir, fetch_fn=None):
    """Alle Kacheln des Kastens; fehlende sind Meer und werden gezählt.

    Ein Fehlschlag, der KEIN 404 ist, bricht ab — sonst würde ein
    Netzproblem still zu einer flachen Nordsee aus Löchern.
    """
    tiles_dir = os.path.join(out_dir, "tiles")
    os.makedirs(tiles_dir, exist_ok=True)
    got, missing = [], 0
    for name in tile_names():
        target = os.path.join(tiles_dir, f"{name}.tif")
        url = f"{BUCKET}{name}/{name}.tif"
        if fetch_fn is not None:
            ok = fetch_fn(url, target)
        else:
            request = urllib.request.Request(
                url, headers={"User-Agent": USER_AGENT})
            try:
                with urllib.request.urlopen(request, timeout=300) as resp, \
                        open(target, "wb") as f:
                    while chunk := resp.read(1 << 20):
                        f.write(chunk)
                ok = True
            except urllib.error.HTTPError as err:
                if err.code != 404:
                    raise
                ok = False
        if ok:
            got.append(target)
        else:
            missing += 1
    print(f"fetch: {len(got)} Kacheln, {missing} fehlen (Meer)",
          file=sys.stderr)
    # Der DACH-Kasten ist überwiegend Land: Deutlich weniger Kacheln
    # hießen falsche Namen oder ein halber Bucket — nicht bauen.
    if len(got) < 90:
        raise SystemExit(f"fetch: nur {len(got)} Kacheln — Namensschema "
                         f"oder Bucket prüfen ({BUCKET})")
    return tiles_dir, got


def warp(tiles_dir, out_dir):
    """Auf das Raster des Waldgitters: gleiche Box, gleiche Größe.

    `-r bilinear`, weil Höhen stetig sind (near ergäbe Treppen an den
    Kachelkanten); `-ot Int16` reicht bis 32 km. `-dstnodata 0` füllt
    Meer (fehlende Kacheln) mit 0 m — siehe Modul-Docstring.
    """
    west, south, east, north = BOUNDS
    vrt = os.path.join(out_dir, "dem.vrt")
    subprocess.run(["gdalbuildvrt", "-q", vrt,
                    *sorted(os.path.join(tiles_dir, f)
                            for f in os.listdir(tiles_dir)
                            if f.endswith(".tif"))], check=True)
    warped = os.path.join(out_dir, "elevation_4326.tif")
    subprocess.run([
        "gdalwarp", "-q", "-overwrite",
        "-t_srs", "EPSG:4326",
        "-te", str(west), str(south), str(east), str(north),
        "-ts", str(WARP_WIDTH), str(WARP_HEIGHT),
        "-r", "bilinear", "-ot", "Int16", "-dstnodata", "0",
        "-multi", "-wo", "NUM_THREADS=ALL_CPUS", "-wm", "1024",
        "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES",
        "-co", "BIGTIFF=YES", "-co", "NUM_THREADS=ALL_CPUS",
        vrt, warped], check=True)
    return warped


def fetch(out_dir):
    tiles_dir, tiles = download_tiles(out_dir)
    warped = warp(tiles_dir, out_dir)
    # Platte ist auf dem Runner das knappe Gut (Muster forest_species).
    for tile in tiles:
        os.remove(tile)
    return warped


# ---------------------------------------------------------------------------
# Selbsttest
# ---------------------------------------------------------------------------

def _fake_tiff_i16(rows_values, little=True):
    """Signierte Werte über den u16-Bauer aus forest_species."""
    from forest_species import _fake_tiff_u16
    return _fake_tiff_u16([[v & 0xFFFF for v in row] for row in rows_values],
                          little=little)


def self_test():
    # Quantisierung: Stufen, Deckel, Senken.
    assert quantize(-3.5) == 0
    assert quantize(0) == 0
    assert quantize(9.9) == 0
    assert quantize(10.1) == 1
    assert quantize(2962) == 148          # Zugspitze
    assert quantize(99999) == MAX_BYTE
    assert MAX_BYTE * QUANT_M >= 4274, "Deckel unter dem Finsteraarhorn"

    # Beide Kodierungen: Roundtrip, Determinismus, falsche Größe.
    rows = [bytes([0, 3, 3, 250]), bytes([1, 1, 254, 0])]
    for enc, name in ((encode_delta, "gzip+row-delta"),
                      (encode_plain, "gzip")):
        payload = enc(rows)
        assert decode(payload, 4, 2, name) == rows
        assert payload[4:8] == b"\x00\x00\x00\x00", \
            "gzip-Header trägt eine Bauzeit"
        try:
            decode(payload, 3, 2, name)
            raise AssertionError("falsche Größe nicht erkannt")
        except ValueError:
            pass
    try:
        decode(encode_plain(rows), 4, 2, "brotli")
        raise AssertionError("unbekannte Kodierung nicht erkannt")
    except ValueError:
        pass

    # Zeilen lesen: signiert, beide Bytereihenfolgen, Präfixsummen.
    for little in (True, False):
        tiff = _fake_tiff_i16([[-5, 0, 100, 2962]], little=little)
        pixel_rows, (w_, h_, _t), bits = read_geotiff(tiff,
                                                      allowed_bits=(16,))
        assert (w_, h_, bits) == (4, 1, 16)
        values = row_values(pixel_rows[0], little)
        assert list(values) == [-5, 0, 100, 2962], list(values)
        prefix = row_prefix(values)
        assert prefix[4] - prefix[0] == 3057
        assert prefix[2] - prefix[1] == 0

    # Dasselbe Raster wie das Waldgitter — die Zahlen des
    # ausgelieferten Assets, wie in forest_species.
    w, r = hex_metrics()
    cols = int(WARP_WIDTH / w) + 1
    rows_n = max(1, int((WARP_HEIGHT - r) / (1.5 * r)) + 1)
    assert (cols, rows_n) == (3038, 4470), \
        f"Raster verschoben: {cols}x{rows_n}"
    assert_matches_forest_grid({"width": cols, "height": rows_n})
    try:
        assert_matches_forest_grid({"width": cols, "height": rows_n + 1})
        raise AssertionError("falsche Maße nicht erkannt")
    except SystemExit:
        pass

    # Kachelnamen: Ecken des Kastens, Format mit führenden Nullen.
    names = list(tile_names())
    assert "Copernicus_DSM_COG_30_N45_00_E005_00_DEM" in names
    assert "Copernicus_DSM_COG_30_N55_00_E017_00_DEM" in names
    assert len(names) == 11 * 13, len(names)

    _self_test_build()
    print("self-test: ok")


def _self_test_build():
    # Ein Testraster mit Gefälle über die GANZE Höhe: links Tal (0 m),
    # rechts Berg (2000 m). Bei einer lückenlosen Quelle hat jede
    # Hexzeile Pixel; 0xFF entsteht trotzdem — in der letzten SPALTE
    # der ungeraden (versetzten) Hexzeilen, die ganz über den Ostrand
    # hinausragt. Genau diese Verteilung wird geprüft: 0xFF am Rand ja,
    # im Inneren nie.
    grid = [[0] * 30 + [2000] * 30 for _ in range(120)]

    def info_fn(_path):
        return 60, 120, (10.0, 0.0001, 0, 55.0, 0, -0.0001)

    def band_fn(_src, x, y, w_, h, out_path):
        with open(out_path, "wb") as f:
            f.write(_fake_tiff_i16([row[x:x + w_]
                                    for row in grid[y:y + h]]))

    with tempfile.TemporaryDirectory() as tmp:
        manifest = build("egal", tmp, band_rows=16,
                         info_fn=info_fn, band_fn=band_fn, progress=False)
        _, rows = _load(tmp)
    assert manifest["encoding"] in ("gzip", "gzip+row-delta")
    assert len(rows) == manifest["height"]
    for row in rows:
        assert ELEVATION_NO_DATA not in row[:-1], \
            "0xFF im Inneren — eine Wabe mit Pixeln blieb leer"
    assert any(row[-1] == ELEVATION_NO_DATA for row in rows), \
        "kein 0xFF am Ostrand — der Verteidigungszweig wäre ungeprüft"
    assert manifest["empty_rows"] == 0
    assert manifest["max_m"] == 2000
    assert manifest["min_m"] == 0
    # Reines Tal links, reiner Berg in der reinen Bergspalte (Byte 100 =
    # 2000 m); die Mischzelle dazwischen wird bewusst nicht festgelegt.
    middle = rows[2 * (len(rows) // 4)]  # eine gerade, unversetzte Zeile
    assert middle[0] == 0, middle[0]
    assert middle[2] == 100, middle[2]
    # Die Landmarken-Rechnung selbst: Geo → Wabe trifft die Bergkante.
    fake_manifest = dict(manifest, west=10.0, north=55.0,
                         east=10.0 + 60 * 0.0001,
                         south=55.0 - 120 * 0.0001)
    hx, hy = cell_at(fake_manifest, 54.9940, 10.0055)
    assert rows[hy][hx] == 100, "Geo → Wabe trifft nicht die Bergseite"
    hx, hy = cell_at(fake_manifest, 54.9940, 10.0005)
    assert rows[hy][hx] == 0, "Geo → Wabe trifft nicht die Talseite"


# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")

    p_fetch = sub.add_parser("fetch", help="holen, warpen, bauen, prüfen")
    p_fetch.add_argument("--out", default="build/elevation")

    p_build = sub.add_parser("build", help="aus gewarptem Raster bauen")
    p_build.add_argument("--source", required=True)
    p_build.add_argument("--out", default="build/elevation")

    p_verify = sub.add_parser("verify", help="Zufallszellen + Landmarken")
    p_verify.add_argument("--source", required=True)
    p_verify.add_argument("--out", default="build/elevation")
    p_verify.add_argument("--samples", type=int, default=24)

    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.command == "fetch":
        source = fetch(args.out)
        manifest = build(source, args.out)
        assert_matches_forest_grid(manifest)
        verify(source, args.out)
    elif args.command == "build":
        manifest = build(args.source, args.out)
        assert_matches_forest_grid(manifest)
    elif args.command == "verify":
        verify(args.source, args.out, samples=args.samples)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
