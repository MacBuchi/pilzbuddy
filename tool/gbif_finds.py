#!/usr/bin/env python3
"""Gemeldete Fundorte (GBIF) als Asset für die Karte — Issue #467.

    python3 tool/gbif_finds.py build            # aus der lokalen Datenbank
    python3 tool/gbif_finds.py build --offline  # ohne Datensatz-Titel aus dem Netz
    python3 tool/gbif_finds.py --self-test      # ohne Netz, ohne Datenbank

Ergebnis: assets/gbif/gbif_finds.bin.gz + gbif_finds_manifest.json.
Die Deutung der Daten steht in docs/gbif-fundorte-messung.md.

WAS DAS ASSET SAGT — UND WAS NICHT. Eine Zeile ist ein ORT, an dem
eine unserer Arten gemeldet wurde, mit der Koordinaten-Unschärfe, die
der Melder selbst angegeben hat. Kein Fundort im Sinn eines Spots:
`kNearbySpotMeters` sind 20 m; die schärfste Klasse hier sind 250 m,
und die drei Länder melden GRUNDVERSCHIEDEN (gemessen 2026-09-21 an
unseren Arten): Deutschland fast nur scharfe Punkte (69 974 von
75 268 auf ≤ 250 m — naturgucker, iNaturalist, ArtenFinder), die
Schweiz fast nur 3535 m (116 316 — SwissFungi meldet Kilometerquadrate,
3535 m ist die halbe Diagonale von 5 km), Österreich fast nur OHNE
Angabe auf Rasterpunkten (96 044 Meldungen auf 8 565 Koordinaten —
die ÖMG). Die Karte zeichnet deshalb SCHEIBEN in der Größe der
Unschärfe, keine Marker. Eine Heatmap wäre bei 91–98 % leerer Fläche
eine Lüge (Messung im Issue); ein einzelner Kreis behauptet nur „hier
hat jemand gemeldet", und das stimmt.

DREI ENTSCHEIDUNGEN, DIE MAN KENNEN MUSS:

1. AUS DER LOKALEN DATENBANK, NIE ÜBER DIE API. CLAUDE.md: „Wer
   Hunderte Einzelabfragen hintereinander braucht, stellt die falsche
   Frage." Der Download trägt einen DOI, und der steht im Manifest —
   zwei Läufe auf demselben Stand ergeben dasselbe Asset. Fehlt die
   Datenbank, bricht der Bau ab und sagt, wie man sie holt.

2. GRUPPIERT, NICHT EINZELN. Auf einem österreichischen Rasterpunkt
   liegen im Schnitt elf Meldungen. Je (Art, Koordinate, Unschärfe)
   entsteht EINE Zeile mit Zähler und jüngstem Jahr — sonst malte die
   Karte elf deckungsgleiche Scheiben und das Asset trüge das
   Dreifache. Der Zähler ist bei 255 gedeckelt; mehr sagt ohnehin
   nur „viel".

3. KEINE MELDERNAMEN. `recordedBy` ist eine Person; das Asset liegt in
   jedem APK. Die Quell-DATENSÄTZE dagegen stehen drin (Schlüssel,
   Titel, Zahl) — das ist die CC-BY-Namensnennung, ohne die wir die
   Daten nicht ausliefern dürfen.

FORMAT (Spalten, alle little-endian, N Zeilen; `records` im Manifest):
  species  u8   Index in `species` des Manifests
  lat      u16  quantisiert: 0 = `north` … 65535 = `south`
  lon      u16  quantisiert: 0 = `west`  … 65535 = `east`
  unc      u16  Koordinaten-Unschärfe in Metern, 0 = unbekannt
  count    u8   Meldungen an diesem Ort (≤ 255)
  year     u8   jüngstes Jahr − 1900, 0 = unbekannt
Ein Quantisierungsschritt ist ~16 m in Breite und ~12 m in Länge — weit
unter der schärfsten Unschärfe (4 m gibt es, aber die Scheibe hat am
Bildschirm ohnehin eine Mindestgröße). Die Box ist die des Waldgitters,
damit ein Punkt außerhalb der Karte gar nicht erst ins Asset kommt.

Nur Standardbibliothek, wie alle Werkzeuge hier.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
import sqlite3
import struct
import sys
import urllib.request
from collections import defaultdict
from datetime import date

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(TOOL_DIR)
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)

import gbif_local  # noqa: E402
from season_curves import read_species  # noqa: E402

OUT_DIR = os.path.join(REPO_ROOT, "assets", "gbif")
BIN_NAME = "gbif_finds.bin.gz"
MANIFEST_NAME = "gbif_finds_manifest.json"

# Dieselbe Box wie das Waldgitter (assets/forest/forest_manifest.json):
# Was die Karte nicht zeigt, braucht das Asset nicht zu tragen.
BOX = dict(west=5.8, east=17.3, north=55.1, south=45.7)

# Über 10 km sagt eine Scheibe nichts mehr über einen Ort. Der
# Quadrant (3535 m) liegt deutlich darunter und bleibt drin.
MAX_UNCERTAINTY_M = 10_000

# Wie die App eine UNBEKANNTE Unschärfe zeichnet: wie die Schweizer
# Quadrate. Die meisten Meldungen ohne Angabe sind österreichische
# Rasterpunkte (11 je Koordinate), und die harmlose Fehlerrichtung ist
# die größere Scheibe — ein scharfer Punkt, der keiner ist, wäre die
# Behauptung einer Fundstelle.
UNKNOWN_DRAWN_AS_M = 3535

# Titel der Quell-Datensätze — ein Aufruf je Datensatz, gecacht. Das
# ist der EINZIGE Netzzugriff dieses Werkzeugs und dient allein der
# Namensnennung.
DATASET_API = os.environ.get("GBIF_API", "https://api.gbif.org/v1") + "/dataset/"
TITLE_CACHE = os.path.expanduser(
    os.environ.get("GBIF_TITLE_CACHE", "~/pilzbuddy-gbif/dataset_titles.json"))

COLUMNS = (("species", "B"), ("lat", "H"), ("lon", "H"),
           ("unc", "H"), ("count", "B"), ("year", "B"))


# ---------------------------------------------------------------- Daten

def quantize(value, low, high):
    """0 … 65535 zwischen [low] und [high]; None außerhalb."""
    if value < min(low, high) or value > max(low, high):
        return None
    return round((value - low) / (high - low) * 65535)


def collect(con, species, box=BOX, max_uncertainty=MAX_UNCERTAINTY_M):
    """Gruppierte Fundorte je Art aus der Datenbank.

    Arten vor Gattungen: Eine Meldung von `Leccinum scabrum` gehört dem
    Birkenpilz, nicht der „Rotkappe" (Gattungseintrag `Leccinum`) —
    der Gattungseintrag sammelt nur, was keine eigene Zeile hat.
    """
    by_species = {s["sci"]: i for i, s in enumerate(species)
                  if " " in s["sci"]}
    by_genus = {s["sci"]: i for i, s in enumerate(species)
                if " " not in s["sci"]}
    groups = defaultdict(lambda: [0, 0])  # (idx, latq, lonq, unc) -> [n, year]
    stats = dict(records=0, outside_box=0, too_coarse=0, unknown=0,
                 countries=defaultdict(int), datasets=defaultdict(int),
                 per_species=[0] * len(species))
    rows = con.execute(
        "SELECT species, genus, decimalLatitude, decimalLongitude, "
        "coordinateUncertaintyInMeters, year, countryCode, datasetKey "
        f"FROM occ WHERE {gbif_local.WHERE_USABLE} "
        "AND decimalLatitude IS NOT NULL AND decimalLongitude IS NOT NULL")
    for sci, genus, lat, lon, unc, year, country, dataset in rows:
        idx = by_species.get(sci)
        if idx is None:
            idx = by_genus.get(genus)
        if idx is None:
            continue
        if unc is not None and unc > max_uncertainty:
            stats["too_coarse"] += 1
            continue
        latq = quantize(lat, box["north"], box["south"])
        lonq = quantize(lon, box["west"], box["east"])
        if latq is None or lonq is None:
            stats["outside_box"] += 1
            continue
        unc_m = 0 if unc is None else min(65535, int(round(unc)))
        if unc is None:
            stats["unknown"] += 1
        entry = groups[(idx, latq, lonq, unc_m)]
        entry[0] += 1
        if year and year > entry[1]:
            entry[1] = year
        stats["records"] += 1
        stats["countries"][country or "?"] += 1
        stats["datasets"][dataset or "?"] += 1
        stats["per_species"][idx] += 1
    return groups, stats


def encode(groups):
    """Spaltenweise packen, sortiert nach Art, Breite, Länge — die
    Sortierung ist Teil des Formats nur insofern, als sie gzip hilft:
    benachbarte Zeilen ähneln sich."""
    keys = sorted(groups)
    cols = {name: [] for name, _ in COLUMNS}
    for idx, latq, lonq, unc in keys:
        n, year = groups[(idx, latq, lonq, unc)]
        cols["species"].append(idx)
        cols["lat"].append(latq)
        cols["lon"].append(lonq)
        cols["unc"].append(unc)
        cols["count"].append(min(255, n))
        cols["year"].append(max(0, min(255, year - 1900)) if year else 0)
    raw = b"".join(struct.pack(f"<{len(cols[name])}{fmt}", *cols[name])
                   for name, fmt in COLUMNS)
    # mtime 0: Der gzip-Header trägt sonst die Bauzeit, und zwei Läufe
    # desselben Stands hätten verschiedene Prüfsummen.
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0, compresslevel=9) as z:
        z.write(raw)
    return buf.getvalue(), len(keys)


def decode(payload, records):
    """Die Umkehrung — für Selbsttest und Nachprüfung."""
    raw = gzip.decompress(payload)
    out = {}
    offset = 0
    for name, fmt in COLUMNS:
        size = struct.calcsize(fmt) * records
        out[name] = list(struct.unpack(f"<{records}{fmt}", raw[offset:offset + size]))
        offset += size
    if offset != len(raw):
        raise ValueError(f"{len(raw)} Bytes, erwartet {offset}")
    return out


# ------------------------------------------------------------- Titel

def dataset_titles(keys, offline=False, cache_path=TITLE_CACHE, fetch=None):
    """Titel je Datensatz-Schlüssel, aus dem Cache oder von GBIF."""
    titles = {}
    if os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as handle:
            titles = json.load(handle)
    missing = [k for k in keys if k not in titles and k != "?"]
    if missing and not offline:
        fetch = fetch or _fetch_title
        for key in missing:
            title = fetch(key)
            if title:
                titles[key] = title
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(cache_path, "w", encoding="utf-8") as handle:
            json.dump(titles, handle, ensure_ascii=False, indent=1,
                      sort_keys=True)
    return {k: titles.get(k, k) for k in keys}


def _fetch_title(key):
    try:
        with urllib.request.urlopen(DATASET_API + key, timeout=30) as resp:
            return json.load(resp).get("title")
    except Exception as error:  # noqa: BLE001 — Titel sind Zugabe
        print(f"  Titel für {key} nicht geholt: {error}", file=sys.stderr)
        return None


# ------------------------------------------------------------- build

def read_citation(db_path):
    """DOI und Datum aus CITATION.txt neben der Datenbank."""
    path = os.path.join(os.path.dirname(db_path), "CITATION.txt")
    doi, fetched = None, None
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            if "10." in line and "/" in line:
                doi = line.split()[-1]
            if "abgerufen am" in line:
                fetched = line.split()[-1]
    return doi, fetched


def build(con, species, out_dir, titles, doi=None, fetched=None,
          today=None):
    groups, stats = collect(con, species)
    payload, records = encode(groups)
    os.makedirs(out_dir, exist_ok=True)
    bin_path = os.path.join(out_dir, BIN_NAME)
    with open(bin_path, "wb") as handle:
        handle.write(payload)
    datasets = sorted(stats["datasets"].items(), key=lambda kv: -kv[1])
    manifest = {
        "source": "GBIF Occurrence Download",
        "doi": doi,
        "fetched_on": fetched,
        "built_on": (today or date.today()).isoformat(),
        "encoding": "gzip-columns",
        "columns": [name for name, _ in COLUMNS],
        "records": records,
        "observations": stats["records"],
        **BOX,
        "max_uncertainty_m": MAX_UNCERTAINTY_M,
        "unknown_uncertainty_drawn_as_m": UNKNOWN_DRAWN_AS_M,
        "filters": {
            "basisOfRecord": "HUMAN_OBSERVATION",
            "license": ["CC0_1_0", "CC_BY_4_0"],
            "dropped_outside_box": stats["outside_box"],
            "dropped_too_coarse": stats["too_coarse"],
            "without_uncertainty": stats["unknown"],
        },
        "countries": dict(sorted(stats["countries"].items())),
        "species": [
            {"name": s["name"], "sci": s["sci"], "observations": n}
            for s, n in zip(species, stats["per_species"])
        ],
        "datasets": [
            {"key": key, "title": titles.get(key, key), "observations": n}
            for key, n in datasets
        ],
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
    }
    with open(os.path.join(out_dir, MANIFEST_NAME), "w",
              encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=1)
        handle.write("\n")
    return manifest


# ---------------------------------------------------------- Selbsttest

def self_test():
    import tempfile
    tmp = tempfile.mkdtemp()
    db = os.path.join(tmp, "t.sqlite")
    con = sqlite3.connect(db)
    con.execute(
        "CREATE TABLE occ (gbifID INTEGER PRIMARY KEY, datasetKey TEXT, "
        "species TEXT, genus TEXT, decimalLatitude REAL, "
        "decimalLongitude REAL, coordinateUncertaintyInMeters REAL, "
        "year INTEGER, basisOfRecord TEXT, license TEXT, "
        "countryCode TEXT, recordedBy TEXT)")
    H, C0, CBY = "HUMAN_OBSERVATION", "CC0_1_0", "CC_BY_4_0"
    rows = [
        # drei Steinpilze auf demselben Rasterpunkt -> EINE Zeile, 3x, 2023
        (1, "d1", "Boletus edulis", "Boletus", 51.0, 10.0, 3535, 2021, H, C0, "DE", "A"),
        (2, "d1", "Boletus edulis", "Boletus", 51.0, 10.0, 3535, 2023, H, CBY, "DE", "B"),
        (3, "d1", "Boletus edulis", "Boletus", 51.0, 10.0, 3535, None, H, C0, "DE", "A"),
        # scharf, eigene Zeile
        (4, "d2", "Boletus edulis", "Boletus", 51.0, 10.0, 25, 2024, H, C0, "DE", "A"),
        # Gattungseintrag: Leccinum ohne eigene Art -> Rotkappe;
        # Leccinum scabrum -> Birkenpilz, NICHT Rotkappe
        (5, "d2", "Leccinum holopus", "Leccinum", 48.0, 12.0, None, 2020, H, C0, "AT", "A"),
        (6, "d2", "Leccinum scabrum", "Leccinum", 48.0, 12.0, 100, 2020, H, C0, "AT", "A"),
        # zu grob -> raus
        (7, "d2", "Boletus edulis", "Boletus", 50.0, 9.0, 20000, 2020, H, C0, "DE", "A"),
        # außerhalb der Box -> raus
        (8, "d2", "Boletus edulis", "Boletus", 40.0, 9.0, 10, 2020, H, C0, "IT", "A"),
        # NC-Lizenz und Bodenprobe -> raus
        (9, "d3", "Boletus edulis", "Boletus", 50.0, 9.0, 10, 2020, H, "CC_BY_NC_4_0", "DE", "A"),
        (10, "d3", "Boletus edulis", "Boletus", 50.0, 9.0, 10, 2020, "MATERIAL_SAMPLE", C0, "DE", "A"),
        # fremde Art -> raus
        (11, "d3", "Amanita phalloides", "Amanita", 50.0, 9.0, 10, 2020, H, C0, "DE", "A"),
    ]
    con.executemany("INSERT INTO occ VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", rows)
    con.commit()

    species = [
        {"name": "Steinpilz", "sci": "Boletus edulis"},
        {"name": "Birkenpilz", "sci": "Leccinum scabrum"},
        {"name": "Rotkappe", "sci": "Leccinum"},
    ]
    out = os.path.join(tmp, "assets")
    manifest = build(con, species, out, titles={"d1": "Erster"},
                     doi="10.0/test", fetched="2026-09-16",
                     today=date(2026, 9, 21))
    assert manifest["records"] == 4, manifest["records"]
    assert manifest["observations"] == 6, manifest["observations"]
    assert manifest["filters"]["dropped_too_coarse"] == 1
    assert manifest["filters"]["dropped_outside_box"] == 1
    assert manifest["filters"]["without_uncertainty"] == 1
    assert manifest["countries"] == {"AT": 2, "DE": 4}, manifest["countries"]
    assert [s["observations"] for s in manifest["species"]] == [4, 1, 1]
    assert manifest["datasets"][0] == {"key": "d1", "title": "Erster",
                                       "observations": 3}
    assert manifest["datasets"][1]["title"] == "d2", "ohne Titel: Schlüssel"

    payload = open(os.path.join(out, BIN_NAME), "rb").read()
    assert hashlib.sha256(payload).hexdigest() == manifest["sha256"]
    assert len(payload) == manifest["bytes"]
    assert payload[4:8] == b"\x00\x00\x00\x00", "gzip-Header trägt eine Bauzeit"
    cols = decode(payload, manifest["records"])
    # sortiert nach Art: Steinpilz (0) x2, Birkenpilz (1), Rotkappe (2)
    assert cols["species"] == [0, 0, 1, 2], cols["species"]
    # Innerhalb des Steinpilzes: gleiche Koordinate, Unschärfe 25 vor 3535.
    assert cols["unc"][:2] == [25, 3535], cols["unc"]
    assert cols["count"][:2] == [1, 3], cols["count"]
    assert cols["year"][:2] == [124, 123], cols["year"]      # 2024, 2023
    assert cols["unc"][3] == 0 and cols["year"][3] == 120     # unbekannt, 2020
    # Quantisierung: 51,0° liegt bei (55,1-51,0)/9,4 der Breite.
    assert abs(cols["lat"][0] / 65535 - (55.1 - 51.0) / 9.4) < 1e-4
    assert abs(cols["lon"][0] / 65535 - (10.0 - 5.8) / 11.5) < 1e-4
    # Und kein Meldername im Asset — auch nicht im Manifest.
    blob = open(os.path.join(out, MANIFEST_NAME), encoding="utf-8").read()
    assert "recordedBy" not in blob and '"A"' not in blob

    try:
        decode(payload, 3)
        raise AssertionError("falsche Zeilenzahl nicht erkannt")
    except ValueError:
        pass

    # Titel-Cache: offline bleibt der Schlüssel, kein Netz.
    cache = os.path.join(tmp, "titles.json")
    got = dataset_titles(["x"], offline=True, cache_path=cache)
    assert got == {"x": "x"}
    got = dataset_titles(["x"], cache_path=cache, fetch=lambda k: "Titel X")
    assert got == {"x": "Titel X"}
    got = dataset_titles(["x"], offline=True, cache_path=cache)
    assert got == {"x": "Titel X"}, "Cache nicht gelesen"
    print("gbif_finds: Selbsttest bestanden")


# --------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="cmd")
    p_build = sub.add_parser("build", help="Asset aus der lokalen Datenbank")
    p_build.add_argument("--offline", action="store_true",
                         help="keine Datensatz-Titel von GBIF holen")
    p_build.add_argument("--out", default=OUT_DIR)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.cmd != "build":
        parser.print_help()
        return
    con = gbif_local.connect()
    if con is None:
        raise SystemExit(
            f"Keine lokale GBIF-Datenbank unter {gbif_local.DB_PATH}. "
            f"Holen: python3 tool/gbif_download.py request → status → "
            f"fetch → build (CLAUDE.md, Abschnitt Externe Datenquellen).")
    species = read_species()
    doi, fetched = read_citation(gbif_local.DB_PATH)
    groups, stats = collect(con, species)
    titles = dataset_titles(sorted(stats["datasets"]), offline=args.offline)
    manifest = build(con, species, args.out, titles, doi=doi, fetched=fetched)
    print(f"{manifest['records']} Orte aus {manifest['observations']} "
          f"Meldungen, {manifest['bytes']} Bytes, DOI {doi}")
    print("Länder:", manifest["countries"])
    print("Datensätze:", len(manifest["datasets"]),
          "· ohne Unschärfe:", manifest["filters"]["without_uncertainty"],
          "· zu grob:", manifest["filters"]["dropped_too_coarse"])
    print("Danach: python3 tool/generated_assets.py --update")


if __name__ == "__main__":
    main()
