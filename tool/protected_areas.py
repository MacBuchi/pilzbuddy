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
LÄUFE je Zeile, alles uint16 little-endian — für jede der `height`
Zeilen erst die Zahl der Läufe, dann je Lauf (x0, Länge, Index). Der
Index ist 1-basiert in `areas` des Manifests; Zellen außerhalb eines
Laufs sind kein Gebiet. **Warum Läufe statt ein Wert je Zelle:** Das
volle Gitter sind 13,6 Mio. Zellen × 2 Byte = 27 MB im Arbeitsspeicher
der App, neben den 13 MB des Waldgitters — für eine Auskunft, die an
5,5 % der Zellen überhaupt etwas sagt. Als Läufe sind es 102 004 × 6
Byte = 0,6 MB (gemessen am ersten DACH-Lauf), und die App muss nie das
volle Gitter auspacken, auch nicht kurz. Überlappen sich Gebiete, gewinnt das
KLEINERE — sein Name ist der genauere („Wutachschlucht" statt
„Naturpark Südschwarzwald" gäbe es ohnehin nicht, aber „Kernzone" statt
„Nationalpark").

**Tirol aus amtlichen Daten** (#623, Betreiber 2026-10-08): Innerhalb
der Landesgrenze zählen NUR die Schutzgebiete des Landes Tirol (TNSchG
2005, CC BY 4.0, „Land Tirol – data.tirol.gv.at"); OSM wird dort
ausgeblendet, damit nie zwei Quellen über dieselbe Fläche streiten. Der
Abgleich am 2026-10-08 gegen das reine OSM-Gitter: 77 % der amtlichen
Naturschutzgebietsfläche fehlten (fast das ganze NSG Karwendel, Tiroler
Lech, Tschirgant, alle drei Sonderschutzgebiete), dafür warnte es in der
ganzen Außenzone des Nationalparks Hohe Tauern und in großen Teilen der
Ruhegebiete Stubaier und Ötztaler Alpen. Warnen: Naturschutz- und
Sonderschutzgebiete, Kernzone des Nationalparks. Still:
Landschaftsschutz- und Ruhegebiete, geschützte Landschaftsteile, die
Außenzone (siehe [classify_tirol]). „In Tirol" heißt: Mittelpunkt der
Wabe in der Landesgrenze aus OSM (`admin_level=4`, aus demselben
Österreich-Auszug). Weitere Länder folgen demselben Muster
(`OFFICIAL`).

Quelle: Geofabrik-Auszüge (OSM, ODbL 1.0), in Tirol das Land Tirol
(CC BY 4.0). Beide Nennungen gehören in die App.

Nutzung:
  python3 tool/protected_areas.py --self-test
  python3 tool/protected_areas.py extract --pbf de.pbf at.pbf ch.pbf \\
      --out build/protected
  python3 tool/protected_areas.py fetch-official --out build/protected
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
import time
import urllib.parse
import urllib.request

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
    """Alle Waben eines Polygons — Mittelpunkt innen ODER Grenze durch
    die Wabe. Siehe [rasterize_split]."""
    inner, edge = rasterize_split(rings, width, height)
    return inner | edge


def rasterize_split(rings, width, height):
    """(Mittelpunkt innen, nur Grenze) — zwei getrennte Mengen, weil
    [build] sie verschieden gewichtet. Ringe im (u, v)-Raum,
    gerade-ungerade-Regel: Löcher sind einfach weitere Ringe."""
    cells = set()
    edge_cells = set()
    vs = [p[1] for ring in rings for p in ring]
    if not vs:
        return cells, edge_cells
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
            if c and c not in cells:
                edge_cells.add(c)
    return cells, edge_cells


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
    None.

    Reihenfolge, und sie ist der Kern: Ein ausdrücklicher Schutztitel
    entscheidet ZUERST. Danach schließen Titel aus, und erst ganz zum
    Schluss der NAME — nur für Flächen, deren Titel nichts sagt (die
    zwei Naturparks mit Nationalpark-Klasse in Österreich). Im ersten
    DACH-Lauf stand der Name vorn und nahm 48 echte Naturschutzgebiete
    heraus: „Vogelschutzgebiet Heisinger Bogen", „Bannwald Wehratal",
    „Markbach und Jagdhäuser Wald"."""
    title = (tags.get("protection_title") or "").strip()
    name = (tags.get("name") or "").strip()
    pc = (tags.get("protect_class") or "").strip()
    boundary = tags.get("boundary")
    reserve = tags.get("leisure") == "nature_reserve"
    lt = title.lower()
    national = ("nationalpark" in lt or boundary == "national_park"
                or pc == "2")
    if national and "kernzone" not in lt:
        # Die EINE Stelle, an der der Name den Titel schlägt: Weißensee
        # und Dobratsch in Kärnten sind Naturparks, tragen in OSM aber
        # Titel UND Grenze eines Nationalparks (gemessen 2026-09-23).
        if re.match(r"naturpark\b", name, re.IGNORECASE):
            return None
        return NATIONAL_PARK
    if "kernzone" in lt:
        return CORE_ZONE
    if _RESERVE_TITLE.search(title):
        return NATURE_RESERVE
    if _NEVER.search(title) or _NEVER.search(name):
        return None
    if pc in ("1", "1a", "1b"):
        return CORE_ZONE
    if pc == "4" and not title:
        return NATURE_RESERVE
    if reserve and not title and not pc:
        # Nur markiert — Betreiber: warnen.
        return NATURE_RESERVE
    return None


# ---------------------------------------------------------------------------
# Amtliche Daten (#623) — ersetzen OSM innerhalb ihres Landes
# ---------------------------------------------------------------------------

SONDERSCHUTZGEBIET = "Sonderschutzgebiet"

# Je Land: woher die Flächen kommen, aus welchem Geofabrik-Auszug die
# Landesgrenze stammt und wie sie dort heißt. Der Schlüssel steht in den
# Dateinamen und in `extracts` des Manifests.
OFFICIAL = {
    "tirol": {
        "url": "https://services3.arcgis.com/hG7UfxX49PQ8XkXh/arcgis/rest/"
               "services/Schutzgebiete_Umwelt/FeatureServer/0/query",
        "extract": "austria",
        "boundary": "Tirol",
        "licence": "CC BY 4.0",
        "attribution": "Land Tirol – data.tirol.gv.at",
    },
}


def classify_tirol(objekt):
    """Die Art eines Tiroler Gebiets nach dem Feld `OBJEKT` — sonst None.

    Betreiber, 2026-10-08 (#623): Naturschutzgebiete (NSG) und
    Sonderschutzgebiete (SSG, dort ist jeder Eingriff verboten) warnen,
    ebenso die Kernzone des Nationalparks Hohe Tauern (NPKZ). Still
    bleiben Landschaftsschutzgebiete (LSG), Ruhegebiete (RG),
    geschützte Landschaftsteile (GLT) und die Außenzone (NPAZ) — dieselbe
    Regel wie bei OSM in #580. Ein unbekanntes Kürzel schweigt; [report]
    zählt es, damit es auffällt."""
    return {"NSG": NATURE_RESERVE, "SSG": NATURE_RESERVE,
            "NPKZ": CORE_ZONE}.get((objekt or "").strip().upper())


def tirol_name(objekt, name):
    """Der Name, den die App zeigt. Das Land führt ihn ohne Art
    („Karwendel"); die App setzt „Naturschutzgebiet" davor. Ein
    Sonderschutzgebiet ist aber keins, deshalb trägt es seine Art selbst
    im Namen (`label` in `protected_areas.dart` erkennt das Wort)."""
    name = (name or "").strip()
    objekt = (objekt or "").strip().upper()
    if objekt == "SSG" and SONDERSCHUTZGEBIET.lower() not in name.lower():
        return f"{SONDERSCHUTZGEBIET} {name}".strip()
    if objekt == "NPKZ" and "nationalpark" not in name.lower():
        return f"Nationalpark {name}".strip()
    return name


def fetch_official(out_dir):
    """Holt die amtlichen Flächen je Land (ArcGIS-Feature-Dienst, WGS84,
    GeoJSON) nach `<land>.official.geojson` und trägt den Abrufzeitpunkt
    in `stamps.json` ein. Bricht ab, wenn der Dienst weniger liefert als
    er zählt — ein halbes Land sähe in der App wie „kein Schutzgebiet"
    aus."""
    os.makedirs(out_dir, exist_ok=True)
    stamps_path = os.path.join(out_dir, "stamps.json")
    stamps = json.load(open(stamps_path)) if os.path.exists(stamps_path) else {}
    for key, cfg in OFFICIAL.items():
        def get(params):
            q = urllib.parse.urlencode({"where": "1=1", **params})
            with urllib.request.urlopen(f"{cfg['url']}?{q}", timeout=300) as r:
                return json.load(r)
        expected = get({"returnCountOnly": "true", "f": "json"})["count"]
        feats = []
        while True:
            page = get({"outFields": "OBJEKT,NAME", "outSR": "4326",
                        "f": "geojson", "resultOffset": len(feats),
                        "resultRecordCount": 500})
            feats += page.get("features") or []
            more = (page.get("exceededTransferLimit")
                    or (page.get("properties") or {}).get(
                        "exceededTransferLimit"))
            if not more or not page.get("features"):
                break
        if len(feats) != expected or not feats:
            sys.exit(f"{key}: {len(feats)} Flächen geholt, der Dienst "
                     f"zählt {expected}")
        json.dump({"type": "FeatureCollection", "features": feats},
                  open(os.path.join(out_dir, f"{key}.official.geojson"), "w"))
        stamps[key] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        print(f"{key}: {len(feats)} Flächen")
    json.dump(stamps, open(stamps_path, "w"), indent=1)


def official_features(out_dir):
    """(land, feature) aus den geholten amtlichen Dateien."""
    for key in OFFICIAL:
        path = os.path.join(out_dir, f"{key}.official.geojson")
        if os.path.exists(path):
            for f in json.load(open(path))["features"]:
                yield key, f


def boundary_rings(out_dir, key, lat_c):
    """Die Landesgrenze als Ringe im (u, v)-Raum — alle Teilflächen
    (Osttirol hängt nicht am Rest)."""
    path = os.path.join(out_dir, f"{key}.boundary.geojsonseq")
    if not os.path.exists(path):
        sys.exit(f"{key}: amtliche Daten, aber keine Landesgrenze ({path}) — "
                 "ohne sie warnte OSM im Land weiter mit")
    rings = []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        f = json.loads(line)
        for poly in polygons(f["geometry"]):
            rings.append([[to_uv(lon, lat, lat_c) for lon, lat in ring]
                          for ring in poly])
    if not rings:
        sys.exit(f"{key}: Landesgrenze ist leer")
    return rings


def official_mask(out_dir, lat_c, width, height):
    """Alle Waben, deren MITTELPUNKT in einem Land mit amtlichen Daten
    liegt — dort hat OSM nichts zu sagen. Nur Mittelpunkte: Eine
    Grenzwabe gehört zur Hälfte dem Nachbarn, und ein bayerisches
    Naturschutzgebiet an der Grenze soll seine Randwabe behalten."""
    mask = set()
    for key in OFFICIAL:
        if not os.path.exists(os.path.join(out_dir, f"{key}.official.geojson")):
            continue
        for rings in boundary_rings(out_dir, key, lat_c):
            inner, _ = rasterize_split(rings, width, height)
            mask |= inner
    return mask


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
        for okey, cfg in OFFICIAL.items():
            if cfg["extract"] == key:
                extract_boundary(pbf, out_dir, okey, cfg["boundary"])
        stamp = subprocess.run(
            ["osmium", "fileinfo", "-g",
             "header.option.osmosis_replication_timestamp", pbf],
            capture_output=True, text=True).stdout.strip()
        stamps[key] = stamp
    json.dump(stamps, open(os.path.join(out_dir, "stamps.json"), "w"),
              indent=1)
    return stamps


def extract_boundary(pbf, out_dir, key, name):
    """Die Landesgrenze (`admin_level=4`, `name`) aus dem Auszug nach
    `<key>.boundary.geojsonseq` — für [official_mask]."""
    filtered = os.path.join(out_dir, f"{key}.admin.osm.pbf")
    subprocess.run(
        ["osmium", "tags-filter", "--overwrite", "-o", filtered, pbf,
         "r/admin_level=4"], check=True)
    every = os.path.join(out_dir, f"{key}.admin.geojsonseq")
    subprocess.run(
        ["osmium", "export", "--overwrite", "-f", "geojsonseq",
         "--geometry-types=polygon", "-x", "print_record_separator=false",
         "-o", every, filtered], check=True)
    kept = []
    for line in open(every):
        line = line.strip()
        if not line:
            continue
        props = json.loads(line).get("properties") or {}
        if (props.get("boundary") == "administrative"
                and props.get("admin_level") == "4"
                and props.get("name") == name):
            kept.append(line)
    if len(kept) != 1:
        sys.exit(f"{key}: {len(kept)} Landesgrenzen „{name}“ gefunden, "
                 "erwartet genau eine")
    with open(os.path.join(out_dir, f"{key}.boundary.geojsonseq"), "w") as fh:
        fh.write(kept[0] + "\n")


def features(out_dir):
    for fn in sorted(os.listdir(out_dir)):
        if not fn.endswith(".geojsonseq") or fn.count(".") != 1:
            # Nur `<auszug>.geojsonseq`; die Landesgrenzen
            # (`<land>.boundary.geojsonseq`) sind keine Schutzgebiete.
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
    official = collections.Counter()
    for key, f in official_features(out_dir):
        props = f.get("properties") or {}
        objekt = props.get("OBJEKT") or "-"
        official[(key, objekt, classify_tirol(objekt) or "schweigt")] += 1
    for (key, objekt, kind), n in sorted(official.items()):
        print(f"AMTLICH {key:12} {objekt:6} {kind:18} {n}")
    for (c, k), n in sorted(kept.items()):
        print(f"WARNT   {c:12} {k:18} {n}")
    for (c, t, pc), n in dropped.most_common(30):
        print(f"schweigt {c:12} class={pc:4} {t:40} {n}")


def assign(split, width, height):
    """Vergibt die Waben: [(kind, name, inner, edge)], KLEINSTES Gebiet
    zuerst. Gibt (Gitter-Bytes, areas) zurück.

    ZWEI Durchgänge: Erst bekommt jedes Gebiet die Waben, deren
    Mittelpunkt in ihm liegt, danach füllen Grenzwaben nur noch LEERE
    Waben auf. In einem Durchgang schlug die gestreifte Teilfläche des
    „Streuewiesenbiotopverbunds" das Ruggeller Riet in dessen eigener
    Mitte — kleiner war sie ja (gemessen am ersten DACH-Lauf)."""
    grid = bytearray(width * height * 2)
    areas = []
    index = {}
    for pass_ in (0, 1):
        for kind, name, inner, edge in split:
            key = (kind, name)
            idx = index.get(key)
            for hx, hy in (inner if pass_ == 0 else edge):
                o = (hy * width + hx) * 2
                if grid[o] or grid[o + 1]:
                    continue
                if idx is None:
                    areas.append({"kind": kind, "name": name})
                    idx = index[key] = len(areas)
                    if idx > 0xFFFF:
                        sys.exit("mehr als 65535 Gebiete — uint16 reicht nicht")
                struct.pack_into("<H", grid, o, idx)
    return grid, areas


def build(out_dir, assets_dir, forest_manifest, previous=None,
          allow_loss=False):
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
                               (props.get("name") or "").strip(), rings,
                               "osm"))
    for key, f in official_features(out_dir):
        props = f.get("properties") or {}
        kind = classify_tirol(props.get("OBJEKT"))
        if not kind:
            continue
        name = tirol_name(props.get("OBJEKT"), props.get("NAME"))
        for poly in polygons(f["geometry"]):
            rings = [[to_uv(p[0], p[1], lat_c) for p in ring] for ring in poly]
            candidates.append((area_uv(rings), kind, name, rings, key))
    # Innerhalb eines Landes mit amtlichen Daten verliert OSM jede Wabe.
    mask = official_mask(out_dir, lat_c, width, height)
    # Kleinere zuerst: Wer schon eine Wabe hat, behält sie.
    candidates.sort(key=lambda c: c[0])
    split = []
    for _, kind, name, rings, origin in candidates:
        inner, edge = rasterize_split(rings, width, height)
        if origin == "osm" and mask:
            inner, edge = inner - mask, edge - mask
        split.append((kind, name, inner, edge))
    grid, areas = assign(split, width, height)
    payload = gzip.compress(encode_runs(grid, width, height),
                            compresslevel=9, mtime=0)
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
        # Länder, in denen statt OSM amtliche Daten stehen (#623).
        "official": {
            key: {"licence": cfg["licence"],
                  "attribution": cfg["attribution"],
                  "areas": sum(1 for k, _ in official_features(out_dir)
                               if k == key)}
            for key, cfg in OFFICIAL.items()
            if os.path.exists(os.path.join(out_dir,
                                           f"{key}.official.geojson"))},
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
        "encoding": "gzip-runs-u16le",
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
    if previous and not allow_loss:
        check_losses(previous, assets_dir, mask)
    return manifest


# Ab wie vielen Waben (≈ 0,054 km² je Wabe, also ~54 km²) ein Gebiet
# nicht still verschwinden darf, und welcher Anteil verloren gehen darf.
LOSS_MIN_CELLS = 1000
LOSS_MAX_SHARE = 0.5


def cells_per_area(assets_dir, outside=frozenset()):
    """{(kind, name): Waben} eines fertigen Gitters, ohne die Waben in
    `outside` (dort hat eine amtliche Quelle OSM ersetzt)."""
    m = json.load(open(os.path.join(assets_dir, "protected_manifest.json")))
    runs = decode_runs(gzip.decompress(
        open(os.path.join(assets_dir, "protected_grid.bin.gz"), "rb").read()),
        m["height"])
    out = {}
    for hy, row in enumerate(runs):
        for x0, n, idx in row:
            a = m["areas"][idx - 1]
            key = (a["kind"], a["name"])
            k = n if not outside else sum(
                1 for hx in range(x0, x0 + n) if (hx, hy) not in outside)
            out[key] = out.get(key, 0) + k
    return out


def losses(before, after):
    """Große Gebiete, die mehr als `LOSS_MAX_SHARE` ihrer Waben verloren
    haben — [(kind, name, vorher, nachher)], größte zuerst.

    Anlass (#623, 2026-10-08): Der Geofabrik-Auszug Deutschland vom
    2026-10-06 erwischte die Relation des Nationalparks Bayerischer Wald
    mitten in einer Bearbeitung, osmium baute aus ihr keine Fläche, und
    der Nationalpark fehlte im Gitter — ohne Fehlermeldung. Der
    Asset-Test hätte es erst nach dem Commit gesehen."""
    lost = []
    for key, n in before.items():
        if n < LOSS_MIN_CELLS:
            continue
        now = after.get(key, 0)
        if now < n * (1 - LOSS_MAX_SHARE):
            lost.append((*key, n, now))
    return sorted(lost, key=lambda x: -x[2])


def check_losses(previous_dir, new_dir, mask):
    """Bricht ab, wenn gegenüber dem bisherigen Gitter ein großes Gebiet
    (fast) verschwunden ist. Waben im amtlichen Bereich zählen nicht —
    dort verschwindet OSM mit Absicht."""
    if not os.path.exists(os.path.join(previous_dir, "protected_manifest.json")):
        return
    lost = losses(cells_per_area(previous_dir, mask),
                  cells_per_area(new_dir, mask))
    for kind, name, n, now in lost:
        print(f"VERLOREN {kind:18} {name[:50]:50} {n:6} → {now:6} Waben")
    if lost:
        sys.exit(f"{len(lost)} große Gebiete verloren — OSM-Stand prüfen "
                 "(halb bearbeitete Relation?), dann neu bauen oder mit "
                 "--allow-loss bewusst übernehmen")


def encode_runs(grid, width, height):
    """uint16-Gitter (2 Byte je Zelle) → Läufe je Zeile, siehe Vertrag."""
    out = bytearray()
    for hy in range(height):
        row = struct.unpack_from(f"<{width}H", grid, hy * width * 2)
        runs = []
        hx = 0
        while hx < width:
            v = row[hx]
            if v == 0:
                hx += 1
                continue
            start = hx
            while hx < width and row[hx] == v:
                hx += 1
            runs.append((start, hx - start, v))
        out += struct.pack("<H", len(runs))
        for run in runs:
            out += struct.pack("<3H", *run)
    return bytes(out)


def decode_runs(raw, height):
    """Läufe je Zeile zurück — [[(x0, Länge, Index), …], …]."""
    rows = []
    o = 0
    for _ in range(height):
        (n,) = struct.unpack_from("<H", raw, o)
        o += 2
        rows.append([struct.unpack_from("<3H", raw, o + 6 * k) for k in range(n)])
        o += 6 * n
    if o != len(raw):
        raise ValueError(f"{len(raw) - o} Byte hinter der letzten Zeile")
    return rows


def index_at(runs, hx, hy):
    """Der Gebietsindex einer Zelle, 0 = keins."""
    for x0, n, idx in runs[hy]:
        if x0 <= hx < x0 + n:
            return idx
    return 0


def lookup(assets_dir, points):
    """Was das Gitter an einer Koordinate sagt — für Stichproben am
    fertigen Gitter, auf demselben Weg, den die App geht."""
    m = json.load(open(os.path.join(assets_dir, "protected_manifest.json")))
    runs = decode_runs(gzip.decompress(
        open(os.path.join(assets_dir, "protected_grid.bin.gz"), "rb").read()),
        m["height"])
    lat_c = (m["west"], m["north"], m["hex_lon_step"], m["hex_lat_step"],
             m["width"], m["height"])
    out = []
    for lat, lon in points:
        cell = nearest_cell(*to_uv(lon, lat, lat_c), m["width"], m["height"])
        idx = 0
        if cell:
            idx = index_at(runs, *cell)
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
    assert c({"boundary": "national_park", "leisure": "nature_reserve",
              "protect_class": "2", "protection_title": "Nationalpark",
              "name": "Naturpark Weißensee"}) is None, "Titel falsch, Name richtig"
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
    # Der Titel schlägt den Namen — alles echte Fälle aus dem ersten
    # DACH-Lauf, die vorher still blieben.
    for name in ("Vogelschutzgebiet Heisinger Bogen", "Bannwald Wehratal",
                 "Naturwaldreservat Eichhall", "Markbach und Jagdhäuser Wald",
                 "Köllnischer Wald - FFH"):
        assert c({"boundary": "protected_area", "protect_class": "4",
                  "protection_title": "Naturschutzgebiet",
                  "name": name}) == NATURE_RESERVE, name
    assert c({"boundary": "protected_area", "protect_class": "4",
              "protection_title": "Fauna Flora Habitat; Naturschutzgebiet",
              "name": "Wildoner Buchkogel"}) == NATURE_RESERVE
    assert c({"boundary": "protected_area", "protect_class": "1",
              "protection_title": "Naturschutzgebiet-Kernzone"}) == CORE_ZONE
    assert c({"boundary": "national_park",
              "name": "Nationalpark Hainich"}) == NATIONAL_PARK
    assert c({"boundary": "national_park", "leisure": "nature_reserve",
              "protect_class": "2", "protection_title": "Naturschutzgebiet",
              "name": "Nationalpark Donau-Auen"}) == NATIONAL_PARK, \
        "Grenze und Klasse schlagen einen Titel, der zu schwach ist"
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
    # Mittelpunkt schlägt Grenze: Das große Gebiet behält seine Mitte,
    # auch wenn die Grenze eines kleineren durch dieselbe Wabe läuft.
    big = [[(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)]]
    sliver = [[(20.0, 20.7), (22.0, 20.7), (22.0, 20.72), (20.0, 20.7)]]
    b_in, _ = rasterize_split(big, w, h)
    s_in, s_edge = rasterize_split(sliver, w, h)
    shared = nearest_cell(20.5, 20 + 2 / 3, w, h)
    assert shared in b_in and shared in s_edge and shared not in s_in
    # … und die Vergabe hält sich daran, obwohl das kleine Gebiet ZUERST
    # dran ist (kleiner gewinnt sonst).
    grid, areas = assign([("Naturschutzgebiet", "klein", s_in, s_edge),
                          ("Nationalpark", "groß", b_in, set())], w, h)
    o = (shared[1] * w + shared[0]) * 2
    assert areas[struct.unpack_from("<H", grid, o)[0] - 1]["name"] == "groß"
    # Läufe: hin und zurück verlustfrei, auch am Zeilenrand und bei zwei
    # verschiedenen Gebieten direkt nebeneinander.
    g = bytearray(6 * 3 * 2)
    for hx, v in ((0, 1), (1, 1), (2, 2), (5, 3)):
        struct.pack_into("<H", g, (1 * 6 + hx) * 2, v)
    struct.pack_into("<H", g, (2 * 6 + 5) * 2, 4)
    rows = decode_runs(encode_runs(g, 6, 3), 3)
    assert rows == [[], [(0, 2, 1), (2, 1, 2), (5, 1, 3)], [(5, 1, 4)]], rows
    assert index_at(rows, 1, 1) == 1 and index_at(rows, 3, 1) == 0
    assert index_at(rows, 5, 2) == 4
    # Nachschlag wie in Dart: Mittelpunkt → eigene Wabe.
    for hy in (4, 5):
        for hx in (3, 8):
            u = hx + 0.5 + (0.5 if hy & 1 else 0.0)
            assert nearest_cell(u, hy + 2 / 3, w, h) == (hx, hy)
    west, north, lon_step, lat_step, width, height = lattice()
    assert (width, height) == (3038, 4470), (width, height)
    # Tirol (#623): warnen nur NSG, SSG und die Kernzone.
    ct = classify_tirol
    assert ct("NSG") == NATURE_RESERVE and ct("SSG") == NATURE_RESERVE
    assert ct("NPKZ") == CORE_ZONE
    for still in ("LSG", "RG", "GLT", "NPAZ", "", None, "XYZ"):
        assert ct(still) is None, still
    assert tirol_name("NSG", "Karwendel") == "Karwendel"
    assert tirol_name("SSG", "Silzer Innau") == "Sonderschutzgebiet Silzer Innau"
    assert tirol_name("NPKZ", "Hohe Tauern Kernzone") == \
        "Nationalpark Hohe Tauern Kernzone"
    _self_test_official_mask()
    # Verluste: Ein großes Gebiet, das (fast) verschwindet, fällt auf; ein
    # kleines oder eines, das nur schrumpft, nicht.
    big = LOSS_MIN_CELLS
    before = {("Nationalpark", "A"): big, ("Nationalpark", "B"): big,
              ("Naturschutzgebiet", "klein"): big - 1}
    after = {("Nationalpark", "B"): big * 0.6}
    assert losses(before, after) == [("Nationalpark", "A", big, 0)], \
        losses(before, after)
    print("protected_areas self-test passed (no network)")


def _self_test_official_mask():
    """Im Land mit amtlichen Daten schweigt OSM, daneben nicht — am
    echten Raster mit einem künstlichen „Tirol" um Innsbruck."""
    import tempfile
    lat_c = lattice()
    _, _, _, _, width, height = lat_c
    box = [[11.0, 47.0], [11.6, 47.0], [11.6, 47.4], [11.0, 47.4],
           [11.0, 47.0]]
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "tirol.boundary.geojsonseq"), "w") as fh:
            fh.write(json.dumps({"type": "Feature", "properties": {},
                                 "geometry": {"type": "Polygon",
                                              "coordinates": [box]}}) + "\n")
        assert not official_mask(d, lat_c, width, height), \
            "ohne amtliche Datei bleibt OSM überall"
        json.dump({"type": "FeatureCollection", "features": []},
                  open(os.path.join(d, "tirol.official.geojson"), "w"))
        mask = official_mask(d, lat_c, width, height)
        inside = nearest_cell(*to_uv(11.3, 47.2, lat_c), width, height)
        outside = nearest_cell(*to_uv(11.8, 47.2, lat_c), width, height)
        assert inside in mask and outside not in mask
        os.remove(os.path.join(d, "tirol.boundary.geojsonseq"))
        try:
            official_mask(d, lat_c, width, height)
        except SystemExit:
            pass
        else:
            raise AssertionError("amtliche Daten ohne Landesgrenze muss abbrechen")


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
    b.add_argument("--previous",
                   help="bisheriges Gitter; große Verluste brechen ab")
    b.add_argument("--allow-loss", action="store_true")
    fo = sub.add_parser("fetch-official")
    fo.add_argument("--out", required=True)
    lk = sub.add_parser("lookup")
    lk.add_argument("--assets", required=True)
    lk.add_argument("points", nargs="+", help="lat,lon")
    args = ap.parse_args()
    if args.self_test:
        self_test()
    elif args.cmd == "extract":
        extract(args.pbf, args.out)
    elif args.cmd == "fetch-official":
        fetch_official(args.out)
    elif args.cmd == "report":
        report(args.out)
    elif args.cmd == "build":
        build(args.out, args.assets, args.forest_manifest, args.previous,
              args.allow_loss)
    elif args.cmd == "lookup":
        lookup(args.assets, [tuple(map(float, p.split(","))) for p in args.points])
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
