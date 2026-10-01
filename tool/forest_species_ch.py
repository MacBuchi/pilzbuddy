#!/usr/bin/env python3
"""Misst die Schweizer Baumartenkarte gegen das ForestPaths-Rückfallgitter
— bevor irgendetwas davon in die App kommt.

Quelle: Koch, T., Hobi, M., Morsdorf, F., Waser, L. (2024). Tree species
map of Switzerland. EnviDat, doi:10.16904/envidat.506. 10 m, EPSG:3035,
Sentinel-2 2020 + Höhenmodell + Landesforstinventar, Gesamtgenauigkeit
0,759 (nur gegen die eigenen Trainingsdaten). Lizenz CC BY-SA 4.0; die
Autorin (2026-10-01) sieht eine zusammengefasste Fassung als abgeleitetes
Werk — ein späteres Asset bekommt deshalb eine EIGENE Datei. Zugang auf
Anfrage; der Link liegt nur im Secret CH_TREE_SPECIES_URL.

Bekannte Schwächen laut Autorin: Buche und Fichte überschätzt, fast alle
anderen Arten unterschätzt, viele Pixel nicht zugeordnet. Lärche ist
gar nicht unter den 15 Arten.

Quellwerte (Gleitkomma, NaN = kein Wald):

    0 Abies alba         5 Castanea sativa     10 Pinus mugo arborea
    1 Acer pseudoplatanus 6 Fagus sylvatica    11 Pinus sylvestris
    2 Alnus glutinosa    7 Fraxinus excelsior  12 Quercus petraea
    3 Alnus incana       8 Picea abies         13 Quercus robur
    4 Betula pendula     9 Pinus cembra        14 Sorbus aucuparia
   15 außerhalb des Anwendungsbereichs (AOA)   16 Zeitreihe unvollständig

Die Frage des Betreibers (2026-10-01): „eher alle möglichen Arten
listen, die für die Wabe gelistet sind" — also nicht nur die führende
Laub- und Nadelart. Gemessen wird deshalb je Wabe der ANTEIL jeder Art,
und berichtet, wie viele Arten je Wabe bei 5/10/20 % Mindestanteil
stehen blieben, wie groß ein Gitter mit einer Artenmaske je Wabe wäre,
und wie oft die führende Art mit ForestPaths übereinstimmt.

**Gemessen am 2026-10-01** (Lauf 36872705133, Kommentar im PR): 317 650
Waldwaben mit benannter Art; führende Laubart gleich ForestPaths in
96,2 %, führende Nadelart in 88,9 % — die Abweichungen sind fast nur
Tanne (14 578 Waben) und Waldföhre (6 711), wo ForestPaths „Fichte"
sagt, weil es Tanne gar nicht kennt. Bei 10 % Mindestanteil stehen je
Wabe 1–6 Arten (149 025 / 127 215 / 39 101 / 2 112 / 192 / 5).

**Das Asset (`build`)**: Betreiber-Entscheidung vom selben Tag — ALLE
Arten mit mindestens [THRESHOLD] (10 %) der benannten Pixel einer Wabe,
nach Anteil sortiert, Edelkastanie eingeschlossen. 5 % wäre bei einer
Pixel-Trefferquote von 76 % Rauschen, 20 % schnitte echte Mischbestände
ab. Je Wabe DREI Bytes = sechs Halbbytes, vom höchsten an gelesen:

    1..15   Art (Quellwert + 1), nach Anteil absteigend
    0       Ende der Liste
    0x000000  keine Aussage (außerhalb der Karte, zu wenig Wald)
    0xFFFFFF  Wald, aber keine Art benennbar (nur AOA/Zeitreihe)

0xFFFFFF kann keine echte Liste sein — sie hieße sechsmal dieselbe Art.
Gespeichert wird nur das Rechteck um die Schweiz (`x0`/`y0`/`width`/
`height` im Manifest, auf dem Hex-Raster des Waldgitters), damit ein
Leser mit `hexNearestCell` über das GANZE Raster zur Zelle findet und
dann nur verschiebt — ein zweiter Weg zur Zelle wäre einer, der
auseinanderlaufen kann.

Eigene Datei, nicht ins DLR- oder ForestPaths-Gitter gemischt: Die
Quelle steht unter CC BY-SA 4.0, und die Zeile muss je Wabe sagen,
woher sie stammt.

Nutzung:
  python3 tool/forest_species_ch.py --self-test
  python3 tool/forest_species_ch.py measure --source ch.tif --out build/ch
  python3 tool/forest_species_ch.py build --source ch.tif --out build/ch
      (ch.tif ist das Original; es wird zuerst auf das Wabenraster
       des Waldgitters gewarpt)
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

from forest_grid import (
    BOUNDS,
    CELL_FACTOR,
    WARP_HEIGHT,
    WARP_WIDTH,
    _fake_tiff_u8,
    gdal_band,
    gdal_info,
    hex_metrics,
    hex_runs,
    read_geotiff,
)
from forest_species import MIN_TREE_SHARE, SPECIES_NO_DATA, decode

SPECIES = (
    "Abies alba", "Acer pseudoplatanus", "Alnus glutinosa", "Alnus incana",
    "Betula pendula", "Castanea sativa", "Fagus sylvatica",
    "Fraxinus excelsior", "Picea abies", "Pinus cembra",
    "Pinus mugo arborea", "Pinus sylvestris", "Quercus petraea",
    "Quercus robur", "Sorbus aucuparia",
)
N_SPECIES = len(SPECIES)
AOA, INCOMPLETE = 15, 16
N_CLASSES = 17
NODATA = 255

# Für den Vergleich mit ForestPaths: welche Art welchem Halbbyte des
# Rückfallgitters entspricht (Hi = Laub: 1 Buche; Lo = Nadel: 1 Fichte,
# 2 Kiefer). Arven und Bergföhren sind Kiefern (Pinus).
CONIFERS = {0, 8, 9, 10, 11}
FP_CONIFER = {8: 1, 9: 2, 10: 2, 11: 2}
FP_BROADLEAF = {6: 1}

EU_GRID = "assets/forest/forest_species_eu.bin.gz"
EU_MANIFEST = "assets/forest/forest_species_eu_manifest.json"

THRESHOLDS = (0.05, 0.10, 0.20)

# Breite des Schweizer Fensters im Zielraster: BOUNDS beginnt bei
# 5,8° O, die Schweiz endet vor 10,8° O.
CH_EAST = 10.8
CH_SOUTH, CH_NORTH = 45.7, 47.85


def ch_window():
    """(x_end, y0, y1) des Schweizer Fensters in Pixeln des Zielrasters."""
    west, south, east, north = BOUNDS
    x_end = int((CH_EAST - west) / (east - west) * WARP_WIDTH)
    y0 = int((north - CH_NORTH) / (north - south) * WARP_HEIGHT)
    y1 = int((north - CH_SOUTH) / (north - south) * WARP_HEIGHT)
    return x_end, y0, y1


def warp(source, out_dir):
    """Auf das Raster des Waldgitters, wie forest_species_eu.warp — nur
    mit Gleitkomma-Quelle (NaN = kein Wald) und Byte-Ziel.

    Geschrieben wird NUR das Schweizer Fenster, pixelgenau auf dem
    Zielraster ausgerichtet: Das volle Raster sind 8,5 Mrd. Pixel, fast
    alle leer, und der erste Lauf stand damit über anderthalb Stunden im
    Warp. Die Wabenzuordnung rechnet weiter in Koordinaten des vollen
    Rasters (count_cells, y_offset)."""
    west, south, east, north = BOUNDS
    x_end, y0, y1 = ch_window()
    dx = (east - west) / WARP_WIDTH
    dy = (north - south) / WARP_HEIGHT
    warped = os.path.join(out_dir, "species_ch_4326.tif")
    # Erst entpacken und kacheln: Liegt die Quelle als wenige große
    # komprimierte Streifen vor, entpackt gdalwarp für jeden Arbeitsblock
    # den ganzen Streifen neu — die beiden ersten Läufe standen damit
    # Stunden. Ein linearer Durchgang kostet Sekunden und 3,7 GB Platte.
    tiled = os.path.join(out_dir, "species_ch_tiled.tif")
    started = time.time()
    subprocess.run([
        "gdal_translate", "-q", "-co", "TILED=YES", "-co", "COMPRESS=NONE",
        "-co", "BIGTIFF=YES", "--config", "GDAL_CACHEMAX", "2048",
        source, tiled], check=True)
    print(f"  entpackt in {time.time() - started:.0f} s", file=sys.stderr)
    source = tiled
    started = time.time()
    subprocess.run([
        "gdalwarp", "-q", "-overwrite",
        "-s_srs", "EPSG:3035", "-t_srs", "EPSG:4326",
        "-te", repr(west), repr(north - y1 * dy),
        repr(west + x_end * dx), repr(north - y0 * dy),
        "-ts", str(x_end), str(y1 - y0),
        "-r", "near", "-ot", "Byte",
        "-srcnodata", "nan", "-dstnodata", str(NODATA),
        "-multi", "-wo", "NUM_THREADS=ALL_CPUS", "-wm", "1024",
        "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES",
        "-co", "BIGTIFF=YES", "-co", "NUM_THREADS=ALL_CPUS",
        source, warped], check=True)
    print(f"  umgerechnet in {time.time() - started:.0f} s", file=sys.stderr)
    os.remove(tiled)  # 3,7 GB, nur für den Warp gebraucht
    return warped


def count_cells(source, band_rows=1024, info_fn=None, band_fn=None,
                window=None, progress=True, y_offset=0, full_size=None):
    """Je Wabe die Zähler der 17 Klassen: {(hx, hy): [17 Zähler]}.

    [window] = (x_end, y0, y1) in Quellpixeln — nur dieser Ausschnitt
    wird gelesen (die Schweiz ist ein kleiner Teil des Zielrasters).
    """
    info_fn = info_fn or gdal_info
    band_fn = band_fn or gdal_band
    src_w, src_h, _gt = info_fn(source)
    # [y_offset]: Die Quelle ist ein Ausschnitt, dessen Zeile 0 die Zeile
    # y_offset des vollen Rasters ist ([full_size] = dessen Maße).
    full_w, full_h = full_size or (src_w, src_h)
    w, r = hex_metrics()
    rows = max(1, int((full_h - r) / (1.5 * r)) + 1)
    cols = int(full_w / w) + 1
    x_end, y_start, y_end = window or (src_w, 0, src_h)
    cells = {}
    with tempfile.TemporaryDirectory() as tmp:
        strip = os.path.join(tmp, "strip.tif")
        y0 = y_start
        while y0 < y_end:
            h = min(band_rows, y_end - y0)
            band_fn(source, 0, y0, x_end, h, strip)
            with open(strip, "rb") as f:
                pixel_rows, _meta, _bits = read_geotiff(
                    f.read(), allowed_bits=(8,))
            for j, row in enumerate(pixel_rows):
                if row.count(NODATA) == len(row):
                    continue
                y = y_offset + y0 + j + 0.5
                for hx, hy, a, b in hex_runs(y, x_end, w, r, rows, cols):
                    seg = row[a:b]
                    nodata = seg.count(NODATA)
                    if nodata == len(seg):
                        continue
                    counts = cells.get((hx, hy))
                    if counts is None:
                        counts = cells[(hx, hy)] = [0] * N_CLASSES
                    seen = nodata
                    for value in range(N_CLASSES):
                        n = seg.count(value)
                        if n:
                            counts[value] += n
                            seen += n
                    if seen != len(seg):
                        raise ValueError("unerwarteter Quellwert")
            y0 += h
            if progress:
                print(f"  {y0 - y_start}/{y_end - y_start} Zeilen",
                      file=sys.stderr)
    return cells, (rows, cols)


def leading(counts, members):
    best, who = 0, None
    for value in sorted(members):
        if counts[value] > best:
            best, who = counts[value], value
    return who


def summarize(cells, eu_rows=None, cell_pixels=None):
    """Die Kennzahlen als dict — rein, damit der Selbsttest sie prüft."""
    w, _r = hex_metrics()
    cell_pixels = cell_pixels or (w * w * 0.866)  # Wabenfläche in Pixeln
    out = {"cells_with_data": len(cells)}
    classified = {k: sum(c[:N_SPECIES]) for k, c in cells.items()}
    forest = {k: v for k, v in cells.items()
              if sum(v) / cell_pixels >= MIN_TREE_SHARE}
    named = {k for k in forest if classified[k] > 0}
    out["forest_cells"] = len(forest)
    out["named_cells"] = len(named)
    out["only_aoa_or_incomplete_cells"] = len(forest) - len(named)
    totals = [0] * N_CLASSES
    for counts in cells.values():
        for i, n in enumerate(counts):
            totals[i] += n
    out["pixels"] = {name: totals[i] for i, name in enumerate(SPECIES)}
    out["pixels"]["AOA"] = totals[AOA]
    out["pixels"]["incomplete_ts"] = totals[INCOMPLETE]

    per_threshold = {}
    for t in THRESHOLDS:
        presence = [0] * N_SPECIES
        histogram = {}
        masks = []
        for k in named:
            counts, total = cells[k], classified[k]
            present = [i for i in range(N_SPECIES) if counts[i] / total >= t]
            for i in present:
                presence[i] += 1
            histogram[len(present)] = histogram.get(len(present), 0) + 1
            masks.append(sum(1 << i for i in present))
        # Größe eines Gitters mit einer 16-Bit-Maske je Wabe, über das
        # Schweizer Rechteck (sonst 0) — grob, aber in der richtigen
        # Größenordnung für die 4-MB-Regel aus #227.
        if named:
            hxs = [k[0] for k in named]
            hys = [k[1] for k in named]
            # Die Minima EINMAL — je Wabe neu über alle Waben gesucht,
            # war das quadratisch und hielt die ersten Läufe stundenlang.
            x0, y0 = min(hxs), min(hys)
            width = max(hxs) - x0 + 1
            height = max(hys) - y0 + 1
            buf = bytearray(width * height * 2)
            for k, m in zip(named, masks):
                i = ((k[1] - y0) * width + (k[0] - x0)) * 2
                buf[i] = m & 0xFF
                buf[i + 1] = m >> 8
            size = len(gzip.compress(bytes(buf), 9, mtime=0))
        else:
            size = 0
        per_threshold[str(t)] = {
            "cells_per_species": {SPECIES[i]: presence[i]
                                  for i in range(N_SPECIES)},
            "species_per_cell": dict(sorted(histogram.items())),
            "mask_grid_bytes_gzip": size,
        }
    out["thresholds"] = per_threshold

    if eu_rows is not None:
        agree = {"conifer": [0, 0], "broadleaf": [0, 0]}
        eu_silent_ch_named = 0
        ch_lead_where_fp_spruce = {}
        for k in named:
            hx, hy = k
            if hy >= len(eu_rows) or hx >= len(eu_rows[hy]):
                continue
            byte = eu_rows[hy][hx]
            if byte == SPECIES_NO_DATA or byte == 0:
                eu_silent_ch_named += 1
                continue
            counts = cells[k]
            lc = leading(counts, CONIFERS)
            lb = leading(counts, set(range(N_SPECIES)) - CONIFERS)
            fp_c, fp_b = byte & 0x0F, byte >> 4
            if fp_c and lc is not None:
                agree["conifer"][1] += 1
                if FP_CONIFER.get(lc) == fp_c:
                    agree["conifer"][0] += 1
                if fp_c == 1:
                    name = SPECIES[lc]
                    ch_lead_where_fp_spruce[name] = \
                        ch_lead_where_fp_spruce.get(name, 0) + 1
            if fp_b and lb is not None:
                agree["broadleaf"][1] += 1
                if FP_BROADLEAF.get(lb) == fp_b:
                    agree["broadleaf"][0] += 1
        out["vs_forestpaths"] = {
            "conifer_agree_of_both_named": agree["conifer"],
            "broadleaf_agree_of_both_named": agree["broadleaf"],
            "ch_named_where_forestpaths_silent": eu_silent_ch_named,
            "ch_leading_conifer_where_forestpaths_says_spruce":
                dict(sorted(ch_lead_where_fp_spruce.items(),
                            key=lambda kv: -kv[1])),
        }
    return out


def report(stats):
    lines = ["## Schweizer Baumartenkarte gegen ForestPaths", ""]
    lines.append(f"- Waben mit Daten: {stats['cells_with_data']:,}, "
                 f"davon Wald: {stats['forest_cells']:,}, mit benannter "
                 f"Art: {stats['named_cells']:,} (nur AOA/Lücke: "
                 f"{stats['only_aoa_or_incomplete_cells']:,})")
    vs = stats.get("vs_forestpaths")
    if vs:
        c, b = vs["conifer_agree_of_both_named"], vs[
            "broadleaf_agree_of_both_named"]
        pct = lambda a: f"{100 * a[0] / a[1]:.1f} %" if a[1] else "—"
        lines += [
            f"- Führende Nadelart gleich (Fichte/Kiefer): {pct(c)} "
            f"von {c[1]:,} Waben",
            f"- Führende Laubart gleich (Buche): {pct(b)} von {b[1]:,} Waben",
            f"- CH nennt etwas, wo ForestPaths schweigt: "
            f"{vs['ch_named_where_forestpaths_silent']:,} Waben",
            "- Wo ForestPaths „Fichte“ sagt, führt laut CH: " + ", ".join(
                f"{k} {v:,}" for k, v in list(
                    vs["ch_leading_conifer_where_forestpaths_says_spruce"]
                    .items())[:6]),
        ]
    for t, d in stats["thresholds"].items():
        lines += ["", f"### Mindestanteil {float(t) * 100:.0f} %", "",
                  "| Art | Waben |", "|---|---|"]
        for name, n in sorted(d["cells_per_species"].items(),
                              key=lambda kv: -kv[1]):
            lines.append(f"| {name} | {n:,} |")
        lines.append("")
        lines.append("Arten je Wabe: " + ", ".join(
            f"{k}: {v:,}" for k, v in d["species_per_cell"].items()))
        lines.append(f"Gitter mit Artenmaske (16 Bit/Wabe, gzip): "
                     f"{d['mask_grid_bytes_gzip'] / 1e6:.2f} MB")
    return "\n".join(lines) + "\n"


def measure(source, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    warped = warp(source, out_dir)
    x_end, y0, y1 = ch_window()
    cells, _dims = count_cells(warped, window=(x_end, 0, y1 - y0),
                               y_offset=y0,
                               full_size=(WARP_WIDTH, WARP_HEIGHT))
    with open(EU_MANIFEST) as f:
        eu = json.load(f)
    with open(EU_GRID, "rb") as f:
        eu_rows = decode(f.read(), eu["width"], eu["height"])
    stats = summarize(cells, eu_rows)
    with open(os.path.join(out_dir, "ch_measure.json"), "w") as f:
        json.dump(stats, f, indent=2, ensure_ascii=False)
    text = report(stats)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(text)
    return stats


# ---------------------------------------------------------------------------
# build: das Asset
# ---------------------------------------------------------------------------

THRESHOLD = 0.10
SLOTS = 6
COVERED_NONE = 0xFFFFFF
# Fläche einer Wabe in Quellpixeln: 0,866·w² = CELL_FACTOR² = 625.
CELL_PIXELS = 625
ASSET = "forest_species_ch.bin.gz"
MANIFEST = "forest_species_ch_manifest.json"


def pack_species(counts):
    """Drei Bytes je Wabe (siehe Kopf). [counts]: die 17 Klassenzähler."""
    total = sum(counts[:N_SPECIES])
    if total == 0:
        return COVERED_NONE
    present = sorted(
        (i for i in range(N_SPECIES) if counts[i] / total >= THRESHOLD),
        key=lambda i: (-counts[i], i))
    if not present:
        # Ganz gemischt, keine Art erreicht die Schwelle: die führende
        # trotzdem nennen. Eine leere Liste hieße 0 — und 0 ist „keine
        # Aussage", dann spräche an einer Waldwabe ForestPaths.
        present = [min(range(N_SPECIES), key=lambda i: (-counts[i], i))]
    value = 0
    for slot, i in enumerate(present[:SLOTS]):
        value |= (i + 1) << (4 * (SLOTS - 1 - slot))
    return value


def unpack_species(value):
    """Umkehrung für Selbsttest und Gegenprobe: Liste der Quellwerte,
    `None` ohne Aussage, `[]` für „Wald ohne benennbare Art"."""
    if value == 0:
        return None
    if value == COVERED_NONE:
        return []
    out = []
    for slot in range(SLOTS):
        nibble = (value >> (4 * (SLOTS - 1 - slot))) & 0xF
        if nibble == 0:
            break
        out.append(nibble - 1)
    return out


def encode_cells(cells):
    """{(hx, hy): counts} → (Rechteck, gzip-Bytes, Zähler)."""
    kept = {k: pack_species(c) for k, c in cells.items()
            if sum(c[:N_CLASSES]) / CELL_PIXELS >= MIN_TREE_SHARE}
    if not kept:
        raise ValueError("keine einzige Waldwabe")
    x0 = min(k[0] for k in kept)
    y0 = min(k[1] for k in kept)
    width = max(k[0] for k in kept) - x0 + 1
    height = max(k[1] for k in kept) - y0 + 1
    buf = bytearray(width * height * 3)
    for (hx, hy), v in kept.items():
        i = ((hy - y0) * width + (hx - x0)) * 3
        buf[i] = v >> 16
        buf[i + 1] = (v >> 8) & 0xFF
        buf[i + 2] = v & 0xFF
    counts = {
        "named_cells": sum(1 for v in kept.values() if v != COVERED_NONE),
        "unnamed_tree_cells": sum(
            1 for v in kept.values() if v == COVERED_NONE),
    }
    return (x0, y0, width, height), gzip.compress(bytes(buf), 9,
                                                  mtime=0), counts


def check_labels(text):
    """Die Legende der Quelle gegen [SPECIES]: Eine neue Fassung mit
    anderer Reihenfolge ergäbe sonst still die falschen Bäume."""
    found = {}
    for line in text.splitlines():
        if " - " in line:
            code, name = line.split(" - ", 1)
            found[int(code)] = name.strip()
    expected = {i: n for i, n in enumerate(SPECIES)}
    expected.update({AOA: "aoa", INCOMPLETE: "incomplete_ts"})
    if found != expected:
        raise ValueError(f"Legende weicht ab: {found}")


def build(source, out_dir, labels=None):
    if labels:
        with open(labels) as f:
            check_labels(f.read())
    os.makedirs(out_dir, exist_ok=True)
    warped = warp(source, out_dir)
    x_end, y0, y1 = ch_window()
    cells, (rows, cols) = count_cells(
        warped, window=(x_end, 0, y1 - y0), y_offset=y0,
        full_size=(WARP_WIDTH, WARP_HEIGHT))
    (rx, ry, rw, rh), payload, counts = encode_cells(cells)
    west, south, east, north = BOUNDS
    w, r = hex_metrics()
    px_w = (east - west) / WARP_WIDTH
    px_h = (north - south) / WARP_HEIGHT
    manifest = {
        "source": "Tree species map of Switzerland (WSL / UZH)",
        "license": "CC BY-SA 4.0 \u2014 Koch, Hobi, Morsdorf, Waser "
                   "(2024), doi:10.16904/envidat.506",
        "derived": "aggregated to 250 m hex cells: every species with at "
                   "least 10 % of the named pixels of a cell, by share",
        "reference_year": 2020,
        "lattice": "hex-odd-r",
        "encoding": "gzip",
        "cell_bytes": 3,
        "slots": SLOTS,
        "threshold": THRESHOLD,
        "min_tree_share": MIN_TREE_SHARE,
        "species": list(SPECIES),
        "never_named": ["Larix"],
        "grid_width": cols,
        "grid_height": rows,
        "x0": rx,
        "y0": ry,
        "width": rw,
        "height": rh,
        "west": west,
        "east": east,
        "north": north,
        "south": south,
        "hex_lon_step": round(w * px_w, 9),
        "hex_lat_step": round(1.5 * r * abs(px_h), 9),
        "cell_factor": CELL_FACTOR,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        **counts,
    }
    with open(os.path.join(out_dir, ASSET), "wb") as f:
        f.write(payload)
    with open(os.path.join(out_dir, MANIFEST), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    text = (f"## Schweizer Baumartengitter\n\n"
            f"- {counts['named_cells']:,} Waben mit Art, "
            f"{counts['unnamed_tree_cells']:,} Wald ohne benennbare Art\n"
            f"- Rechteck {rw} x {rh} ab ({rx}, {ry}), "
            f"{len(payload) / 1e6:.2f} MB gepackt\n")
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(text)
    return manifest


# ---------------------------------------------------------------------------

def self_test():
    # 60×48 Pixel: links Fichte, Mitte Buche mit eingestreuter Tanne,
    # rechts nur AOA. Unten nichts.
    grid = [[NODATA] * 60 for _ in range(48)]
    for y in range(0, 24):
        for x in range(60):
            if x < 20:
                grid[y][x] = 8
            elif x < 40:
                grid[y][x] = 0 if (x + y) % 5 == 0 else 6
            else:
                grid[y][x] = AOA

    def info_fn(_path):
        return 60, 48, (10.0, 0.0001, 0, 55.0, 0, -0.0001)

    def band_fn(_src, x, y, w, h, out_path):
        sub = [row[x:x + w] for row in grid[y:y + h]]
        with open(out_path, "wb") as f:
            f.write(_fake_tiff_u8(sub))

    cells, (rows, cols) = count_cells("egal", band_rows=7, info_fn=info_fn,
                                      band_fn=band_fn, progress=False)
    total = sum(sum(c) for c in cells.values())
    assert total == 60 * 24, f"Pixel verloren: {total}"
    # ForestPaths-Stellvertreter: überall Fichte + Buche.
    eu_rows = [bytes([0x11]) * cols for _ in range(rows)]
    stats = summarize(cells, eu_rows, cell_pixels=1)
    assert stats["only_aoa_or_incomplete_cells"] > 0, "AOA-Waben fehlen"
    ten = stats["thresholds"]["0.1"]
    assert ten["cells_per_species"]["Abies alba"] > 0, \
        "eingestreute Tanne (20 %) fehlt bei 10 %"
    assert stats["thresholds"]["0.2"]["cells_per_species"]["Abies alba"] \
        <= ten["cells_per_species"]["Abies alba"]
    vs = stats["vs_forestpaths"]
    assert vs["conifer_agree_of_both_named"][0] > 0, "Fichte = Fichte"
    assert "Abies alba" in vs[
        "ch_leading_conifer_where_forestpaths_says_spruce"], \
        "Tanne unter FP-Fichte nicht gezählt"
    assert report(stats).startswith("## Schweizer")

    # Ausschnitt mit Versatz: dieselben Waben wie aus dem vollen Raster.
    # Die Kante liegt mitten in einer Wabenzeile, gerade das muss stimmen.
    offset = 9
    crop = grid[offset:]

    def crop_info(_path):
        return 60, len(crop), None

    def crop_band(_src, x, y, w, h, out_path):
        sub = [row[x:x + w] for row in crop[y:y + h]]
        with open(out_path, "wb") as f:
            f.write(_fake_tiff_u8(sub))

    full = {k: v for k, v in count_cells(
        "egal", band_rows=5, info_fn=info_fn, band_fn=band_fn,
        window=(60, offset, 48), progress=False)[0].items()}
    part, dims = count_cells("egal", band_rows=5, info_fn=crop_info,
                             band_fn=crop_band, progress=False,
                             y_offset=offset, full_size=(60, 48))
    assert dims == (rows, cols), "Wabenraster hängt am Ausschnitt"
    assert part == full, "Versatz verschiebt die Waben"

    # Asset-Kodierung: Reihenfolge nach Anteil, Schwelle, Sonderwerte.
    c = [0] * N_CLASSES
    c[8], c[0], c[6], c[5] = 60, 25, 10, 5   # Fichte, Tanne, Buche, Kastanie
    c[AOA] = 400
    assert unpack_species(pack_species(c)) == [8, 0, 6], \
        unpack_species(pack_species(c))
    c[5] = 0
    c[14] = 40                                # Vogelbeere: Halbbyte 15
    assert unpack_species(pack_species(c))[0] == 8
    assert 14 in unpack_species(pack_species(c))
    assert pack_species([0] * 15 + [100, 3]) == COVERED_NONE
    assert unpack_species(COVERED_NONE) == [] and unpack_species(0) is None
    seven = [10] * 7 + [0] * 10               # 7 × 14 %: nur SLOTS
    assert unpack_species(pack_species(seven)) == list(range(SLOTS))
    flat15 = [10] * N_SPECIES + [0, 0]        # 15 × 6,7 %: die führende
    assert unpack_species(pack_species(flat15)) == [0]
    rect, payload, counts = encode_cells(
        {(5, 7): [0] * 8 + [400] + [0] * 8,         # Fichte, Wald
         (6, 9): [0] * 15 + [500, 0],               # nur AOA
         (9, 8): [0] * 8 + [3] + [0] * 8})          # zu wenig Wald
    assert rect == (5, 7, 2, 3), rect
    flat = gzip.decompress(payload)
    assert flat[0:3] == bytes([0x90, 0, 0]), flat[0:3]
    assert flat[-3:] == b"\xff\xff\xff"
    assert counts == {"named_cells": 1, "unnamed_tree_cells": 1}
    check_labels("\n".join(f"{i} - {n}" for i, n in enumerate(SPECIES))
                 + "\n15 - aoa\n16 - incomplete_ts\n")
    try:
        check_labels("0 - Picea abies\n")
    except ValueError:
        pass
    else:
        raise AssertionError("abweichende Legende nicht erkannt")
    print("Selbsttest ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="cmd")
    for name in ("measure", "build"):
        p = sub.add_parser(name)
        p.add_argument("--source", required=True)
        p.add_argument("--out", default="build/ch")
        p.add_argument("--labels")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.cmd == "measure":
        measure(args.source, args.out)
    elif args.cmd == "build":
        build(args.source, args.out, args.labels)
    else:
        parser.print_help()
        sys.exit(2)


if __name__ == "__main__":
    main()
