#!/usr/bin/env python3
"""Baut das Baumarten-Gitter der App (#227) aus der DLR-Karte
„Tree Species Germany" (10 m, EPSG:3035).

Stufe 1 der Waldebene (#213) beantwortet „Laub, Misch oder Nadel". Was
über den Partnerpilz entscheidet, ist aber die Art: Fichte oder Kiefer
trennt Marone von Butterpilz, Buche oder Birke trennt Steinpilz von
Birkenpilz. Genau diese eine Auskunft liefert dieses Gitter — als Zeile
im Spot-Blatt, NICHT als Kartenebene.

Läuft in CI (.github/workflows/forest-species.yml), jährlich und von
Hand. Ergebnis ist ein Workflow-Artefakt — kein Release-Tag: Das Gitter
ist ein Asset im APK, sein Update gehört in einen menschengeprüften PR
mit Versions-Bump (dieselbe Begründung wie bei `forest_grid.py`).

**Warum eine eigene Datei und kein Modus von `forest_grid.py`:** andere
Quelle, kein Secret (offener HTTP-Download statt CDSE-S3), andere
Kadenz. Geteilt wird trotzdem alles, was Geometrie ist — dieses Modul
importiert `BOUNDS`, `WARP_WIDTH/HEIGHT`, `hex_metrics`, `hex_runs` und
den GeoTIFF-Leser von dort. Das ist keine Bequemlichkeit, sondern der
Kern des Entwurfs:

**Das Gitter liegt auf EXAKT demselben Hex-Raster wie das Waldgitter.**
Gleiche Bounding Box, gleiche Warp-Größe, gleicher Zellfaktor, also
gleiche `width`/`height` und dieselben Mittelpunkte. Die App schlägt
beide Gitter mit EINEM `hexNearestCell` nach. Ein eigener,
Deutschland-enger Zuschnitt wäre kleiner gewesen — aber eine zweite
Geometrie mit eigener Zuordnung Punkt → Zelle, und zwei Wege zur Zelle,
die auseinanderlaufen können, sind genau die Falle, vor der
`rain_stack.dart` warnt.

Byte-Vertrag je Zelle (das Pendant liest
`lib/features/map/forest_species.dart`):

    Hi-Nibble  führende Laubart:  0 keine · 1 Buche · 2 Eiche
                                  3 Birke · 4 Erle
    Lo-Nibble  führende Nadelart: 0 keine · 1 Fichte · 2 Kiefer
                                  3 Tanne · 4 Douglasie · 5 Lärche
    0xFE       nur Kronenverlust
    0xFF       keine Aussage (außerhalb Deutschlands, oder zu wenig Baum)

Höchster gültiger Nibble-Wert ist 0x45 — 0xFE und 0xFF können also
niemals eine echte Artenkombination verdecken (der Selbsttest hält das
fest).

**Kein Zeilen-Delta.** `forest_grid.py` und `rain_grid.py` kodieren
Zeilen-Delta + gzip; hier wäre das ein Schaden, kein Nutzen. Gemessen an
der echten Karte: 1,98 MB roh-gzip gegen 2,42 MB mit Delta. Klassen
haben kein Gefälle — das Delta zerstört genau die Wiederholungen, von
denen gzip lebt. Das Manifest schreibt `"encoding": "gzip"` deshalb
ausdrücklich hin.

Quellwerte: 0 Kiefer, 1 Fichte, 2 Douglasie, 3 Lärche, 4 Tanne,
5 Buche, 6 Eiche, 7 Birke, 8 Erle, 9 andere, 666 Kronenverlust,
999 keine Daten. Lizenz CC BY 4.0 — die Nennung gehört ins Wald-Blatt
der App, nicht nur hierher.

Nutzung:
  python3 tool/forest_species.py --self-test
  python3 tool/forest_species.py fetch --out build/species
  python3 tool/forest_species.py build --source warped.tif --year 2022 \
      --out build/species
  python3 tool/forest_species.py verify --source warped.tif \
      --out build/species
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import os
import random
import re
import struct
import subprocess
import sys
import tempfile
import urllib.request

from forest_grid import (
    BOUNDS,
    CELL_FACTOR,
    WARP_HEIGHT,
    WARP_WIDTH,
    gdal_band,
    gdal_info,
    hex_center,
    hex_metrics,
    hex_runs,
    read_geotiff,
)

BASE_URL = "https://download.geoservice.dlr.de/TREE_SPECIES_DE/files/"
USER_AGENT = "pilzbuddy-forest-species (github.com/MacBuchi/pilzbuddy)"

# Quellklassen der DLR-Karte.
PINE, SPRUCE, DOUGLAS, LARCH, FIR = 0, 1, 2, 3, 4
BEECH, OAK, BIRCH, ALDER, OTHER = 5, 6, 7, 8, 9
LOSS, NODATA = 666, 999

# Die Halbbyte-Tabellen. Die REIHENFOLGE ist zugleich die
# Gleichstandsregel: Bei exakt gleicher Pixelzahl gewinnt die frühere —
# fest verdrahtet, damit zwei Läufe dasselbe Gitter ergeben.
BROADLEAF_NIBBLE = ((BEECH, 1), (OAK, 2), (BIRCH, 3), (ALDER, 4))
CONIFER_NIBBLE = ((SPRUCE, 1), (PINE, 2), (FIR, 3), (DOUGLAS, 4), (LARCH, 5))

SPECIES_LOSS_ONLY = 0xFE
SPECIES_NO_DATA = 0xFF

# Ab wie viel Baum in der Zelle überhaupt eine Art genannt wird.
#
# Anders als `TREE_THRESHOLD` im Waldgitter ist das KEINE Waldschwelle —
# der Anteil steht schon in der anderen Zeile und kommt aus dem
# verlässlicheren Zwei-Klassen-Produkt. Hier geht es nur darum, dass ein
# einzelnes 10-m-Pixel keinen Baumnamen ins Spot-Blatt schreibt: 5 % der
# Zelle sind ~3100 m², also ein Bestand und kein Rauschpixel. Die
# Schwelle steht im Manifest, damit sie nachlesbar ist.
MIN_TREE_SHARE = 0.05

# Hohe Bytes der Sonderwerte im 16-Bit-Raster (little-endian gelesen):
# 666 = 0x029A, 999 = 0x03E7. Die zehn Artenwerte haben hohes Byte 0 und
# niedrige Bytes 0..9 — beides überschneidungsfrei, deshalb lässt sich
# alles mit `bytes.count` auf den beiden Byte-Ebenen zählen statt mit
# einer Python-Schleife über 5,8 Milliarden Pixel.
LOSS_HI, LOSS_LO = LOSS >> 8, LOSS & 0xFF
NODATA_HI, NODATA_LO = NODATA >> 8, NODATA & 0xFF


# ---------------------------------------------------------------------------
# Kodierung
# ---------------------------------------------------------------------------

def encode(rows):
    """gzip, ohne Zeilen-Delta — Begründung im Modul-Docstring.

    mtime=0 wie beim Waldgitter: Identische Nutzdaten sollen identische
    Prüfsummen ergeben, sonst kann der Review nicht sehen, ob sich
    überhaupt etwas geändert hat.
    """
    return gzip.compress(b"".join(rows), 9, mtime=0)


def decode(payload, width, height):
    """Referenz-Umkehrung für Tests und verify."""
    flat = gzip.decompress(payload)
    if len(flat) != width * height:
        raise ValueError(f"{len(flat)} Bytes, erwartet {width * height}")
    return [flat[y * width:(y + 1) * width] for y in range(height)]


# ---------------------------------------------------------------------------
# Zählen und Packen
# ---------------------------------------------------------------------------

def split_planes(row, little_endian):
    """Zerlegt eine 16-Bit-Zeile in ihre niedrigen und hohen Bytes."""
    return (row[0::2], row[1::2]) if little_endian else (row[1::2], row[0::2])


def count_run(lo, hi, x0, x1):
    """Zählt einen Lauf. Gibt `None`, wenn er ganz ohne Daten ist,
    sonst (species[10], loss, nodata).

    Zwei Vollständigkeitsproben statt eines Vertrauensvorschusses: Die
    hohen Bytes müssen restlos aus {0, 2, 3} bestehen und die niedrigen
    der Artenpixel restlos aus 0..9. Ein unerwarteter Quellwert fliegt
    damit auf, statt still als Kiefer gezählt zu werden.
    """
    length = x1 - x0
    hi_seg = hi[x0:x1]
    nodata = hi_seg.count(NODATA_HI)
    if nodata == length:
        return None
    loss = hi_seg.count(LOSS_HI)
    named = hi_seg.count(0)
    if named + loss + nodata != length:
        raise ValueError("unerwarteter Quellwert: hohes Byte außerhalb "
                         "{0, 2, 3}")
    species = [lo[x0:x1].count(v) for v in range(10)]
    if sum(species) != named:
        raise ValueError("unerwarteter Quellwert: niedriges Byte außerhalb "
                         "0..9 bei hohem Byte 0")
    return species, loss, nodata


def pack_cell(species, loss, total):
    """Der Byte-Vertrag: aus den Zählern das eine Byte."""
    trees = sum(species)
    if total and trees / total >= MIN_TREE_SHARE:
        high = low = 0
        best = 0
        for value, nibble in BROADLEAF_NIBBLE:
            if species[value] > best:
                best, high = species[value], nibble
        best = 0
        for value, nibble in CONIFER_NIBBLE:
            if species[value] > best:
                best, low = species[value], nibble
        return (high << 4) | low
    if total and loss / total >= MIN_TREE_SHARE:
        return SPECIES_LOSS_ONLY
    return SPECIES_NO_DATA


# ---------------------------------------------------------------------------
# build: gewarptes Quell-Raster → Gitter + Manifest
# ---------------------------------------------------------------------------

def build(source, year, out_dir, band_rows=2048, info_fn=None, band_fn=None,
          progress=True):
    """Aggregiert das gewarpte 16-Bit-Raster in das Hex-Gitter.

    Aufbau wie `forest_grid.build_hex` — Akkumulatoren je Hexzeile, weil
    Hexzeilen Pixelzeilen überlappen. Ein Unterschied mit Absicht: Eine
    Hexzeile ganz OHNE Daten ist hier kein Geometriefehler, sondern der
    Normalfall südlich und östlich Deutschlands. Sie wird mit 0xFF
    gefüllt; dass die Geometrie stimmt, prüft stattdessen der Abgleich
    der Maße mit dem Waldgitter (siehe `assert_matches_forest_grid`).
    """
    os.makedirs(out_dir, exist_ok=True)
    info_fn = info_fn or gdal_info
    band_fn = band_fn or gdal_band

    src_w, src_h, gt = info_fn(source)
    w, r = hex_metrics()
    rows = max(1, int((src_h - r) / (1.5 * r)) + 1)
    cols = int(src_w / w) + 1

    acc = {}  # hy -> (total[], loss[], species[10][])
    grid_rows = [None] * rows

    def flush(hy):
        total, loss, species = acc.pop(hy)
        out = bytearray(cols)
        for hx in range(cols):
            out[hx] = pack_cell([s[hx] for s in species], loss[hx], total[hx])
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
                lo, hi = split_planes(row, little)
                # Ganze Zeilen ohne Daten überspringen: südlich und
                # östlich Deutschlands ist das der Großteil des Kastens,
                # und die Lauf-Zerlegung ist der teure Teil.
                if hi.count(NODATA_HI) == src_w:
                    continue
                y = y0 + j + 0.5
                for hx, hy, x0, x1 in hex_runs(y, src_w, w, r, rows, cols):
                    counted = count_run(lo, hi, x0, x1)
                    if counted is None:
                        continue
                    if hy not in acc:
                        acc[hy] = ([0] * cols, [0] * cols,
                                   [[0] * cols for _ in range(10)])
                    total, loss, species = acc[hy]
                    run_species, run_loss, run_nodata = counted
                    total[hx] += (x1 - x0) - run_nodata
                    loss[hx] += run_loss
                    for value, count in enumerate(run_species):
                        if count:
                            species[value][hx] += count
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
    with open(os.path.join(out_dir, "forest_species.bin.gz"), "wb") as f:
        f.write(payload)

    origin_x, origin_y, px_w, px_h = gt[0], gt[3], gt[1], gt[5]
    named = loss_only = no_data = 0
    leading = {}
    for row in grid_rows:
        for byte in row:
            if byte == SPECIES_NO_DATA:
                no_data += 1
            elif byte == SPECIES_LOSS_ONLY:
                loss_only += 1
            else:
                named += 1
                leading[byte] = leading.get(byte, 0) + 1
    manifest = {
        "source": "DLR EOC Tree Species Germany",
        "license": "CC BY 4.0 — © DLR",
        "reference_year": year,
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
        "broadleaf_nibbles": {str(n): v for v, n in BROADLEAF_NIBBLE},
        "conifer_nibbles": {str(n): v for v, n in CONIFER_NIBBLE},
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "named_cells": named,
        "loss_only_cells": loss_only,
        "no_data_cells": no_data,
        "empty_rows": empty,
    }
    with open(os.path.join(out_dir, "forest_species_manifest.json"),
              "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def assert_matches_forest_grid(manifest):
    """Die Zusicherung, die den ganzen Entwurf trägt: dasselbe Raster.

    Nicht gegen das ausgelieferte Asset geprüft (das liegt in CI nicht
    zwingend vor), sondern gegen die Formel, aus der es entsteht — wer
    an BOUNDS, WARP_* oder CELL_FACTOR dreht, verschiebt beide Gitter
    gemeinsam oder fliegt hier auf.
    """
    w, r = hex_metrics()
    cols = int(WARP_WIDTH / w) + 1
    rows = max(1, int((WARP_HEIGHT - r) / (1.5 * r)) + 1)
    if (manifest["width"], manifest["height"]) != (cols, rows):
        raise SystemExit(
            f"Gitter passt nicht zum Waldgitter: "
            f"{manifest['width']}x{manifest['height']} statt {cols}x{rows}")


# ---------------------------------------------------------------------------
# verify: N Zufallszellen aus dem Quell-Raster nachrechnen
# ---------------------------------------------------------------------------

def verify(source, out_dir, samples=24, band_fn=None):
    band_fn = band_fn or gdal_band
    with open(os.path.join(out_dir,
                           "forest_species_manifest.json")) as f:
        manifest = json.load(f)
    with open(os.path.join(out_dir, "forest_species.bin.gz"), "rb") as f:
        rows = decode(f.read(), manifest["width"], manifest["height"])
    src_w, src_h, _ = gdal_info(source)
    w, r = hex_metrics()
    hrows, hcols = manifest["height"], manifest["width"]

    rng = random.Random(20260812)
    checked = bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        tries = 0
        while checked < samples and tries < samples * 400:
            tries += 1
            hx = rng.randrange(hcols)
            hy = rng.randrange(hrows)
            stored = rows[hy][hx]
            # Nur Zellen MIT Aussage prüfen: 0xFF gibt es millionenfach,
            # eine Stichprobe daraus prüfte vor allem die leere Fläche.
            if stored == SPECIES_NO_DATA:
                continue
            _, cy = hex_center(hx, hy, w, r)
            y0 = max(0, int(cy - r))
            y1 = min(src_h, int(math.ceil(cy + r)) + 1)
            band_fn(source, 0, y0, src_w, y1 - y0, strip)
            with open(strip, "rb") as f:
                raw = f.read()
            little = raw[:2] == b"II"
            pixel_rows, _meta, _bits = read_geotiff(raw, allowed_bits=(16,))
            total = loss = 0
            species = [0] * 10
            for j, row in enumerate(pixel_rows):
                lo, hi = split_planes(row, little)
                y = y0 + j + 0.5
                for rhx, rhy, x0, x1 in hex_runs(y, src_w, w, r, hrows,
                                                 hcols):
                    if (rhx, rhy) != (hx, hy):
                        continue
                    counted = count_run(lo, hi, x0, x1)
                    if counted is None:
                        continue
                    run_species, run_loss, run_nodata = counted
                    total += (x1 - x0) - run_nodata
                    loss += run_loss
                    for value, count in enumerate(run_species):
                        species[value] += count
            expect = pack_cell(species, loss, total)
            if expect != stored:
                bad += 1
                print(f"  Hex ({hx},{hy}): gespeichert 0x{stored:02X}, "
                      f"nachgerechnet 0x{expect:02X}", file=sys.stderr)
            checked += 1
    report = [
        f"verify: {checked} Hexe, {bad} Abweichungen",
        f"Zellen mit Artnamen: {manifest['named_cells']}, "
        f"nur Kronenverlust: {manifest['loss_only_cells']}, "
        f"ohne Aussage: {manifest['no_data_cells']}",
        f"Gitter: {manifest['width']}x{manifest['height']}, "
        f"{manifest['bytes'] / 1e6:.2f} MB gepackt, "
        f"Stand {manifest['reference_year']}",
    ]
    print("\n".join(report))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("\n".join(report) + "\n")
    if bad:
        raise SystemExit(f"verify: {bad} Abweichungen")
    return manifest


# ---------------------------------------------------------------------------
# fetch: Quelle holen und warpen
# ---------------------------------------------------------------------------

def _http_text(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode("utf-8", "replace")


def newest_vintage(listing=None):
    """Jüngster Jahrgang aus der Verzeichnisliste des Download-Dienstes.

    Der Dienst hat 2026 einen 2016er-Jahrgang nachgeschoben — die Liste
    ist also die einzige verlässliche Quelle dafür, was es gibt. Ein
    fester Jahrgang im Code würde den Jahres-Cron sinnlos machen.
    """
    text = listing if listing is not None else _http_text(BASE_URL)
    years = {int(m) for m in re.findall(r"treespecies_de_(\d{4})\.tif", text)}
    if not years:
        raise SystemExit("fetch: kein treespecies_de_<Jahr>.tif in der Liste")
    return max(years)


def download(year, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    name = f"treespecies_de_{year}.tif"
    target = os.path.join(out_dir, name)
    request = urllib.request.Request(BASE_URL + name,
                                     headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=600) as response:
        expected = int(response.headers.get("Content-Length", 0))
        with open(target, "wb") as f:
            while chunk := response.read(1 << 20):
                f.write(chunk)
    size = os.path.getsize(target)
    # Der Dienst veröffentlicht keine Prüfsumme; die Länge ist das
    # Einzige, was sich prüfen lässt — ein abgebrochener Download soll
    # nicht als halbe Karte weiterlaufen.
    if expected and size != expected:
        raise SystemExit(f"fetch: {size} Bytes statt {expected}")
    print(f"fetch: {name}, {size / 1e6:.0f} MB", file=sys.stderr)
    return target


def warp(source, out_dir):
    """Auf das Raster des Waldgitters: gleiche Box, gleiche Größe.

    `-r near`, weil die Werte Klassen sind. `-ot UInt16`, weil 666 und
    999 in kein Byte passen. `-dstnodata 999` füllt alles außerhalb
    Deutschlands mit genau dem Wert, den die Quelle selbst für „keine
    Daten" benutzt — eine zweite Sorte Leere wäre eine zweite Sorte
    Fehler.
    """
    west, south, east, north = BOUNDS
    warped = os.path.join(out_dir, "species_4326.tif")
    subprocess.run([
        "gdalwarp", "-q", "-overwrite",
        "-s_srs", "EPSG:3035", "-t_srs", "EPSG:4326",
        "-te", str(west), str(south), str(east), str(north),
        "-ts", str(WARP_WIDTH), str(WARP_HEIGHT),
        "-r", "near", "-ot", "UInt16",
        "-srcnodata", str(NODATA), "-dstnodata", str(NODATA),
        "-multi", "-wo", "NUM_THREADS=ALL_CPUS", "-wm", "1024",
        "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES",
        "-co", "BIGTIFF=YES", "-co", "NUM_THREADS=ALL_CPUS",
        source, warped], check=True)
    return warped


def fetch(out_dir):
    year = newest_vintage()
    print(f"fetch: jüngster Jahrgang {year}", file=sys.stderr)
    cog = download(year, out_dir)
    warped = warp(cog, out_dir)
    # Die Quelle wiegt eine halbe Milliarde Bytes und wird ab hier nicht
    # mehr gebraucht — auf dem Runner ist Platte das knappere Gut als
    # Zeit, und ein zweiter Download wäre im Fehlerfall billiger als ein
    # abgebrochener Lauf wegen voller Platte.
    os.remove(cog)
    return warped, year


# ---------------------------------------------------------------------------
# Selbsttest
# ---------------------------------------------------------------------------

def _fake_tiff_u16(rows_values, little=True):
    """Minimales unkomprimiertes uint16-GeoTIFF, ein Streifen."""
    endian = "<" if little else ">"
    width = len(rows_values[0])
    height = len(rows_values)
    pixel = b"".join(struct.pack(endian + "H" * width, *row)
                     for row in rows_values)
    data_offset = 8
    ifd_offset = data_offset + len(pixel)
    tags = [
        (256, 3, 1, width), (257, 3, 1, height), (258, 3, 1, 16),
        (259, 3, 1, 1), (262, 3, 1, 1), (273, 4, 1, data_offset),
        (277, 3, 1, 1), (278, 3, 1, height), (279, 4, 1, len(pixel)),
    ]
    total = len(tags) + 2
    extra = ifd_offset + 2 + total * 12 + 4
    tie = struct.pack(endian + "6d", 0, 0, 0, 10.0, 55.0, 0)
    scale = struct.pack(endian + "3d", 0.0001, 0.0001, 0)
    all_tags = sorted(tags + [(33550, 12, 3, extra),
                              (33922, 12, 6, extra + len(scale))])
    out = bytearray(b"II*\x00" if little else b"MM\x00*")
    out += struct.pack(endian + "I", ifd_offset)
    out += pixel
    out += struct.pack(endian + "H", len(all_tags))
    for tag, kind, num, value in all_tags:
        out += struct.pack(endian + "HHI", tag, kind, num)
        # Das Wertfeld ist 4 Byte und LINKSBÜNDIG. Bei little-endian
        # fällt das nicht auf (ein SHORT als 4-Byte-Zahl steht ohnehin
        # vorn); bei big-endian schon — dort landete der Wert sonst in
        # den hinteren zwei Bytes und der Leser läse null.
        out += (struct.pack(endian + "H", value) + b"\x00\x00"
                if kind == 3 and num == 1
                else struct.pack(endian + "I", value))
    out += struct.pack(endian + "I", 0)
    out += scale
    out += tie
    return bytes(out)


def self_test():
    # Kodierung: Roundtrip, und der gzip-Header ohne Bauzeit.
    rows = [bytes([0x00, 0x12, 0xFF]), bytes([0xFE, 0x45, 0x00])]
    assert decode(encode(rows), 3, 2) == rows
    assert encode(rows)[4:8] == b"\x00\x00\x00\x00", \
        "gzip-Header trägt eine Bauzeit"
    try:
        decode(encode(rows), 2, 2)
        raise AssertionError("falsche Größe nicht erkannt")
    except ValueError:
        pass

    # Die Sonderwerte dürfen keine echte Kombination verdecken.
    highest = (max(n for _, n in BROADLEAF_NIBBLE) << 4) \
        | max(n for _, n in CONIFER_NIBBLE)
    assert highest < SPECIES_LOSS_ONLY, "Nibbles kollidieren mit 0xFE"

    # Byte-Vertrag.
    empty = [0] * 10
    assert pack_cell(empty, 0, 0) == SPECIES_NO_DATA
    assert pack_cell(empty, 0, 625) == SPECIES_NO_DATA
    assert pack_cell(empty, 600, 625) == SPECIES_LOSS_ONLY
    # Zu wenig Baum: kein Name, obwohl Bäume da sind.
    few = list(empty)
    few[BEECH] = 10
    assert pack_cell(few, 0, 625) == SPECIES_NO_DATA
    enough = list(empty)
    enough[BEECH] = 40
    assert pack_cell(enough, 0, 625) == 0x10
    both = list(empty)
    both[SPRUCE], both[BEECH] = 300, 200
    assert pack_cell(both, 0, 625) == 0x11, "Fichte und Buche"
    mixed = list(empty)
    mixed[PINE], mixed[OAK] = 200, 300
    assert pack_cell(mixed, 0, 625) == 0x22, "Kiefer und Eiche"
    only_other = list(empty)
    only_other[OTHER] = 400
    assert pack_cell(only_other, 0, 625) == 0x00, \
        "Bäume ohne benennbare Art sind nicht dasselbe wie keine Daten"
    # Gleichstand: die frühere Art gewinnt, reproduzierbar.
    tie = list(empty)
    tie[BEECH] = tie[OAK] = 100
    assert pack_cell(tie, 0, 625) == 0x10

    # Zählen auf den Byte-Ebenen, beide Bytereihenfolgen.
    for little in (True, False):
        values = [PINE, SPRUCE, BEECH, LOSS, NODATA, OAK, OTHER, BEECH]
        tiff = _fake_tiff_u16([values], little=little)
        pixel_rows, (w, h, _t), bits = read_geotiff(tiff, allowed_bits=(16,))
        assert (w, h, bits) == (len(values), 1, 16)
        lo, hi = split_planes(pixel_rows[0], little)
        species, loss, nodata = count_run(lo, hi, 0, len(values))
        assert loss == 1 and nodata == 1, (loss, nodata)
        assert species[BEECH] == 2 and species[PINE] == 1
        assert species[SPRUCE] == 1 and species[OAK] == 1
        assert species[OTHER] == 1
        assert sum(species) == 6
        # Ein Lauf ganz ohne Daten meldet sich als solcher.
        blank = _fake_tiff_u16([[NODATA] * 4], little=little)
        rows_b, _m, _b = read_geotiff(blank, allowed_bits=(16,))
        lo_b, hi_b = split_planes(rows_b[0], little)
        assert count_run(lo_b, hi_b, 0, 4) is None

    # Unerwartete Quellwerte fliegen auf, statt still mitgezählt oder
    # verschluckt zu werden. ZWEI Fälle, weil es zwei Proben gibt und
    # jede allein gebraucht wird (die Gegenprobe hat gezeigt, dass eine
    # davon sonst von der anderen verdeckt wird):
    #    10 = 0x000A — hohes Byte 0, nur Probe 2 sieht es
    #   256 = 0x0100 — niedriges Byte 0, würde als Kiefer durchgehen
    #   511 = 0x01FF — niedriges Byte 255, nur Probe 1 sieht es
    for bad_value in (10, 256, 511):
        bogus = _fake_tiff_u16([[bad_value, PINE]])
        rows_x, _m, _b = read_geotiff(bogus, allowed_bits=(16,))
        lo_x, hi_x = split_planes(rows_x[0], True)
        try:
            count_run(lo_x, hi_x, 0, 2)
            raise AssertionError(f"Wert {bad_value} nicht erkannt")
        except ValueError:
            pass

    # Ein 8-Bit-Raster darf hier NICHT durchrutschen.
    try:
        read_geotiff(b"II*\x00" + b"\x00" * 32, allowed_bits=(16,))
        raise AssertionError("Schrott als TIFF akzeptiert")
    except (ValueError, struct.error, IndexError):
        pass

    # Jüngsten Jahrgang aus einer Verzeichnisliste lesen.
    listing = ("treespecies_de_2016.tif treespecies_de_2016_readme.txt "
               "treespecies_de_2022.tif")
    assert newest_vintage(listing) == 2022

    # Die Zusicherung, die den Entwurf trägt: dasselbe Raster wie das
    # Waldgitter. Die Zahlen sind die des AUSGELIEFERTEN Assets
    # (assets/forest/forest_manifest.json) — wer an BOUNDS, WARP_* oder
    # CELL_FACTOR dreht, verschiebt beide Gitter gemeinsam oder fliegt
    # hier auf, bevor ein halb passendes Asset entsteht.
    w_, r_ = hex_metrics()
    cols_ = int(WARP_WIDTH / w_) + 1
    rows_ = max(1, int((WARP_HEIGHT - r_) / (1.5 * r_)) + 1)
    assert (cols_, rows_) == (3038, 4470), \
        f"Raster verschoben: {cols_}x{rows_} statt 3038x4470"
    assert_matches_forest_grid({"width": cols_, "height": rows_})
    try:
        assert_matches_forest_grid({"width": cols_ + 1, "height": rows_})
        raise AssertionError("falsche Maße nicht erkannt")
    except SystemExit:
        pass

    # Der ganze Bau gegen ein winziges Raster.
    _self_test_build()
    print("self-test: ok")


def _self_test_build():
    # Hoch genug für MEHRERE Hexzeilen, Daten nur ganz oben: So entstehen
    # Hexzeilen, in die kein einziges Pixel fällt. Genau die sind hier der
    # Normalfall (südlich und östlich Deutschlands) und müssen als 0xFF
    # herauskommen statt als Geometriefehler. Mit dem ersten, kleineren
    # Testraster lief dieser Pfad nie — von der Gegenprobe aufgedeckt.
    grid = [[NODATA] * 60 for _ in range(120)]
    for y in range(0, 20):
        for x in range(0, 30):
            grid[y][x] = SPRUCE if x < 20 else BEECH

    def info_fn(_path):
        return 60, 120, (10.0, 0.0001, 0, 55.0, 0, -0.0001)

    def band_fn(_src, x, y, w, h, out_path):
        sub = [row[x:x + w] for row in grid[y:y + h]]
        with open(out_path, "wb") as f:
            f.write(_fake_tiff_u16(sub))

    with tempfile.TemporaryDirectory() as tmp:
        manifest = build("egal", 2022, tmp, band_rows=16,
                         info_fn=info_fn, band_fn=band_fn,
                         progress=False)
        payload = open(os.path.join(tmp, "forest_species.bin.gz"), "rb").read()
        rows = decode(payload, manifest["width"], manifest["height"])
    assert manifest["encoding"] == "gzip"
    assert len(rows) == manifest["height"]
    values = {b for row in rows for b in row}
    assert SPECIES_NO_DATA in values, "leere Ecke fehlt"
    # Die Fichten-Ecke muss Fichte sein, nicht Buche.
    assert any(b & 0x0F == 1 for row in rows for b in row), \
        f"keine Fichte: {sorted(hex(v) for v in values)}"
    assert any(b >> 4 == 1 for row in rows for b in row), "keine Buche"
    # Hexzeilen ganz ohne Pixel: gezählt UND mit 0xFF gefüllt.
    assert manifest["empty_rows"] > 0, "keine leere Hexzeile im Testraster"
    assert set(rows[-1]) == {SPECIES_NO_DATA}, \
        "leere Hexzeile ist nicht 0xFF"
    assert manifest["no_data_cells"] > manifest["named_cells"]


# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")

    p_fetch = sub.add_parser("fetch", help="holen, warpen, bauen, prüfen")
    p_fetch.add_argument("--out", default="build/species")

    p_build = sub.add_parser("build", help="aus gewarptem Raster bauen")
    p_build.add_argument("--source", required=True)
    p_build.add_argument("--year", type=int, required=True)
    p_build.add_argument("--out", default="build/species")

    p_verify = sub.add_parser("verify", help="Zufallszellen nachrechnen")
    p_verify.add_argument("--source", required=True)
    p_verify.add_argument("--out", default="build/species")
    p_verify.add_argument("--samples", type=int, default=24)

    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.command == "fetch":
        source, year = fetch(args.out)
        manifest = build(source, year, args.out)
        assert_matches_forest_grid(manifest)
        verify(source, args.out)
    elif args.command == "build":
        manifest = build(args.source, args.year, args.out)
        assert_matches_forest_grid(manifest)
        print(json.dumps(manifest, indent=2))
    elif args.command == "verify":
        verify(args.source, args.out, samples=args.samples)
    else:
        parser.error("Kommando oder --self-test angeben")


if __name__ == "__main__":
    main()
