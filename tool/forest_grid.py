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
Der frühere Bestell-Weg über die CLMS-Download-API (JWT-Service-Key,
@datarequest_post, stundenlanges Queue-Polling) wurde nach dem ersten
erfolgreichen Direktweg-Lauf entfernt; die Git-Historie der sechs
Echtläufe dokumentiert ihn samt aller Fallen.

Erklärte Abweichung von der Stdlib-Regel des Regen-Werkzeugs
(`rain_grid.py`), nur im Quartals-Workflow und nie in der App:
GDAL als Mosaik- und Reprojektionswerkzeug. Die Kacheln sind EPSG:3035
(LAEA) und die App rechnet linear in Grad — `gdalwarp -r near` macht
daraus einmal ein EPSG:4326-Raster (nearest, weil die Werte Klassen
sind). Danach bandweise `gdal_translate -srcwin`, der eigene strenge
Reader, Aggregation von Hand — GDAL ist nie der Rechner, und --verify
rechnet gegen das gewarpte Raster nach. Der Download läuft über die
AWS-CLI (auf den Runnern vorinstalliert), verifiziert gegen HeadObject
des TIFF-Objekts (Größe, plus MD5 übers ETag bei Nicht-Multipart).

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
  python3 tool/forest_grid.py fetch --out build/forest   # braucht S3-Env
  python3 tool/forest_grid.py verify --source dlt.tif --out build/forest
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import math
import os
import random
import re
import struct
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

CLMS_BASE = "https://land.copernicus.eu"

# Ehrlicher Absender für die Downloads — urllib meldet sich sonst als
# „Python-urllib", und genau solche Standard-UAs filtern CDNs gern weg.
USER_AGENT = "pilzbuddy-forest-grid (github.com/MacBuchi/pilzbuddy)"

# DACH — weiter als die Regen-Box: ganz Österreich (bis 17,2° O), die
# Schweiz (ab 45,8° N). west, south, east, north.
BOUNDS = (5.8, 45.7, 17.3, 55.1)

# Aggregation: 25 × 25 Quellpixel (10 m) je Zelle ≈ 250 m.
#
# Über `--cell-factor` umstellbar, weil die Quelle 10 m liefert und die
# Frage „wie fein geht es, und was kostet das?" nur eine Messung
# beantwortet (Feldbericht 2026-08-09: 250-m-Zellen sind auf der Karte
# grob, und der Laubfaktor-Umkreis muss deshalb groß sein). Beide
# Warp-Achsen müssen durch den Faktor teilbar bleiben — sonst fielen am
# Rand Pixel unter den Tisch, ohne dass es jemand merkt; `set_cell_factor`
# prüft das.
CELL_FACTOR = 25


def set_cell_factor(factor):
    """Stellt die Aggregation um und prüft, ob das Zielraster aufgeht."""
    global CELL_FACTOR
    if factor < 1:
        raise ValueError("cell-factor muss mindestens 1 sein")
    if WARP_WIDTH % factor or WARP_HEIGHT % factor:
        raise ValueError(
            f"cell-factor {factor} teilt das Zielraster nicht glatt "
            f"({WARP_WIDTH}×{WARP_HEIGHT}) — am Rand fielen Pixel weg")
    CELL_FACTOR = factor

# Ab diesem Baumanteil (unter den gültigen Pixeln der Zelle) gilt sie als
# Wald. 20 %: Ein lichter Bestand zählt noch, eine Baumreihe am Feldrand
# nicht mehr. Steht im Manifest, damit die Zahl nie geraten werden muss.
TREE_THRESHOLD = 0.20


# ---------------------------------------------------------------------------
# Hex-Gitter (#251): Sechsecke MIT SPITZE OBEN, versetzte Zeilen (odd-r),
# regelmäßig im PIXELRAUM des gewarpten Rasters — dieselbe bewusste
# Gröbe wie beim Quadrat (Meter je Grad variieren mit der Breite).
#
# Ehrlich heißt: Jedes 10-m-Quellpixel fällt über seinen MITTELPUNKT in
# genau ein Sechseck; die Sechsecke SIND dann die Daten, keine Umdeutung
# quadratischer Zellen (Entscheid des Betreibers 2026-08-09; das
# Performance-Tor des Zeichners ist gemessen und bestanden).
#
# Die Fläche eines Hexes entspricht der Fläche der Quadratzelle
# (CELL_FACTOR² Pixel), damit das Asset gleich groß bleibt:
#   Breite w = CELL_FACTOR·√(2/√3) ≈ 1,0746·CELL_FACTOR
#   Umkreisradius R = w/√3, Zeilenschritt 1,5·R, ungerade Zeilen +w/2.
#
# Warum die Zuordnung über LÄUFE statt je Pixel: 81600 × 104000 Pixel je
# Pixel in Python zuzuordnen wäre der Tod des Quartalsjobs. Eine
# Pixelzeile zerfällt aber in zusammenhängende Läufe je Hex — im
# Mittelband einer Hexzeile gehört jeweils eine ganze Hexbreite einem
# Hex, im Übergangsband wechseln Ober- und Unterzeile in Segmenten,
# deren Grenzen linear mit y wandern (die Schrägkanten). Gezählt wird je
# Lauf mit bytes.count — C-Geschwindigkeit.

def hex_metrics(cell_factor=None):
    """(w, r) in Quellpixeln: Hexbreite und Umkreisradius."""
    f = CELL_FACTOR if cell_factor is None else cell_factor
    w = f * math.sqrt(2 / math.sqrt(3))
    return w, w / math.sqrt(3)


def hex_center(hx, hy, w, r):
    """Mittelpunkt des Hexes (Spalte hx, Zeile hy) in Quellpixeln."""
    return w * (hx + 0.5 + 0.5 * (hy & 1)), r + hy * 1.5 * r


def hex_at(x, y, w, r, rows, cols):
    """Hexindex (hx, hy) unter dem Punkt — Referenz über den nächsten
    Mittelpunkt, für Tests und kleine Mengen (--verify). Prüft die drei
    Kandidatzeilen um die grobe Schätzung."""
    best = None
    best_d = None
    hy0 = int((y - r) / (1.5 * r) + 0.5)
    for hy in range(max(0, hy0 - 1), min(rows, hy0 + 2)):
        odd = 0.5 * (hy & 1)
        hx0 = int(x / w - 0.5 - odd + 0.5)
        for hx in range(max(0, hx0 - 1), min(cols, hx0 + 2)):
            cx, cy = hex_center(hx, hy, w, r)
            d = (x - cx) ** 2 + (y - cy) ** 2
            if best_d is None or d < best_d:
                best_d = d
                best = (hx, hy)
    return best


def hex_runs(y, src_w, w, r, rows, cols):
    """Zerlegt die Pixelzeile mit Mittelpunkt-y in Läufe [(hx, hy, x0, x1)],
    x1 exklusiv. Jeder Pixel (über seinen Mittelpunkt x+0,5) gehört zu
    genau einem Lauf.

    Mittelband einer Hexzeile (|dy| ≤ r/2): alles gehört dieser Zeile,
    Grenzen bei den Hexkanten. Übergangsband: Ober- und Unterzeile
    wechseln sich ab; die Oberzeile reicht bis Halbbreite
    (w/2)·(1 − t/(r/2)) um ihre Mittelpunkte, t = Abstand unter ihrem
    Mittelband."""
    runs = []
    band = 1.5 * r
    hy_upper = int((y - r) / band + 0.5)  # Zeile, deren Mitte am nächsten
    cy_upper = r + hy_upper * band
    dy = y - cy_upper
    if abs(dy) <= r / 2 or (dy < 0 and hy_upper == 0) or (
            dy > 0 and hy_upper >= rows - 1):
        # Mittelband (oder Randzeile: nichts darüber/darunter).
        hy = max(0, min(rows - 1, hy_upper))
        shift = w * (0.5 * (hy & 1))
        x = 0.0
        if shift > 0:
            # Links vor dem ersten Hex dieser (ungeraden) Zeile liegt
            # ein Keil, der zu einer NACHBARZEILE gehört. Er ist eine
            # halbe Hexbreite schmal — pixelweise über die Referenz
            # zuordnen ist billiger als jede Sonderfall-Geometrie.
            while x + 0.5 < shift and x < src_w:
                target = hex_at(x + 0.5, y, w, r, rows, cols)
                runs.append((target[0], target[1], int(x), int(x) + 1))
                x += 1
        while x < src_w:
            hx = int((x + 0.5 - shift) // w) if x + 0.5 >= shift else 0
            hx = max(0, min(cols - 1, hx))
            edge = min(src_w, shift + (hx + 1) * w)
            x1 = int(math.ceil(edge - 0.5)) if edge < src_w else src_w
            x0 = int(x)
            if x1 > x0:
                runs.append((hx, hy, x0, x1))
            if x1 <= x0:
                x1 = x0 + 1
            x = x1
        return runs

    # Übergangsband zwischen hy_upper und der Nachbarzeile.
    if dy > 0:
        hy_a, cy_a = hy_upper, cy_upper
    else:
        hy_a = hy_upper - 1
        cy_a = r + hy_a * band
    hy_b = hy_a + 1
    t = y - (cy_a + r / 2)  # 0..r/2 unterhalb des Mittelbands von a
    half = (w / 2) * (1 - t / (r / 2))
    shift_a = w * (0.5 * (hy_a & 1))
    x = 0
    while x < src_w:
        px = x + 0.5
        # Nächster a-Mittelpunkt und seine Spanne auf dieser Höhe.
        hx_a = int(round((px - shift_a) / w - 0.5))
        hx_a = max(0, min(cols - 1, hx_a))
        cx_a = shift_a + (hx_a + 0.5) * w
        left_a, right_a = cx_a - half, cx_a + half
        if left_a <= px <= right_a:
            # Im a-Hex bis zu dessen rechter Schräge.
            x1 = int(math.floor(right_a - 0.5)) + 1
            hx, hy = hx_a, hy_a
        else:
            # Dazwischen: das b-Hex (versetzt um w/2) bis zur linken
            # Schräge des NÄCHSTEN a-Hexes.
            shift_b = w * (0.5 * (hy_b & 1))
            hx_b = int(round((px - shift_b) / w - 0.5))
            if px < left_a:
                x1 = int(math.ceil(left_a - 0.5))
            else:
                x1 = int(math.ceil(left_a + w - 0.5))
            if 0 <= hx_b < cols and 0 <= hy_b < rows:
                hx, hy = hx_b, hy_b
            else:
                # Rand: Das versetzte Nachbar-Hex existiert nicht (erste/
                # letzte Bandzeile, linker/rechter Rand). Der Lauf kann
                # dann ZWEI a-Hexen gehören (Teilung am Mittelpunkt) —
                # pixelweise über die Referenz zuordnen; es betrifft nur
                # wenige Randzeilen und ist damit billig und exakt.
                x1 = max(x + 1, min(src_w, x1))
                for i in range(x, x1):
                    t_hx, t_hy = hex_at(i + 0.5, y, w, r, rows, cols)
                    runs.append((t_hx, t_hy, i, i + 1))
                x = x1
                continue
        x1 = max(x + 1, min(src_w, x1))
        runs.append((hx, hy, x, x1))
        x = x1
    return runs

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
    # mtime=0: Ohne das stempelt gzip die Bauzeit in den Header und
    # identische Nutzdaten bekommen je Lauf eine neue Prüfsumme — der
    # Quartals-Review soll aber an der SHA ablesen können, ob sich
    # überhaupt etwas geändert hat (Lauf 9 und 10 lieferten identische
    # Nutzdaten mit verschiedenen Hashes, nur wegen dieses Felds).
    return gzip.compress(bytes(delta), 9, mtime=0)


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

def build_hex(source, year, out_dir, band_rows=2048,
              info_fn=None, band_fn=None):
    """Aggregiert das Quell-GeoTIFF in das Hex-Gitter (#251).

    Bandweise wie [build]; weil Hexzeilen Pixelzeilen ÜBERLAPPEN, laufen
    Akkumulatoren je Hexzeile mit (valid/broadleaf/conifer je Hex) und
    werden erst ausgegeben, wenn kein Pixel mehr hineinfallen kann.
    """
    os.makedirs(out_dir, exist_ok=True)
    info_fn = info_fn or gdal_info
    band_fn = band_fn or gdal_band

    src_w, src_h, gt = info_fn(source)
    w, r = hex_metrics()
    rows = max(1, int((src_h - r) / (1.5 * r)) + 1)
    cols = int(src_w / w) + 1

    acc = {}  # hy -> (valid[], broadleaf[], conifer[])
    grid_rows = [None] * rows

    def flush(hy):
        valid, broad, conif = acc.pop(hy)
        out = bytearray(cols)
        for hx in range(cols):
            v = valid[hx]
            if v == 0:
                out[hx] = NO_DATA
                continue
            trees = broad[hx] + conif[hx]
            if trees / v < TREE_THRESHOLD:
                out[hx] = NO_FOREST
            else:
                out[hx] = 1 + round(100 * conif[hx] / trees)
        grid_rows[hy] = bytes(out)

    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        y0 = 0
        while y0 < src_h:
            h = min(band_rows, src_h - y0)
            band_fn(source, 0, y0, src_w, h, strip)
            with open(strip, "rb") as f:
                pixel_rows, _ = read_geotiff_u8(f.read())
            for j, row_bytes in enumerate(pixel_rows):
                y = y0 + j + 0.5
                for hx, hy, x0, x1 in hex_runs(y, src_w, w, r, rows, cols):
                    if hy not in acc:
                        acc[hy] = ([0] * cols, [0] * cols, [0] * cols)
                    valid, broad, conif = acc[hy]
                    seg = row_bytes[x0:x1]
                    b = seg.count(DLT_BROADLEAF)
                    c = seg.count(DLT_CONIFER)
                    valid[hx] += seg.count(DLT_NO_TREE) + b + c
                    broad[hx] += b
                    conif[hx] += c
            # Hexzeile hy endet bei r + hy*1,5r + r — alles darüber
            # hinaus bekommt keine Pixel mehr.
            done_before = int(((y0 + h) - 2 * r) / (1.5 * r))
            for hy in [k for k in acc if k < done_before]:
                flush(hy)
            y0 += h
            print(f"  {y0}/{src_h} Zeilen (hex)", file=sys.stderr)
    for hy in list(acc):
        flush(hy)
    if any(row is None for row in grid_rows):
        raise RuntimeError("Hexzeile ohne Pixel — Geometriefehler")

    payload = encode(grid_rows)
    with open(os.path.join(out_dir, "forest_grid.bin.gz"), "wb") as f:
        f.write(payload)

    origin_x, origin_y, px_w, px_h = gt[0], gt[3], gt[1], gt[5]
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
        "lattice": "hex-odd-r",
        "width": cols,
        "height": rows,
        "west": round(origin_x, 6),
        "east": round(origin_x + src_w * px_w, 6),
        "north": round(origin_y, 6),
        "south": round(origin_y + src_h * px_h, 6),
        # Hexbreite (Länge) und Zeilenschritt (Breite) in Grad — daraus
        # rekonstruiert die App jeden Mittelpunkt:
        #   lon = west + lon_step*(hx + 0,5 + 0,5*(hy&1))
        #   lat = north − lat_step/1,5 − hy*lat_step   (R = lat_step/1,5)
        "hex_lon_step": round(w * px_w, 9),
        "hex_lat_step": round(1.5 * r * abs(px_h), 9),
        "cell_factor": CELL_FACTOR,
        "tree_threshold": TREE_THRESHOLD,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "forest_percent": round(100 * counts["forest"] / known, 1)
        if known else None,
        "median_conifer_percent":
            conifer_values[len(conifer_values) // 2]
            if conifer_values else None,
    }
    with open(os.path.join(out_dir, "forest_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def cut_blocks(out_dir, block_deg=2.0):
    """Schneidet das gebaute HEX-Gitter in nachladbare Blöcke (#253).

    Für die 100-m-Stufe: 27+ MB am Stück lädt niemand für einen
    Waldspaziergang — Blöcke von ~2° Kantenlänge schon. Geschnitten wird
    an GERADEN Hexzeilen (odd-r-Parität!) und ganzen Spalten, damit
    jeder Block für sich ein gültiges Hex-Gitter mit denselben
    Mittelpunkten ist: Sein Anker ist der globale Anker plus
    Indexversatz, die Formel der App ändert sich nicht.

    Ergebnis: forest_block_x<i>_y<j>.bin.gz je Block plus der Katalog
    forest_blocks.json (Bbox, Maße, Prüfsumme je Block) — das Pendant
    zur Release-Asset-Liste des Regens.
    """
    with open(os.path.join(out_dir, "forest_manifest.json")) as f:
        manifest = json.load(f)
    if manifest.get("lattice") != "hex-odd-r":
        raise SystemExit("cut_blocks: nur für Hex-Gitter gedacht")
    with open(os.path.join(out_dir, "forest_grid.bin.gz"), "rb") as f:
        rows = decode(f.read(), manifest["width"], manifest["height"])
    lon_step = manifest["hex_lon_step"]
    lat_step = manifest["hex_lat_step"]
    width, height = manifest["width"], manifest["height"]
    west, north = manifest["west"], manifest["north"]

    step_x = max(2, int(round(block_deg / lon_step)))
    step_y = max(2, int(round(block_deg / lat_step)) // 2 * 2)  # gerade!

    catalog = []
    for by, hy0 in enumerate(range(0, height, step_y)):
        h = min(step_y, height - hy0)
        for bx, hx0 in enumerate(range(0, width, step_x)):
            w = min(step_x, width - hx0)
            block_rows = [rows[hy0 + j][hx0:hx0 + w] for j in range(h)]
            payload = encode(block_rows)
            name = f"forest_block_x{bx}_y{by}.bin.gz"
            with open(os.path.join(out_dir, name), "wb") as f:
                f.write(payload)
            catalog.append({
                "file": name,
                "width": w,
                "height": h,
                "west": round(west + hx0 * lon_step, 9),
                "north": round(north - hy0 * lat_step, 9),
                "east": round(west + (hx0 + w + 0.5) * lon_step, 9),
                "south": round(north - (hy0 + h + 1) * lat_step, 9),
                "bytes": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            })
    index = {
        "source": manifest["source"],
        "reference_year": manifest["reference_year"],
        "lattice": manifest["lattice"],
        "hex_lon_step": lon_step,
        "hex_lat_step": lat_step,
        "cell_factor": manifest["cell_factor"],
        "tree_threshold": manifest["tree_threshold"],
        "blocks": catalog,
    }
    with open(os.path.join(out_dir, "forest_blocks.json"), "w") as f:
        json.dump(index, f, indent=2)
    total = sum(b["bytes"] for b in catalog)
    print(f"blocks: {len(catalog)} Stück, gesamt {total/1e6:.1f} MB, "
          f"größter {max(b['bytes'] for b in catalog)/1e6:.1f} MB")
    return index


def build(source, year, out_dir, band_rows=None,
          info_fn=None, band_fn=None):
    """Aggregiert das (komprimierte) Quell-GeoTIFF bandweise.

    `band_rows` ist ein Vielfaches von CELL_FACTOR (geprüft), damit keine
    Zelle über eine Bandgrenze läuft. Ohne Angabe rund 2000 Zeilen, auf
    das nächste Vielfache abgerundet — sonst müsste jeder neue
    `--cell-factor` auch noch diese Zahl mitbringen.
    """
    if band_rows is None:
        band_rows = max(CELL_FACTOR, 2000 // CELL_FACTOR * CELL_FACTOR)
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

def verify_hex(source, out_dir, samples=24, band_fn=None):
    """Wie [verify], aber für das Hex-Gitter (#251): Zufalls-Hexe werden
    über die Lauf-Zerlegung ihrer Pixelzeilen direkt aus der Quelle
    nachgerechnet — dieselbe Zerlegung wie im Bau, aber je Hex isoliert
    und gegen den gespeicherten Byte verglichen."""
    band_fn = band_fn or gdal_band
    with open(os.path.join(out_dir, "forest_manifest.json")) as f:
        manifest = json.load(f)
    assert manifest.get("lattice") == "hex-odd-r", "kein Hex-Manifest"
    with open(os.path.join(out_dir, "forest_grid.bin.gz"), "rb") as f:
        rows = decode(f.read(), manifest["width"], manifest["height"])
    src_w, src_h, _ = gdal_info(source)
    w, r = hex_metrics()
    hrows, hcols = manifest["height"], manifest["width"]

    rng = random.Random(20260809)
    checked = 0
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        while checked < samples:
            hx = rng.randrange(hcols)
            hy = rng.randrange(hrows)
            stored = rows[hy][hx]
            if stored in (NO_DATA,):
                continue
            _, cy = hex_center(hx, hy, w, r)
            y0 = max(0, int(cy - r))
            y1 = min(src_h, int(math.ceil(cy + r)) + 1)
            band_fn(source, 0, y0, src_w, y1 - y0, strip)
            with open(strip, "rb") as f:
                pixel_rows, _ = read_geotiff_u8(f.read())
            valid = broad = conif = 0
            for j, row_bytes in enumerate(pixel_rows):
                y = y0 + j + 0.5
                for rhx, rhy, x0, x1 in hex_runs(
                        y, src_w, w, r, hrows, hcols):
                    if (rhx, rhy) != (hx, hy):
                        continue
                    seg = row_bytes[x0:x1]
                    b = seg.count(DLT_BROADLEAF)
                    c = seg.count(DLT_CONIFER)
                    valid += seg.count(DLT_NO_TREE) + b + c
                    broad += b
                    conif += c
            if valid == 0:
                expect = NO_DATA
            else:
                trees = broad + conif
                if trees / valid < TREE_THRESHOLD:
                    expect = NO_FOREST
                else:
                    expect = 1 + round(100 * conif / trees)
            if expect != stored:
                bad += 1
                print(f"  Hex ({hx},{hy}): gespeichert {stored}, "
                      f"nachgerechnet {expect}", file=sys.stderr)
            checked += 1
    forest_percent = manifest.get("forest_percent")
    report = [
        f"verify (hex): {checked} Hexe, {bad} Abweichungen",
        f"Waldanteil: {forest_percent} % "
        f"(plausibel: 25–50), Median Nadel: "
        f"{manifest.get('median_conifer_percent')} %",
    ]
    print("\n".join(report))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("\n".join(report) + "\n")
    if bad:
        raise SystemExit("verify (hex): Gitter weicht von der Quelle ab")
    if forest_percent is not None and not 25 <= forest_percent <= 50:
        raise SystemExit(
            f"verify (hex): Waldanteil {forest_percent} % außerhalb "
            "25–50 — Klassenzuordnung oder Schwelle prüfen")


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
# fetch: Direktweg über den CDSE-Objektspeicher (nur im Workflow)
# ---------------------------------------------------------------------------
# Der frühere Bestell-Weg über die CLMS-Download-API (JWT-Token,
# @datarequest_post, Polling, Auftrags-Übernahme) wurde nach dem ersten
# erfolgreichen Direktweg-Lauf entfernt — die FME-Queue brauchte für den
# 10-m-Jahrgang über sechs Stunden ohne Zusage. Die Git-Historie der
# sechs Echtläufe dokumentiert ihn samt seiner Fallen.

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


def select_tiles(csv_text, year, bounds):
    """Kacheln des Jahres, deren Bounding Box das Zielgebiet schneidet.

    Die bbox-Spalte ist ein POLYGON in Länge/Breite; der grobe
    Rechteck-Schnitt reicht, weil gdalwarp auf BOUNDS zuschneidet und
    Fehlendes als NO_DATA endet. content_length/checksum der CSV
    beziffern das GANZE Granulat-Bündel (tif + XML + Legende) und
    taugen deshalb nur für die Info-Zeile — verifiziert wird der
    Download in download_tiles gegen HeadObject des TIFF-Objekts.
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
        tiles.append({
            "name": row.get("name") or os.path.basename(s3_path),
            "s3_path": s3_path,
            "bytes": int(row.get("content_length") or 0),
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


CDSE_S3_ENDPOINT = "https://eodata.dataspace.copernicus.eu"


def tile_object_key(tile):
    """S3-Schlüssel des TIFF-Objekts einer Kachel.

    Der s3_path der Granulat-Liste ist ein ORDNER (tif + Metadaten +
    Legende) — der erste Direktweg-Lauf scheiterte mit HeadObject-404,
    weil er den Ordnerpfad als Objekt ansprach. Das Datenobjekt darin
    heißt <name>.tif (per OData-Nodes nachgesehen).
    """
    prefix = tile["s3_path"].split("s3://eodata/", 1)[-1].rstrip("/")
    return f"{prefix}/{tile['name']}.tif"


def download_tiles(tiles, tiles_dir, copy_fn=None, head_fn=None):
    """Jede Kachel einzeln per AWS CLI, verifiziert gegen HeadObject.

    Größe muss immer stimmen; das ETag ist bei Nicht-Multipart-Uploads
    das MD5 des Inhalts und wird dann mitgeprüft (ein „…-N"-ETag ist
    Multipart, da bleibt die Größe). Eine Wiederholung je Kachel;
    unvollständig nach zwei Versuchen bricht ab. Die CLI ist auf den
    GitHub-Runnern vorinstalliert; Zugang über das CDSE-Schlüsselpaar
    in AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY.
    """
    copy_fn = copy_fn or _aws_copy
    head_fn = head_fn or _aws_head
    os.makedirs(tiles_dir, exist_ok=True)
    paths = []
    for index, tile in enumerate(tiles, 1):
        key = tile_object_key(tile)
        expected_size, etag = head_fn(key)
        target = os.path.join(tiles_dir, tile["name"] + ".tif")
        for attempt in (1, 2):
            try:
                copy_fn("s3://eodata/" + key, target)
            except subprocess.CalledProcessError:
                pass  # zählt wie eine unvollständige Datei: neuer Versuch
            if tile_ok(target, expected_size, etag):
                break
            print(f"  {tile['name']}: unvollständig (Versuch {attempt})",
                  file=sys.stderr)
        else:
            raise SystemExit(f"fetch: Kachel {tile['name']} nach zwei "
                             "Versuchen unvollständig")
        paths.append(target)
        print(f"  {index}/{len(tiles)} {tile['name']}", file=sys.stderr)
    return paths


def tile_ok(path, expected_size, etag):
    if not os.path.exists(path) or os.path.getsize(path) != expected_size:
        return False
    if not etag or "-" in etag:
        return True
    digest = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest() == etag


def _aws_copy(s3_path, target):
    subprocess.run(
        ["aws", "s3", "cp", "--only-show-errors",
         "--endpoint-url", CDSE_S3_ENDPOINT, s3_path, target],
        check=True)


def _aws_head(key):
    result = subprocess.run(
        ["aws", "s3api", "head-object", "--bucket", "eodata",
         "--key", key, "--endpoint-url", CDSE_S3_ENDPOINT],
        check=True, capture_output=True, text=True)
    info = json.loads(result.stdout)
    return int(info["ContentLength"]), info.get("ETag", "").strip('"').lower()


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
    Kacheln samt Bounding Box; geladen wird direkt aus s3://eodata,
    verifiziert gegen HeadObject.
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


# ---------------------------------------------------------------------------
# Selbsttest — netzfrei, ohne GDAL.
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
    # Die Selbsttests rechnen gegen den STANDARD-Faktor, auch wenn der
    # Aufruf einen anderen mitbringt: Ihre erwarteten Zahlen (Zellgrößen,
    # Blockmuster) gehören zu 25 — mit einem umgestellten Faktor prüften
    # sie nichts mehr, sondern scheiterten nur anders.
    previous = CELL_FACTOR
    set_cell_factor(25)
    try:
        _self_test()
    finally:
        set_cell_factor(previous)


def _self_test():
    # Kodierung: Roundtrip mit Zeilen, die verschieden anfangen.
    rows = [bytes([0, 50, 101]), bytes([101, 1, 0]), bytes([255, 255, 80])]
    assert decode(encode(rows), 3, 3) == rows
    # Deterministisch: Bytes 4–7 des gzip-Headers sind das mtime-Feld —
    # genullt, damit identische Nutzdaten identische Dateien ergeben
    # (der Quartals-Review vergleicht Prüfsummen).
    assert encode(rows)[4:8] == b"\x00\x00\x00\x00", \
        "gzip-Header trägt eine Bauzeit"
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
    assert newest_year_in_csv(
        granule_csv_text("seite", fetch_fn=pages.__getitem__)) == 2024

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
    assert tiles[0]["bytes"] == 100
    try:
        select_tiles(kachel_csv, 2030, testgebiet)
        raise AssertionError("leere Kachelliste nicht erkannt")
    except SystemExit:
        pass

    # Objektschlüssel: der s3_path ist ein ORDNER, das Datenobjekt
    # heißt <name>.tif darin — Lauf 7 scheiterte am Ordnerpfad (404).
    assert tile_object_key({"name": "K1",
                            "s3_path": "s3://eodata/pfad/K1"}) == \
        "pfad/K1/K1.tif"

    # Download: HeadObject liefert Größe + ETag, danach wird geprüft —
    # ein Retry, dann Abbruch.
    with tempfile.TemporaryDirectory() as tiles_tmp:
        inhalt = b"kacheldaten"
        etag = hashlib.md5(inhalt).hexdigest()
        kachel = {"name": "K1", "s3_path": "s3://eodata/pfad/K1",
                  "bytes": 999}
        heads = []

        def _head(key):
            heads.append(key)
            return len(inhalt), etag

        versuche = []

        def _copy_kaputt_dann_gut(_s3, target):
            versuche.append(target)
            data = b"kaputt" if len(versuche) < 2 else inhalt
            with open(target, "wb") as f:
                f.write(data)

        paths = download_tiles([kachel], tiles_tmp,
                               copy_fn=_copy_kaputt_dann_gut, head_fn=_head)
        assert heads == ["pfad/K1/K1.tif"], heads
        assert len(versuche) == 2 and paths[0].endswith("K1.tif")
        with open(paths[0], "rb") as f:
            assert f.read() == inhalt

        # Multipart-ETag („…-N") ist kein MD5 — dann zählt die Größe.
        download_tiles([dict(kachel, name="K2")], tiles_tmp,
                       copy_fn=lambda _s3, t: open(t, "wb").write(inhalt),
                       head_fn=lambda _k: (len(inhalt), etag + "-2"))

        # Richtige Größe, falscher Inhalt → das ETag muss es fangen.
        try:
            download_tiles([dict(kachel, name="K3")], tiles_tmp,
                           copy_fn=lambda _s3, t: open(t, "wb").write(
                               b"x" * len(inhalt)),
                           head_fn=_head)
            raise AssertionError("falsches ETag nicht erkannt")
        except SystemExit:
            pass

    _self_test_build()
    _self_test_hex_assign()
    _self_test_hex_build()
    _self_test_blocks()

    print("self-test: ok")



def _self_test_blocks():
    """Der Block-Schneider: Jeder Block ist die exakte Teilmatrix, die
    Parität stimmt (Schnitt an geraden Zeilen), und die Katalog-Bboxen
    decken den Block samt odd-r-Überhang."""
    import tempfile as _tempfile
    rows = [bytes((x + y) % 103 for x in range(37)) for y in range(29)]
    with _tempfile.TemporaryDirectory() as out:
        payload = encode(rows)
        with open(os.path.join(out, "forest_grid.bin.gz"), "wb") as f:
            f.write(payload)
        with open(os.path.join(out, "forest_manifest.json"), "w") as f:
            json.dump({
                "source": "t", "reference_year": 2024,
                "lattice": "hex-odd-r", "width": 37, "height": 29,
                "west": 5.8, "north": 55.1,
                "hex_lon_step": 0.1, "hex_lat_step": 0.15,
                "cell_factor": 25, "tree_threshold": 0.2,
            }, f)
        index = cut_blocks(out, block_deg=1.0)
        assert index["lattice"] == "hex-odd-r"
        seen = bytearray(37 * 29)
        for block in index["blocks"]:
            with open(os.path.join(out, block["file"]), "rb") as f:
                got = decode(f.read(), block["width"], block["height"])
            # Anker zurück auf globale Indizes rechnen.
            hx0 = round((block["west"] - 5.8) / 0.1)
            hy0 = round((55.1 - block["north"]) / 0.15)
            assert hy0 % 2 == 0, "Block beginnt an UNGERADER Zeile"
            for j, row in enumerate(got):
                assert row == rows[hy0 + j][hx0:hx0 + block["width"]], \
                    (block["file"], j)
                for i in range(block["width"]):
                    seen[(hy0 + j) * 37 + hx0 + i] += 1
        assert all(v == 1 for v in seen), "Lücke oder Überlappung"


def _self_test_hex_assign():
    """Die Lauf-Zerlegung gegen die Referenz (nächster Mittelpunkt):
    jedes Pixel genau einmal, im richtigen Hex. Der Lauf-Weg existiert
    nur der Geschwindigkeit wegen — weicht er ab, gewinnt der falsche
    Nachbar still ein paar Pixel, und niemand sieht es je."""
    for factor in (25, 10):
        w = factor * math.sqrt(2 / math.sqrt(3))
        r = w / math.sqrt(3)
        src_w, src_h = 160, 140
        rows = max(1, int((src_h - r) / (1.5 * r)) + 1)
        cols = int(src_w / w) + 1
        for j in range(src_h):
            y = j + 0.5
            seen = [0] * src_w
            for hx, hy, x0, x1 in hex_runs(y, src_w, w, r, rows, cols):
                for i in range(x0, x1):
                    seen[i] += 1
                    assert hex_at(i + 0.5, y, w, r, rows, cols) == (hx, hy), \
                        (factor, i, j, (hx, hy))
            assert all(v == 1 for v in seen), (factor, j)


def _self_test_hex_build():
    """build_hex auf synthetischer Quelle: linke Hälfte Laub, rechte
    Nadel, oben ein NoData-Streifen — die Grenz-Hexe sind gemischt, die
    Fläche bleibt erhalten (jedes gültige Pixel zählt genau einmal)."""
    src_w, src_h = 200, 150
    src_rows = []
    for j in range(src_h):
        if j < 8:
            src_rows.append(bytes([255]) * src_w)
        else:
            src_rows.append(
                bytes([1]) * (src_w // 2) + bytes([2]) * (src_w - src_w // 2))

    def info_fn(_source):
        return src_w, src_h, [10.0, 0.0001, 0, 55.0, 0, -0.0001]

    def band_fn(_source, x, y, bw, bh, out_path):
        window = [row[x:x + bw] for row in src_rows[y:y + bh]]
        with open(out_path, "wb") as f:
            f.write(_fake_tiff_u8(window))

    import tempfile as _tempfile
    with _tempfile.TemporaryDirectory() as out:
        manifest = build_hex("fake", 2024, out, band_rows=64,
                             info_fn=info_fn, band_fn=band_fn)
        assert manifest["lattice"] == "hex-odd-r", manifest
        assert manifest["hex_lon_step"] > 0
        assert manifest["hex_lat_step"] > 0
        with open(os.path.join(out, "forest_grid.bin.gz"), "rb") as f:
            rows = decode(f.read(), manifest["width"], manifest["height"])
        mid = manifest["height"] // 2
        assert rows[mid][0] == 1, rows[mid][0]  # reiner Laub
        assert rows[mid][manifest["width"] - 2] == 101  # reiner Nadel
        w, _ = hex_metrics()
        boundary = rows[mid][int((src_w / 2) / w)]
        assert 1 < boundary < 101, boundary  # Grenz-Hex gemischt
        # Bandgrenzen quer testen: andere Bandhöhe, identisches Ergebnis
        # — sonst hinge der Inhalt an der Lesefenstergröße.
        with _tempfile.TemporaryDirectory() as out2:
            build_hex("fake", 2024, out2, band_rows=17,
                      info_fn=info_fn, band_fn=band_fn)
            with open(os.path.join(out2, "forest_grid.bin.gz"), "rb") as f2:
                assert f2.read() == encode(rows), \
                    "Bandhöhe ändert das Ergebnis"


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
                        choices=["", "build", "fetch", "verify", "blocks"])
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--source")
    parser.add_argument("--year", type=int)
    parser.add_argument("--key")
    parser.add_argument("--out", default="build/forest")
    parser.add_argument("--samples", type=int, default=24)
    parser.add_argument("--cell-factor", type=int, default=CELL_FACTOR,
                        help="Quellpixel je Zelle (25 = ~250 m, "
                             "10 = ~100 m). Größere Gitter sind größere "
                             "Dateien — genau deshalb messbar.")
    parser.add_argument("--block-deg", type=float, default=2.0,
                        help="Blockkante in Grad für das Kommando blocks.")
    parser.add_argument("--lattice", choices=["square", "hex"],
                        default="square",
                        help="Zellform des Gitters: square (Bestand) "
                             "oder hex (#251, odd-r, flächengleich).")
    args = parser.parse_args()

    if args.cell_factor != CELL_FACTOR:
        set_cell_factor(args.cell_factor)

    if args.self_test:
        self_test()
        return
    build_fn = build_hex if args.lattice == "hex" else build
    if args.command == "build":
        manifest = build_fn(args.source, args.year, args.out)
        print(json.dumps(manifest, indent=2))
    elif args.command == "fetch":
        source, year = fetch_direct(args.out)
        manifest = build_fn(source, year, args.out)
        print(json.dumps(manifest, indent=2))
        verify_fn = verify_hex if args.lattice == "hex" else verify
        verify_fn(source, args.out, samples=args.samples)
    elif args.command == "verify":
        verify_fn = verify_hex if args.lattice == "hex" else verify
        verify_fn(args.source, args.out, samples=args.samples)
    elif args.command == "blocks":
        cut_blocks(args.out, block_deg=args.block_deg)
    else:
        parser.error("Kommando oder --self-test angeben")


if __name__ == "__main__":
    main()
