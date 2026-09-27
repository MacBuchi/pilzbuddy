#!/usr/bin/env python3
"""Baut das Rückfall-Baumartengitter (#624) aus der ForestPaths-Karte
„European Tree Genus Map" (10 m, 2020, EPSG:3035).

Die Artenzeile im Spot-Blatt (#227) kommt aus der DLR-Karte und ist
damit nur für Deutschland da; außerhalb schwieg sie — in Österreich, der
Schweiz und Südtirol an JEDEM Spot. Dieses Gitter springt genau dort
ein, wo das DLR-Gitter nichts sagt, und nur mit den Gattungen, die die
Karte nachweislich trifft.

**Gemessen, nicht geglaubt** (2026-09-27, Kachelspalte ulx_4400 auf
unseren Waben gegen die DLR-Karte, 269 885 Waben): Wenn ForestPaths
eine Gattung nennt, stimmt sie bei Fichte in 76 % (bayerische Alpen
97 %), bei Buche in 91 % (97 %), bei Kiefer in 76 % (46 %, nur 48
Waben). Lärche erkennt sie praktisch nie (1,5 % der DLR-Lärchenwaben),
Eiche kaum (2 %), „andere Laub" stimmt in 28 %. Daraus die Regel:

    genannt werden NUR Fichte, Kiefer und Buche.

Die führende Gattung wird trotzdem über ALLE Klassen ihrer Blattart
bestimmt, Lärche und „andere" eingeschlossen — und fällt erst DANACH
weg, wenn sie nicht zu den dreien gehört. Genau so ist gemessen worden.
Die Alternative („die führende unter den dreien") nennte eine Fichte in
einem Lärchenbestand, sobald dort ein einziges Fichtenpixel liegt, und
hätte mit den gemessenen Trefferquoten nichts mehr zu tun.

**Der blinde Fleck bleibt und gehört in die Anzeige:** Wo ForestPaths
„Fichte" sagt, kann durchaus Lärche stehen — sie wird nur nicht
erkannt. Die App schreibt deshalb dazu, woher die Zeile kommt und dass
Lärche darin nicht vorkommen kann. Das ist nicht Sache dieses Werkzeugs,
aber der Grund, warum das Gitter eine EIGENE Datei ist und nicht in das
DLR-Gitter gemischt wird: Die Anzeige muss je Wabe wissen, woher die
Aussage stammt.

**Deutschland ist ausgespart**, nicht nur überstimmt: Jede Wabe, zu der
das ausgelieferte DLR-Gitter etwas sagt (Art, nur „andere", oder
Kronenverlust), ist hier 0xFF. Das macht die Datei kleiner und die
Vorrangregel auch dann richtig, wenn ein Leser sie vergisst. Die
Prüfsumme des DLR-Gitters, gegen das ausgespart wurde, steht im
Manifest (`mask_sha256`). Ein späteres DLR-Update macht dieses Gitter
nicht falsch — die App fragt zuerst das DLR-Gitter —, es kann nur an
einzelnen Waben schweigen, wo es neu bauen würde.

Byte-Vertrag je Zelle — derselbe wie im DLR-Gitter, damit die App beide
mit demselben Leser liest (`lib/features/map/forest_species.dart`):

    Hi-Nibble  führende Laubart:  0 keine/nicht benennbar · 1 Buche
    Lo-Nibble  führende Nadelart: 0 keine/nicht benennbar · 1 Fichte
                                  2 Kiefer
    0xFF       keine Aussage (Deutschland, außerhalb der Karte, oder
               zu wenig Baum)

Quellwerte: 0 Lärche, 1 Fichte, 2 Kiefer, 3 Buche, 4 Eiche, 5 andere
Nadel, 6 andere Laub, 7 kein Baum, 255 keine Daten. Lizenz CC BY 4.0
(De Keersmaecker et al., doi:10.5281/zenodo.13341104) — die Nennung
gehört ins Wald-Blatt und auf die Lizenzseite der App.

Die Karte ist eine **Vorab-Fassung** (early access, v0.0.1). Das
Werkzeug holt deshalb bewusst den FESTEN Datensatz `RECORD_ID` und nicht
„die neueste Fassung": Eine neue Fassung ist erst nach derselben
Messung (Lärchen-Trefferquote in Deutschland) willkommen. `fetch` meldet
es in der Run-Summary, wenn es eine gibt.

Geometrie, Kodierung und das Hex-Raster sind die des Waldgitters und
des DLR-Gitters (`forest_grid.py`, `forest_species.py`); siehe dort.

Nutzung:
  python3 tool/forest_species_eu.py --self-test
  python3 tool/forest_species_eu.py fetch --out build/species_eu
  python3 tool/forest_species_eu.py build --source warped.tif \\
      --out build/species_eu
  python3 tool/forest_species_eu.py verify --source warped.tif \\
      --out build/species_eu
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

from forest_grid import (
    BOUNDS,
    CELL_FACTOR,
    WARP_HEIGHT,
    WARP_WIDTH,
    _fake_tiff_u8,
    gdal_band,
    gdal_info,
    hex_center,
    hex_metrics,
    hex_runs,
    read_geotiff,
)
from forest_species import (
    MIN_TREE_SHARE,
    SPECIES_NO_DATA,
    assert_matches_forest_grid,
    decode,
    encode,
)

RECORD_ID = 13341104
API = "https://zenodo.org/api/records/"
USER_AGENT = "pilzbuddy-forest-species-eu (github.com/MacBuchi/pilzbuddy)"
REFERENCE_YEAR = 2020

# Quellklassen der ForestPaths-Karte.
LARIX, PICEA, PINUS, FAGUS, QUERCUS, OTHER_NL, OTHER_BL, NO_TREES = range(8)
NODATA = 255

# Die Klassen je Blattart in der Reihenfolge der GLEICHSTANDSREGEL (bei
# exakt gleicher Pixelzahl gewinnt die frühere) — dieselbe Reihenfolge
# wie in der Messung vom 2026-09-27. Das zweite Element ist das Halbbyte
# oder 0, wenn die Gattung nicht genannt wird.
BROADLEAF_ORDER = ((FAGUS, 1), (QUERCUS, 0), (OTHER_BL, 0))
CONIFER_ORDER = ((PICEA, 1), (PINUS, 2), (LARIX, 0), (OTHER_NL, 0))

# Das ausgelieferte DLR-Gitter, gegen das Deutschland ausgespart wird.
DLR_GRID = "assets/forest/forest_species.bin.gz"
DLR_MANIFEST = "assets/forest/forest_species_manifest.json"

TILE_RE = re.compile(r"spp_pred_ulx_(\d+)_uly_(\d+)\.tif$")
ZIP_RE = re.compile(r"^ulx_(\d+)\.zip$")
TILE_KM = 100


# ---------------------------------------------------------------------------
# Packen
# ---------------------------------------------------------------------------

def _leading_nibble(counts, order):
    best = 0
    nibble = 0
    for value, named in order:
        if counts[value] > best:
            best, nibble = counts[value], named
    return nibble


def pack_cell(counts, total):
    """Der Byte-Vertrag: aus den Zählern (8 Klassen) das eine Byte."""
    trees = sum(counts[:NO_TREES])
    if total and trees / total >= MIN_TREE_SHARE:
        return (_leading_nibble(counts, BROADLEAF_ORDER) << 4) \
            | _leading_nibble(counts, CONIFER_ORDER)
    return SPECIES_NO_DATA


def count_run(seg):
    """Zählt einen Lauf. `None`, wenn er ganz ohne Daten ist, sonst
    (counts[8], nodata). Ein unerwarteter Quellwert fliegt auf, statt
    still unter den Tisch zu fallen."""
    nodata = seg.count(NODATA)
    if nodata == len(seg):
        return None
    counts = [seg.count(v) for v in range(8)]
    if sum(counts) + nodata != len(seg):
        raise ValueError("unerwarteter Quellwert außerhalb 0..7 und 255")
    return counts, nodata


def load_mask(grid_path=DLR_GRID, manifest_path=DLR_MANIFEST):
    """Das DLR-Gitter als Zeilen samt Prüfsumme — geprüft gegen dessen
    eigenes Manifest, damit nicht gegen eine halbe Datei ausgespart
    wird."""
    with open(manifest_path) as f:
        manifest = json.load(f)
    with open(grid_path, "rb") as f:
        payload = f.read()
    sha = hashlib.sha256(payload).hexdigest()
    if sha != manifest["sha256"]:
        raise SystemExit(f"{grid_path} passt nicht zu seinem Manifest")
    return decode(payload, manifest["width"], manifest["height"]), sha


# ---------------------------------------------------------------------------
# build: gewarptes Quell-Raster → Gitter + Manifest
# ---------------------------------------------------------------------------

def build(source, out_dir, mask_rows, mask_sha, band_rows=2048,
          info_fn=None, band_fn=None, progress=True, extra=None):
    """Aggregiert das gewarpte 8-Bit-Raster in das Hex-Gitter.

    Aufbau wie `forest_species.build`: Akkumulatoren je Hexzeile, weil
    Hexzeilen Pixelzeilen überlappen. Ausgesparte Waben (DLR sagt etwas)
    werden gar nicht erst gezählt — das spart den teuren Teil über
    Deutschland.
    """
    os.makedirs(out_dir, exist_ok=True)
    info_fn = info_fn or gdal_info
    band_fn = band_fn or gdal_band

    src_w, src_h, gt = info_fn(source)
    w, r = hex_metrics()
    rows = max(1, int((src_h - r) / (1.5 * r)) + 1)
    cols = int(src_w / w) + 1
    if (len(mask_rows), len(mask_rows[0])) != (rows, cols):
        raise SystemExit(f"Maske {len(mask_rows[0])}x{len(mask_rows)} "
                         f"passt nicht zum Gitter {cols}x{rows}")

    acc = {}  # hy -> (total[], counts[8][])
    grid_rows = [None] * rows

    def flush(hy):
        total, counts = acc.pop(hy)
        out = bytearray(cols)
        for hx in range(cols):
            out[hx] = pack_cell([c[hx] for c in counts], total[hx])
        grid_rows[hy] = bytes(out)

    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        y0 = 0
        while y0 < src_h:
            h = min(band_rows, src_h - y0)
            band_fn(source, 0, y0, src_w, h, strip)
            with open(strip, "rb") as f:
                raw = f.read()
            pixel_rows, _meta, _bits = read_geotiff(raw, allowed_bits=(8,))
            for j, row in enumerate(pixel_rows):
                if row.count(NODATA) == src_w:
                    continue
                y = y0 + j + 0.5
                for hx, hy, x0, x1 in hex_runs(y, src_w, w, r, rows, cols):
                    # DIE Maske: Eine ausgesparte Wabe wird nie gezählt
                    # und kommt damit als 0xFF heraus (total 0). Eine
                    # zweite Prüfung beim Packen hätte nie etwas bewirkt
                    # — die Gegenprobe hat es gezeigt.
                    if mask_rows[hy][hx] != SPECIES_NO_DATA:
                        continue
                    counted = count_run(row[x0:x1])
                    if counted is None:
                        continue
                    if hy not in acc:
                        acc[hy] = ([0] * cols,
                                   [[0] * cols for _ in range(8)])
                    total, counts = acc[hy]
                    run_counts, run_nodata = counted
                    total[hx] += (x1 - x0) - run_nodata
                    for value, n in enumerate(run_counts):
                        if n:
                            counts[value][hx] += n
            done_before = int(((y0 + h) - 2 * r) / (1.5 * r))
            for hy in [k for k in acc if k < done_before]:
                flush(hy)
            y0 += h
            if progress:
                print(f"  {y0}/{src_h} Zeilen", file=sys.stderr)
    for hy in list(acc):
        flush(hy)
    empty = sum(1 for row in grid_rows if row is None)
    blank = bytes([SPECIES_NO_DATA]) * cols
    grid_rows = [blank if row is None else row for row in grid_rows]

    payload = encode(grid_rows)
    with open(os.path.join(out_dir, "forest_species_eu.bin.gz"), "wb") as f:
        f.write(payload)

    origin_x, origin_y, px_w, px_h = gt[0], gt[3], gt[1], gt[5]
    named = unnamed = no_data = 0
    for row in grid_rows:
        for byte in row:
            if byte == SPECIES_NO_DATA:
                no_data += 1
            elif byte == 0:
                unnamed += 1
            else:
                named += 1
    manifest = {
        "source": "ForestPaths European Tree Genus Map (early access)",
        "license": "CC BY 4.0 — De Keersmaecker et al., "
                   "doi:10.5281/zenodo.13341104",
        "zenodo_record": RECORD_ID,
        "reference_year": REFERENCE_YEAR,
        "lattice": "hex-odd-r",
        "encoding": "gzip",
        "width": cols,
        "height": rows,
        "west": round(origin_x, 6),
        "east": round(origin_x + src_w * px_w, 6),
        "north": round(origin_y, 6),
        "south": round(origin_y + src_h * px_h, 6),
        "hex_lon_step": round(w * px_w, 9),
        "hex_lat_step": round(1.5 * r * abs(px_h), 9),
        "cell_factor": CELL_FACTOR,
        "min_tree_share": MIN_TREE_SHARE,
        "broadleaf_nibbles": {"1": "Fagus"},
        "conifer_nibbles": {"1": "Picea", "2": "Pinus"},
        "never_named": ["Larix", "Quercus", "other needleleaf",
                        "other broadleaf"],
        "mask_sha256": mask_sha,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "named_cells": named,
        "unnamed_tree_cells": unnamed,
        "no_data_cells": no_data,
        "empty_rows": empty,
    }
    manifest.update(extra or {})
    with open(os.path.join(out_dir, "forest_species_eu_manifest.json"),
              "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


# ---------------------------------------------------------------------------
# verify: N Zufallszellen aus dem Quell-Raster nachrechnen
# ---------------------------------------------------------------------------

def verify(source, out_dir, mask_rows, samples=24, band_fn=None,
           info_fn=None, summary=True):
    band_fn = band_fn or gdal_band
    info_fn = info_fn or gdal_info
    with open(os.path.join(out_dir, "forest_species_eu_manifest.json")) as f:
        manifest = json.load(f)
    with open(os.path.join(out_dir, "forest_species_eu.bin.gz"), "rb") as f:
        rows = decode(f.read(), manifest["width"], manifest["height"])
    src_w, src_h, _ = info_fn(source)
    w, r = hex_metrics()
    hrows, hcols = manifest["height"], manifest["width"]

    rng = random.Random(20260927)
    checked = bad = masked_bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        tries = 0
        while checked < samples and tries < samples * 400:
            tries += 1
            hx = rng.randrange(hcols)
            hy = rng.randrange(hrows)
            stored = rows[hy][hx]
            # Ausgesparte Waben: Die Zusage ist 0xFF, das lässt sich
            # ohne Raster prüfen — und MUSS stimmen, sonst stünden zwei
            # Quellen auf derselben Wabe.
            if mask_rows[hy][hx] != SPECIES_NO_DATA:
                if stored != SPECIES_NO_DATA:
                    masked_bad += 1
                continue
            if stored == SPECIES_NO_DATA:
                continue
            _, cy = hex_center(hx, hy, w, r)
            y0 = max(0, int(cy - r))
            y1 = min(src_h, int(math.ceil(cy + r)) + 1)
            band_fn(source, 0, y0, src_w, y1 - y0, strip)
            with open(strip, "rb") as f:
                raw = f.read()
            pixel_rows, _meta, _bits = read_geotiff(raw, allowed_bits=(8,))
            total = 0
            counts = [0] * 8
            for j, row in enumerate(pixel_rows):
                y = y0 + j + 0.5
                for rhx, rhy, x0, x1 in hex_runs(y, src_w, w, r, hrows,
                                                 hcols):
                    if (rhx, rhy) != (hx, hy):
                        continue
                    counted = count_run(row[x0:x1])
                    if counted is None:
                        continue
                    run_counts, run_nodata = counted
                    total += (x1 - x0) - run_nodata
                    for value, n in enumerate(run_counts):
                        counts[value] += n
            expect = pack_cell(counts, total)
            if expect != stored:
                bad += 1
                print(f"  Hex ({hx},{hy}): gespeichert 0x{stored:02X}, "
                      f"nachgerechnet 0x{expect:02X}", file=sys.stderr)
            checked += 1
    report = [
        f"verify: {checked} Hexe, {bad} Abweichungen, "
        f"{masked_bad} ausgesparte Waben mit Aussage",
        f"Zellen mit Artnamen: {manifest['named_cells']}, "
        f"Bäume ohne nennbare Gattung: {manifest['unnamed_tree_cells']}, "
        f"ohne Aussage: {manifest['no_data_cells']}",
        f"Gitter: {manifest['width']}x{manifest['height']}, "
        f"{manifest['bytes'] / 1e6:.2f} MB gepackt, "
        f"Stand {manifest['reference_year']}",
    ]
    print("\n".join(report))
    # Der Selbsttest läuft in CI mit — dort soll er die Run-Summary des
    # Jobs nicht mit Testzahlen füllen.
    path = os.environ.get("GITHUB_STEP_SUMMARY") if summary else None
    if path:
        with open(path, "a") as f:
            f.write("\n".join(report) + "\n")
    if bad or masked_bad:
        raise SystemExit(f"verify: {bad} Abweichungen, {masked_bad} "
                         f"ausgesparte Waben mit Aussage")
    return manifest


# ---------------------------------------------------------------------------
# fetch: Kacheln wählen, holen, mosaikieren, warpen
# ---------------------------------------------------------------------------

def _http_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read())


def box_extent_3035(transform_fn=None, steps=40):
    """Die App-Box in EPSG:3035 — über Punkte ENTLANG der Kanten, nicht
    nur über die Ecken: In LAEA ist der Nordrand gebogen, die Ecken
    allein unterschätzen die Ausdehnung."""
    west, south, east, north = BOUNDS
    points = []
    for i in range(steps + 1):
        t = i / steps
        lon = west + t * (east - west)
        lat = south + t * (north - south)
        points += [(lon, south), (lon, north), (west, lat), (east, lat)]
    xy = (transform_fn or _gdaltransform)(points)
    xs = [p[0] for p in xy]
    ys = [p[1] for p in xy]
    return min(xs), min(ys), max(xs), max(ys)


def _gdaltransform(points):
    text = "\n".join(f"{lon} {lat}" for lon, lat in points) + "\n"
    out = subprocess.run(
        ["gdaltransform", "-s_srs", "EPSG:4326", "-t_srs", "EPSG:3035"],
        input=text, capture_output=True, text=True, check=True)
    return [tuple(float(v) for v in line.split()[:2])
            for line in out.stdout.splitlines() if line.strip()]


def needed_columns(extent):
    """Die Spalten-Zips (ulx in km), die die Box schneiden."""
    xmin, _ymin, xmax, _ymax = extent
    first = int(xmin // 1000 // TILE_KM) * TILE_KM
    last = int(xmax // 1000 // TILE_KM) * TILE_KM
    return list(range(first, last + 1, TILE_KM))


def needed_tile(name, extent):
    """Schneidet die Kachel (100 km, Name trägt die obere linke Ecke in
    km) die Box?"""
    m = TILE_RE.search(name)
    if not m:
        return False
    ulx, uly = int(m.group(1)) * 1000, int(m.group(2)) * 1000
    xmin, ymin, xmax, ymax = extent
    return (ulx < xmax and ulx + TILE_KM * 1000 > xmin
            and uly > ymin and uly - TILE_KM * 1000 < ymax)


def md5_of(path):
    digest = hashlib.md5()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def download(entry, out_dir):
    target = os.path.join(out_dir, entry["key"])
    url = entry["links"]["self"]
    for attempt in (1, 2):
        request = urllib.request.Request(url,
                                         headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=600) as response, \
                open(target, "wb") as f:
            shutil.copyfileobj(response, f, 1 << 20)
        # Zenodo veröffentlicht je Datei eine md5 — anders als der
        # DLR-Dienst lässt sich hier also mehr prüfen als die Länge.
        if (os.path.getsize(target) == entry["size"]
                and "md5:" + md5_of(target) == entry["checksum"]):
            return target
        print(f"fetch: {entry['key']} beschädigt (Versuch {attempt})",
              file=sys.stderr)
    raise SystemExit(f"fetch: {entry['key']} zweimal beschädigt")


def fetch(out_dir):
    record = _http_json(f"{API}{RECORD_ID}")
    version = record["metadata"].get("version")
    notes = [f"ForestPaths: Datensatz {RECORD_ID}, Fassung {version}"]
    try:
        latest = _http_json(f"{API}{RECORD_ID}/versions/latest")
        if latest.get("id") != RECORD_ID:
            notes.append(
                f"**Neuere Fassung verfügbar: {latest.get('id')} "
                f"({latest['metadata'].get('version')}).** Nicht "
                "automatisch übernommen — erst die Messung aus #624 "
                "wiederholen (Lärchen-Trefferquote in Deutschland).")
    except Exception as e:  # noqa: BLE001 — nur ein Hinweis, kein Tor
        notes.append(f"Versionsabfrage gescheitert: {e}")
    print("\n".join(notes), file=sys.stderr)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("\n".join(notes) + "\n\n")

    extent = box_extent_3035()
    columns = set(needed_columns(extent))
    entries = [e for e in record["files"]
               if (m := ZIP_RE.match(e["key"])) and int(m.group(1)) in columns]
    tiles_dir = os.path.join(out_dir, "tiles")
    os.makedirs(tiles_dir, exist_ok=True)
    tiles = []
    for entry in sorted(entries, key=lambda e: e["key"]):
        archive = download(entry, out_dir)
        with zipfile.ZipFile(archive) as z:
            for name in z.namelist():
                if needed_tile(name, extent):
                    z.extract(name, tiles_dir)
                    tiles.append(os.path.join(tiles_dir, name))
        # Platte ist auf dem Runner das knappe Gut: Zip weg, sobald die
        # gebrauchten Kacheln heraus sind.
        os.remove(archive)
        print(f"fetch: {entry['key']}, {len(tiles)} Kacheln bisher",
              file=sys.stderr)
    if not tiles:
        raise SystemExit("fetch: keine Kachel in der Box")

    vrt = os.path.join(out_dir, "mosaic.vrt")
    subprocess.run(["gdalbuildvrt", "-q", "-srcnodata", str(NODATA),
                    "-vrtnodata", str(NODATA), vrt] + tiles, check=True)
    warped = warp(vrt, out_dir)
    shutil.rmtree(tiles_dir)
    os.remove(vrt)
    return warped, {"zenodo_version": version, "tiles": len(tiles)}


def warp(source, out_dir):
    """Auf das Raster des Waldgitters: gleiche Box, gleiche Größe,
    `-r near`, weil die Werte Klassen sind — wie beim DLR-Gitter."""
    west, south, east, north = BOUNDS
    warped = os.path.join(out_dir, "species_eu_4326.tif")
    subprocess.run([
        "gdalwarp", "-q", "-overwrite",
        "-s_srs", "EPSG:3035", "-t_srs", "EPSG:4326",
        "-te", str(west), str(south), str(east), str(north),
        "-ts", str(WARP_WIDTH), str(WARP_HEIGHT),
        "-r", "near", "-ot", "Byte",
        "-srcnodata", str(NODATA), "-dstnodata", str(NODATA),
        "-multi", "-wo", "NUM_THREADS=ALL_CPUS", "-wm", "1024",
        "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES",
        "-co", "BIGTIFF=YES", "-co", "NUM_THREADS=ALL_CPUS",
        source, warped], check=True)
    return warped


# ---------------------------------------------------------------------------
# Selbsttest
# ---------------------------------------------------------------------------

def self_test():
    # Byte-Vertrag.
    empty = [0] * 8
    assert pack_cell(empty, 0) == SPECIES_NO_DATA
    assert pack_cell(empty, 625) == SPECIES_NO_DATA
    few = list(empty)
    few[FAGUS] = 10
    few[NO_TREES] = 615
    assert pack_cell(few, 625) == SPECIES_NO_DATA, "zu wenig Baum"
    both = list(empty)
    both[PICEA], both[FAGUS] = 300, 200
    assert pack_cell(both, 625) == 0x11, "Fichte und Buche"
    pine = list(empty)
    pine[PINUS] = 300
    assert pack_cell(pine, 625) == 0x02, "Kiefer"

    # Die Regel, an der die Messung hängt: Die führende Gattung wird
    # über ALLE Klassen bestimmt und fällt erst danach weg. Ein
    # Lärchenbestand mit ein paar Fichten ist KEINE Fichte.
    larch = list(empty)
    larch[LARIX], larch[PICEA] = 400, 50
    assert pack_cell(larch, 625) == 0x00, \
        "Lärche führt — dann wird keine Nadelart genannt, nicht die Fichte"
    oak = list(empty)
    oak[QUERCUS], oak[FAGUS] = 300, 100
    assert pack_cell(oak, 625) == 0x00, "Eiche führt — keine Buche"
    other = list(empty)
    other[OTHER_BL], other[FAGUS], other[PICEA] = 300, 100, 200
    assert pack_cell(other, 625) == 0x01, \
        "„andere Laub“ führt — nur die Fichte bleibt"
    # Nichts jenseits der drei darf je im Gitter stehen.
    for value in range(8):
        cell = list(empty)
        cell[value] = 500
        byte = pack_cell(cell, 625)
        assert byte in (0x00, 0x01, 0x02, 0x10, SPECIES_NO_DATA), hex(byte)
    # Gleichstand: die frühere Klasse gewinnt, reproduzierbar.
    tie = list(empty)
    tie[PICEA] = tie[LARIX] = 100
    assert pack_cell(tie, 625) == 0x01
    tie2 = list(empty)
    tie2[LARIX] = tie2[PINUS] = 100
    assert pack_cell(tie2, 625) == 0x02

    # Zählen: Daten, Lücken, fremde Werte.
    counts, nodata = count_run(bytes([PICEA, FAGUS, NODATA, NO_TREES]))
    assert nodata == 1 and counts[PICEA] == 1 and counts[NO_TREES] == 1
    assert count_run(bytes([NODATA] * 3)) is None
    try:
        count_run(bytes([PICEA, 9]))
        raise AssertionError("Wert 9 nicht erkannt")
    except ValueError:
        pass

    # Kachelwahl über die Namen.
    extent = (4_390_000, 2_550_000, 4_610_000, 2_760_000)
    assert needed_columns(extent) == [4300, 4400, 4500, 4600]
    assert needed_tile("spp_pred_ulx_4400_uly_2640.tif", extent)
    assert needed_tile("x/spp_pred_ulx_4300_uly_2640.tif", extent)
    assert not needed_tile("spp_pred_ulx_4400_uly_2540.tif", extent), \
        "Kachel liegt ganz südlich der Box"
    assert not needed_tile("spp_pred_ulx_4700_uly_2640.tif", extent)
    assert not needed_tile("grid.gpkg", extent)
    # Die Box entlang der Kanten, nicht nur an den Ecken.
    seen = []

    def fake_transform(points):
        seen.extend(points)
        return [(lon * 1000, lat * 1000) for lon, lat in points]
    x0, y0, x1, y1 = box_extent_3035(fake_transform, steps=4)
    assert (x0, y0, x1, y1) == (5800, 45700, 17300, 55100)
    assert len(seen) > 4, "nur die Ecken transformiert"

    # Das Raster ist das des Waldgitters.
    w_, r_ = hex_metrics()
    cols_ = int(WARP_WIDTH / w_) + 1
    rows_ = max(1, int((WARP_HEIGHT - r_) / (1.5 * r_)) + 1)
    assert_matches_forest_grid({"width": cols_, "height": rows_})

    _self_test_build()
    print("self-test: ok")


def _self_test_build():
    # Mehrere Hexzeilen, Daten nur oben: leere Hexzeilen müssen 0xFF
    # werden. Links Fichte/Buche, rechts ein Lärchenbestand.
    grid = [[NODATA] * 60 for _ in range(120)]
    for y in range(0, 24):
        for x in range(0, 60):
            grid[y][x] = (PICEA if x < 15 else FAGUS if x < 30
                          else LARIX)

    def info_fn(_path):
        return 60, 120, (10.0, 0.0001, 0, 55.0, 0, -0.0001)

    def band_fn(_src, x, y, w, h, out_path):
        sub = [row[x:x + w] for row in grid[y:y + h]]
        with open(out_path, "wb") as f:
            f.write(_fake_tiff_u8(sub))

    w, r = hex_metrics()
    rows = max(1, int((120 - r) / (1.5 * r)) + 1)
    cols = int(60 / w) + 1
    open_mask = [bytes([SPECIES_NO_DATA]) * cols for _ in range(rows)]
    # Die erste Wabe gehört „Deutschland": DLR sagt dort etwas.
    closed = [bytearray(row) for row in open_mask]
    closed[0][0] = 0x11
    closed = [bytes(row) for row in closed]

    with tempfile.TemporaryDirectory() as tmp:
        free = build("egal", tmp, open_mask, "0" * 64, band_rows=16,
                     info_fn=info_fn, band_fn=band_fn, progress=False)
        free_rows = decode(
            open(os.path.join(tmp, "forest_species_eu.bin.gz"), "rb").read(),
            free["width"], free["height"])
        masked = build("egal", tmp, closed, "1" * 64, band_rows=16,
                       info_fn=info_fn, band_fn=band_fn, progress=False)
        masked_rows = decode(
            open(os.path.join(tmp, "forest_species_eu.bin.gz"), "rb").read(),
            masked["width"], masked["height"])
        # verify rechnet dieselben Waben nach — und fängt eine Wabe, die
        # trotz Maske eine Aussage trägt.
        verify("egal", tmp, closed, samples=4, band_fn=band_fn,
               info_fn=info_fn, summary=False)
        rows_b = [bytearray(x) for x in masked_rows]
        rows_b[0][0] = 0x01
        with open(os.path.join(tmp, "forest_species_eu.bin.gz"), "wb") as f:
            f.write(encode([bytes(x) for x in rows_b]))
        try:
            verify("egal", tmp, closed, samples=400, band_fn=band_fn,
                   info_fn=info_fn, summary=False)
            raise AssertionError("Aussage auf ausgesparter Wabe übersehen")
        except SystemExit:
            pass

    values = {b for row in free_rows for b in row}
    assert free_rows[0][0] != SPECIES_NO_DATA, "Ecke ohne Aussage"
    assert masked_rows[0][0] == SPECIES_NO_DATA, "Maske wirkt nicht"
    assert masked_rows[0][1:] == free_rows[0][1:], \
        "Maske wirkt über ihre Wabe hinaus"
    assert any(b & 0x0F == 1 for b in values), "keine Fichte"
    assert any(b >> 4 == 1 for b in values), "keine Buche"
    # Im Lärchenstreifen: Bäume, aber nichts Nennbares.
    assert 0x00 in values, f"Lärche ergibt nicht 0x00: {sorted(values)}"
    assert free["empty_rows"] > 0
    assert set(free_rows[-1]) == {SPECIES_NO_DATA}
    assert masked["mask_sha256"] == "1" * 64


# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")

    p_fetch = sub.add_parser("fetch", help="holen, warpen, bauen, prüfen")
    p_fetch.add_argument("--out", default="build/species_eu")

    p_build = sub.add_parser("build", help="aus gewarptem Raster bauen")
    p_build.add_argument("--source", required=True)
    p_build.add_argument("--out", default="build/species_eu")

    p_verify = sub.add_parser("verify", help="Zufallszellen nachrechnen")
    p_verify.add_argument("--source", required=True)
    p_verify.add_argument("--out", default="build/species_eu")
    p_verify.add_argument("--samples", type=int, default=24)

    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    mask_rows, mask_sha = load_mask()
    if args.command == "fetch":
        source, extra = fetch(args.out)
        manifest = build(source, args.out, mask_rows, mask_sha, extra=extra)
        assert_matches_forest_grid(manifest)
        verify(source, args.out, mask_rows)
    elif args.command == "build":
        manifest = build(args.source, args.out, mask_rows, mask_sha)
        assert_matches_forest_grid(manifest)
        print(json.dumps(manifest, indent=2))
    elif args.command == "verify":
        verify(args.source, args.out, mask_rows, samples=args.samples)
    else:
        parser.error("Kommando oder --self-test angeben")


if __name__ == "__main__":
    main()
