#!/usr/bin/env python3
"""Baut das Schutzgebiets-Gitter der App (#580) aus OpenStreetMap.

Wo Pilze sammeln VERBOTEN ist, soll die App es sagen — beim Eintragen
eines Fundes und auf der Karte. Beides liest dieses EINE Gitter; kämen
Kartenrand und Hinweis aus zwei Quellen, widersprächen sie sich an
genau den Stellen, an denen es darauf ankommt (die Regel aus #279,
„Fläche und Blatt sagen dasselbe").

**Warum nicht aus den Kartenkacheln.** Die Protomaps-Kacheln tragen je
Fläche nur `kind` — gemessen am 2026-09-23 (Wutachschlucht, Nationalpark
Schwarzwald, Naturpark Thal): Schweizer Regionalparks kommen dort als
`nature_reserve` an, 29 × 16 km groß, und sind von einem
Naturschutzgebiet nicht zu unterscheiden. Hier stehen die vollen Tags.

**Was als „Sammeln verboten" gilt** (Betreiber, 2026-09-23, siehe
[classify]): Naturschutzgebiete, Nationalparks und Kernzonen — auch
Flächen, die NUR `leisure=nature_reserve` tragen (Fehlerrichtung: eine
Warnung zu viel kostet einen Blick auf das Schild, eine zu wenig ein
Bußgeld). NICHT: Landschaftsschutzgebiete, Natur- und Regionalparks,
Natura 2000/FFH, Wasserschutz- und Jagdzonen, Naturdenkmale,
Landschaftsbestandteile, Naturwaldreservate und die Tiroler
Empfehlungszonen. Die Messung der Tags dazu steht in #580.

**Dasselbe Hex-Raster wie das Waldgitter**, Zelle für Zelle — die App
schlägt alle Gitter mit EINEM `hexNearestCell` nach. Die Maße kommen aus
`forest_grid.py` und werden gegen `forest_manifest.json` geprüft.

**Randwaben zählen mit.** Eine Wabe ist markiert, wenn ihr Mittelpunkt
im Gebiet liegt ODER die Grenze durch sie läuft. Ein Gebiet, kleiner als
eine Wabe, bekommt so trotzdem seine Wabe, und am Rand warnt die App
lieber 250 m zu früh als zu spät.

Byte-Vertrag (das Pendant liest `lib/features/map/protected_areas.dart`):
je Zelle ein uint16 little-endian, 0 = kein Gebiet, sonst der 1-basierte
Index in `areas` des Manifests. Überlappen sich Gebiete, gewinnt das
KLEINERE — sein Name ist der genauere („Wutachschlucht" statt
„Naturpark Südschwarzwald" gäbe es ohnehin nicht, aber „Kernzone" statt
„Nationalpark").

Quelle: Geofabrik-Auszüge (OSM, ODbL 1.0). Die Nennung gehört in die App.

Nutzung:
  python3 tool/protected_areas.py --self-test
  python3 tool/protected_areas.py extract --pbf de.pbf at.pbf ch.pbf \\
      --out build/protected
  python3 tool/protected_areas.py report --out build/protected
  python3 tool/protected_areas.py build --out build/protected \\
      --assets assets/protected
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import os
import re
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forest_grid import BOUNDS, CELL_FACTOR, WARP_HEIGHT, WARP_WIDTH, hex_metrics  # noqa: E402

# ---------------------------------------------------------------------------
# Raster — exakt das des Waldgitters
# ---------------------------------------------------------------------------


def lattice():
    """(west, north, lon_step, lat_step, width, height) des Hex-Rasters,
    gerechnet wie in `forest_species.py`."""
    west, south, east, north = BOUNDS
    px_w = (east - west) / WARP_WIDTH
    px_h = (north - south) / WARP_HEIGHT
    w, r = hex_metrics(CELL_FACTOR)
    # Wie `build_hex` in forest_grid.py: Die letzte, angeschnittene
    # Spalte zählt mit.
    width = int(WARP_WIDTH / w) + 1
    height = max(1, int((WARP_HEIGHT - r) / (1.5 * r)) + 1)
    return west, north, w * px_w, 1.5 * r * px_h, width, height


def assert_matches_forest_grid(manifest_path):
    """Bricht ab, wenn das Raster nicht das des Waldgitters ist."""
    if not os.path.exists(manifest_path):
        return
    m = json.load(open(manifest_path))
    west, north, lon_step, lat_step, width, height = lattice()
    mine = (width, height, round(lon_step, 9), round(lat_step, 9))
    theirs = (m["width"], m["height"], m["hex_lon_step"], m["hex_lat_step"])
    if mine != theirs:
        sys.exit(f"Raster weicht vom Waldgitter ab: {mine} gegen {theirs}")


def to_uv(lon, lat, lat_c):
    """(lon, lat) → regelmäßiger Rasterraum (u, v)."""
    west, north, lon_step, lat_step, _, _ = lat_c
    return (lon - west) / lon_step, (north - lat) / lat_step


def nearest_cell(u, v, width, height):
    """Dasselbe wie `hexNearestCell` in `forest_grid.dart`."""
    best = None
    best_d = None
    hy0 = round(v - 2 / 3)
    for hy in range(hy0 - 1, hy0 + 2):
        if hy < 0 or hy >= height:
            continue
        odd = 0.5 if hy & 1 else 0.0
        hx0 = round(u - 0.5 - odd)
        for hx in range(hx0 - 1, hx0 + 2):
            if hx < 0 or hx >= width:
                continue
            du = (u - (hx + 0.5 + odd)) * math.sqrt(3)
            dv = (v - (hy + 2 / 3)) * 1.5
            d = du * du + dv * dv
            if best_d is None or d < best_d:
                best_d, best = d, (hx, hy)
    return best


def rasterize(rings, width, height):
    """Alle Waben eines Polygons (Ringe im (u, v)-Raum, gerade-ungerade-
    Regel — Löcher sind einfach weitere Ringe). Mittelpunkt innen ODER
    Grenze durch die Wabe."""
    cells = set()
    vs = [p[1] for ring in rings for p in ring]
    if not vs:
        return cells
    hy_lo = max(0, math.floor(min(vs) - 2 / 3))
    hy_hi = min(height - 1, math.ceil(max(vs) - 2 / 3))
    edges = []
    for ring in rings:
        for i in range(len(ring) - 1):
            edges.append((ring[i], ring[i + 1]))
    # Mittelpunkte: Zeile für Zeile die Schnittpunkte mit der Mittellinie.
    for hy in range(hy_lo, hy_hi + 1):
        vc = hy + 2 / 3
        xs = []
        for (u1, v1), (u2, v2) in edges:
            if (v1 <= vc < v2) or (v2 <= vc < v1):
                xs.append(u1 + (vc - v1) * (u2 - u1) / (v2 - v1))
        xs.sort()
        odd = 0.5 if hy & 1 else 0.0
        for a, b in zip(xs[0::2], xs[1::2]):
            hx_lo = max(0, math.ceil(a - 0.5 - odd))
            hx_hi = min(width - 1, math.floor(b - 0.5 - odd))
            for hx in range(hx_lo, hx_hi + 1):
                cells.add((hx, hy))
    # Grenze: jede Kante in Schritten unter einer Viertelwabe abgehen.
    for (u1, v1), (u2, v2) in edges:
        n = max(1, math.ceil(max(abs(u2 - u1), abs(v2 - v1)) * 4))
        for k in range(n + 1):
            t = k / n
            c = nearest_cell(u1 + t * (u2 - u1), v1 + t * (v2 - v1),
                             width, height)
            if c:
                cells.add(c)
    return cells


def area_uv(rings):
    """Fläche des Außenrings im (u, v)-Raum (für „kleiner gewinnt").
    Löcher zählen nicht — für eine Rangfolge genügt der Umriss."""
    total = 0.0
    for i, ring in enumerate(rings):
        a = 0.0
        for (u1, v1), (u2, v2) in zip(ring, ring[1:]):
            a += u1 * v2 - u2 * v1
        total += abs(a) / 2 if i == 0 else 0.0
    return total


# ---------------------------------------------------------------------------
# Einordnung
# ---------------------------------------------------------------------------

NATIONAL_PARK = "Nationalpark"
CORE_ZONE = "Kernzone"
NATURE_RESERVE = "Naturschutzgebiet"
KINDS = (NATIONAL_PARK, CORE_ZONE, NATURE_RESERVE)

# Titel oder Namen, die NIE warnen — auch wenn die Schutzklasse es
# anders sagt (in Österreich tragen zwei Naturparks die Klasse eines
# Nationalparks, in Tirol Empfehlungszonen die eines
# Naturschutzgebiets).
_NEVER = re.compile(
    r"naturpark|regionaler naturpark|parc naturel|parco naturale"
    r"|landschaftsschutz|landschaftsbestandteil|landschaftsteil"
    r"|natura ?2000|fauna|flora|ffh|vogelschutz"
    r"|bergwelt tirol|wildruhe|wasserschutz|jagd|schongebiet"
    r"|gebietsverbot|wegegebot|naturdenkmal|naturwaldreservat|bannwald"
    r"|biosph(ä|ae)ren(?!.*kern)",
    re.IGNORECASE)
_RESERVE_TITLE = re.compile(
    r"naturschutzgebiet|r(é|e)serve naturelle|riserva naturale"
    r"|naturreservat", re.IGNORECASE)


def classify(tags):
    """Die Art des Gebiets, wenn dort das Sammeln verboten ist — sonst
    None. Reihenfolge: erst die Ausschlüsse, dann das Strengste."""
    title = (tags.get("protection_title") or "").strip()
    name = (tags.get("name") or "").strip()
    pc = (tags.get("protect_class") or "").strip()
    boundary = tags.get("boundary")
    reserve = tags.get("leisure") == "nature_reserve"
    if _NEVER.search(title) or _NEVER.search(name):
        return None
    if boundary == "national_park" or pc == "2" or "nationalpark" in title.lower():
        return NATIONAL_PARK
    if pc in ("1", "1a", "1b") or "kernzone" in title.lower():
        return CORE_ZONE
    if _RESERVE_TITLE.search(title):
        return NATURE_RESERVE
    if pc == "4" and not title:
        return NATURE_RESERVE
    if reserve and not title and not pc:
        # Nur markiert — Betreiber: warnen.
        return NATURE_RESERVE
    return None


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------


def extract(pbfs, out_dir):
    """osmium: Schutzgebiete herausziehen und als GeoJSON-Zeilen
    schreiben, je Auszug eine Datei. Gibt die Stände der Auszüge zurück."""
    os.makedirs(out_dir, exist_ok=True)
    stamps = {}
    for pbf in pbfs:
        key = os.path.basename(pbf).split("-")[0]
        filtered = os.path.join(out_dir, f"{key}.pa.osm.pbf")
        subprocess.run(
            ["osmium", "tags-filter", "--overwrite", "-o", filtered, pbf,
             "wr/leisure=nature_reserve", "wr/boundary=protected_area",
             "wr/boundary=national_park"], check=True)
        subprocess.run(
            ["osmium", "export", "--overwrite", "-f", "geojsonseq",
             "--geometry-types=polygon", "--add-unique-id=type_id",
             "-x", "print_record_separator=false",
             "-o", os.path.join(out_dir, f"{key}.geojsonseq"), filtered],
            check=True)
        stamp = subprocess.run(
            ["osmium", "fileinfo", "-g",
             "header.option.osmosis_replication_timestamp", pbf],
            capture_output=True, text=True).stdout.strip()
        stamps[key] = stamp
    json.dump(stamps, open(os.path.join(out_dir, "stamps.json"), "w"),
              indent=1)
    return stamps


def features(out_dir):
    for fn in sorted(os.listdir(out_dir)):
        if not fn.endswith(".geojsonseq"):
            continue
        country = fn.split(".")[0]
        for line in open(os.path.join(out_dir, fn)):
            line = line.strip()
            if line:
                f = json.loads(line)
                yield country, f


def polygons(geometry):
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    return []


def report(out_dir):
    """Wie viele Gebiete je Land und Art — und was ausgeschlossen wurde."""
    import collections
    kept = collections.Counter()
    dropped = collections.Counter()
    for country, f in features(out_dir):
        tags = f.get("properties") or {}
        kind = classify(tags)
        title = (tags.get("protection_title") or "")[:40]
        if kind:
            kept[(country, kind)] += 1
        else:
            dropped[(country, title or "-", tags.get("protect_class", "-"))] += 1
    for (c, k), n in sorted(kept.items()):
        print(f"WARNT   {c:12} {k:18} {n}")
    for (c, t, pc), n in dropped.most_common(30):
        print(f"schweigt {c:12} class={pc:4} {t:40} {n}")


def build(out_dir, assets_dir, forest_manifest):
    assert_matches_forest_grid(forest_manifest)
    lat_c = lattice()
    _, _, lon_step, lat_step, width, height = lat_c
    candidates = []
    seen_ids = set()
    for country, f in features(out_dir):
        props = f.get("properties") or {}
        kind = classify(props)
        if not kind:
            continue
        # Ein Gebiet, das über eine Landesgrenze reicht, steht in zwei
        # Auszügen — einmal genügt.
        oid = f.get("id") or props.get("@id")
        if oid in seen_ids:
            continue
        seen_ids.add(oid)
        for poly in polygons(f["geometry"]):
            rings = [[to_uv(lon, lat, lat_c) for lon, lat in ring]
                     for ring in poly]
            candidates.append((area_uv(rings), kind,
                               (props.get("name") or "").strip(), rings))
    # Kleinere zuerst: Wer schon eine Wabe hat, behält sie.
    candidates.sort(key=lambda c: c[0])
    grid = bytearray(width * height * 2)
    areas = []
    index = {}
    for _, kind, name, rings in candidates:
        cells = rasterize(rings, width, height)
        key = (kind, name)
        idx = index.get(key)
        for hx, hy in cells:
            o = (hy * width + hx) * 2
            if grid[o] or grid[o + 1]:
                continue
            if idx is None:
                areas.append({"kind": kind, "name": name})
                idx = index[key] = len(areas)
                if idx > 0xFFFF:
                    sys.exit("mehr als 65535 Gebiete — uint16 reicht nicht")
            struct.pack_into("<H", grid, o, idx)
    payload = gzip.compress(bytes(grid), compresslevel=9, mtime=0)
    os.makedirs(assets_dir, exist_ok=True)
    grid_path = os.path.join(assets_dir, "protected_grid.bin.gz")
    open(grid_path, "wb").write(payload)
    marked = sum(1 for i in range(0, len(grid), 2) if grid[i] or grid[i + 1])
    stamps = {}
    stamps_path = os.path.join(out_dir, "stamps.json")
    if os.path.exists(stamps_path):
        stamps = json.load(open(stamps_path))
    manifest = {
        "source": "OpenStreetMap (Geofabrik-Auszüge)",
        "licence": "ODbL 1.0",
        "attribution": "© OpenStreetMap-Mitwirkende",
        "extracts": stamps,
        "lattice": "hex-odd-r",
        "width": width,
        "height": height,
        "west": BOUNDS[0],
        "east": BOUNDS[2],
        "north": BOUNDS[3],
        "south": BOUNDS[1],
        "hex_lon_step": round(lon_step, 9),
        "hex_lat_step": round(lat_step, 9),
        "encoding": "gzip-u16le",
        "cells_marked": marked,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "areas": areas,
    }
    with open(os.path.join(assets_dir, "protected_manifest.json"), "w") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=0,
                  separators=(",", ":"))
        fh.write("\n")
    print(f"{len(areas)} Gebiete, {marked} Waben markiert, "
          f"Gitter {len(payload) / 1024:.0f} KB")
    return manifest


def lookup(assets_dir, points):
    """Was das Gitter an einer Koordinate sagt — für Stichproben am
    fertigen Gitter, auf demselben Weg, den die App geht."""
    m = json.load(open(os.path.join(assets_dir, "protected_manifest.json")))
    raw = gzip.decompress(
        open(os.path.join(assets_dir, "protected_grid.bin.gz"), "rb").read())
    lat_c = (m["west"], m["north"], m["hex_lon_step"], m["hex_lat_step"],
             m["width"], m["height"])
    out = []
    for lat, lon in points:
        cell = nearest_cell(*to_uv(lon, lat, lat_c), m["width"], m["height"])
        idx = 0
        if cell:
            idx = struct.unpack_from("<H", raw, (cell[1] * m["width"] + cell[0]) * 2)[0]
        area = m["areas"][idx - 1] if idx else None
        out.append(area)
        label = f"{area['kind']} „{area['name']}\"" if area else "kein Gebiet"
        print(f"{lat:.5f},{lon:.5f}  {label}")
    return out


# ---------------------------------------------------------------------------
# Selbsttest (netzfrei)
# ---------------------------------------------------------------------------


def self_test():
    c = classify
    assert c({"leisure": "nature_reserve", "boundary": "protected_area",
              "protect_class": "4",
              "protection_title": "Naturschutzgebiet"}) == NATURE_RESERVE
    assert c({"boundary": "national_park", "name": "Nationalpark Eifel"}) \
        == NATIONAL_PARK
    assert c({"boundary": "protected_area", "protect_class": "1",
              "protection_title": "Biosphärenreservat-Kernzone"}) == CORE_ZONE
    assert c({"leisure": "nature_reserve"}) == NATURE_RESERVE, \
        "nur markiert warnt (Betreiber)"
    # Die Ausschlüsse — jeder ist ein gemessener Fall aus #580.
    assert c({"boundary": "protected_area", "protect_class": "5",
              "protection_title": "Landschaftsschutzgebiet"}) is None
    assert c({"leisure": "nature_reserve", "boundary": "protected_area",
              "protection_title": "Regionaler Naturpark",
              "name": "Naturpark Thal"}) is None, "Schweizer Regionalpark"
    assert c({"boundary": "protected_area", "protect_class": "2",
              "name": "Naturpark Dobratsch"}) is None, "falsch erfasster Naturpark"
    assert c({"boundary": "protected_area", "protect_class": "4",
              "protection_title": 'Schutzzone nach Empfehlung "Bergwelt '
              'Tirol - Miteinander erleben"'}) is None, "Tiroler Empfehlung"
    assert c({"boundary": "protected_area", "protect_class": "97",
              "protection_title": "Fauna-Flora-Habitat"}) is None
    assert c({"boundary": "protected_area", "protect_class": "1",
              "protection_title": "Naturwaldreservat"}) is None
    assert c({"boundary": "protected_area", "protect_class": "7",
              "protection_title": "Naturdenkmal"}) is None
    assert c({"boundary": "protected_area", "protect_class": "12",
              "protection_title": "Wasserschutzgebiet-Schutzzone I"}) is None
    assert c({"boundary": "protected_area",
              "protection_title": "Biosphärengebiet"}) is None
    # Raster: ein Quadrat von 10 × 10 Waben trifft etwa 100 Waben, ein
    # winziges Gebiet trotzdem genau eine.
    w, h = 50, 50
    sq = [[(10, 10), (20, 10), (20, 20), (10, 20), (10, 10)]]
    cells = rasterize(sq, w, h)
    assert 100 <= len(cells) <= 150, len(cells)
    tiny = [[(30.4, 30.3), (30.5, 30.3), (30.5, 30.4), (30.4, 30.3)]]
    assert len(rasterize(tiny, w, h)) == 1
    # Loch: Ein Ring im Ring spart die Mitte aus.
    donut = sq + [[(13, 13), (17, 13), (17, 17), (13, 17), (13, 13)]]
    inner = nearest_cell(15, 15, w, h)
    assert inner in cells and inner not in rasterize(donut, w, h)
    # Nachschlag wie in Dart: Mittelpunkt → eigene Wabe.
    for hy in (4, 5):
        for hx in (3, 8):
            u = hx + 0.5 + (0.5 if hy & 1 else 0.0)
            assert nearest_cell(u, hy + 2 / 3, w, h) == (hx, hy)
    west, north, lon_step, lat_step, width, height = lattice()
    assert (width, height) == (3038, 4470), (width, height)
    print("protected_areas self-test passed (no network)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--self-test", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    e = sub.add_parser("extract")
    e.add_argument("--pbf", nargs="+", required=True)
    e.add_argument("--out", required=True)
    r = sub.add_parser("report")
    r.add_argument("--out", required=True)
    b = sub.add_parser("build")
    b.add_argument("--out", required=True)
    b.add_argument("--assets", required=True)
    b.add_argument("--forest-manifest",
                   default="assets/forest/forest_manifest.json")
    lk = sub.add_parser("lookup")
    lk.add_argument("--assets", required=True)
    lk.add_argument("points", nargs="+", help="lat,lon")
    args = ap.parse_args()
    if args.self_test:
        self_test()
    elif args.cmd == "extract":
        extract(args.pbf, args.out)
    elif args.cmd == "report":
        report(args.out)
    elif args.cmd == "build":
        build(args.out, args.assets, args.forest_manifest)
    elif args.cmd == "lookup":
        lookup(args.assets, [tuple(map(float, p.split(","))) for p in args.points])
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
