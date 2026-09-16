#!/usr/bin/env python3
"""Trägt eine Heatmap der GBIF-Fundorte? (Vormessung zu #467)

    python3 tool/gbif_effort.py harz          # laden und auswerten
    python3 tool/gbif_effort.py obb
    python3 tool/gbif_effort.py --self-test   # ohne Netz

Ergebnis und Deutung: docs/gbif-fundorte-messung.md

DIE FRAGE. Eine rohe Fundort-Heatmap zeigt, WO GEMELDET WIRD — nicht,
wo Pilze stehen. Das ist dieselbe Falle, die tool/season_curves.py
zeitlich löst („DIE EFFORT-KORREKTUR IST DER GANZE PUNKT"), nur
räumlich. Geprüft wird dreierlei: ob die Rohkarte wirklich die
Meldedichte misst, ob nach der Korrektur Struktur übrig bleibt, und ob
diese Struktur der Wald ist oder die Vorliebe einzelner Melder.

ZWEI FALLEN, BEIDE STILL:

1. GBIF LÄUFT AUF ELASTICSEARCH, und dessen `max_result_window` steht
   auf 10 000. Ab `offset` 10 000 kommt KEIN Fehler — die Anfrage hängt
   einfach, minutenlang, ohne offene Verbindung. Gemessen am
   2026-09-16: Der Lauf blieb zweimal bei exakt 10 200 stehen, mit und
   ohne WKT-`geometry`. Deshalb kachelt [_collect] die Region rekursiv,
   bis jede Kachel unter die Grenze passt, statt tief zu blättern.

2. DIE MELDER DOMINIEREN. In der typischen 5-km-Zelle stammen 69 % der
   Meldungen von EINER Person. Wer den Anteil je Zelle roh zählt, misst
   zur Hälfte deren Vorliebe. [fair_share] gibt deshalb jedem Melder
   mit genug Meldungen eine Stimme, statt Meldungen zu zählen.

Der Download wird FESTGENAGELT — gleiche Begründung wie `fetch_finds`
in tool/ampel_validate.py: GBIF wächst täglich, zwei Läufe wären sonst
nicht vergleichbar. Neu ziehen heißt: die Datei löschen.

Nur Standardbibliothek, wie tool/rain_grid.py und tool/season_curves.py.
"""
import argparse
import json
import math
import os
import re
import statistics
import sys
import time
import urllib.parse
import urllib.request

GBIF = os.environ.get("GBIF_API", "https://api.gbif.org/v1")
CACHE = os.path.expanduser(os.environ.get("GBIF_EFFORT_CACHE",
                                          "~/pilzbuddy-gbif-effort"))
ES_WINDOW = 9000                      # unter Elasticsearchs 10 000 bleiben
MIN_RECORDS = 30                      # weniger ist je Zelle Rauschen
MIN_PER_RECORDER = 5                  # ab hier zählt ein Melder als Stimme
MIN_RECORDERS = 3                     # so viele Stimmen braucht eine Zelle

REGIONS = {
    "harz": dict(name="Harz/Suedniedersachsen",
                 lat=(51.5, 52.2), lon=(9.8, 11.0)),
    "obb": dict(name="Oberbayern/Alpenvorland",
                lat=(47.6, 48.5), lon=(11.0, 12.3)),
}


# --------------------------------------------------------------- Netz

def _get(path, params, tries=5):
    url = f"{GBIF}/{path}?" + urllib.parse.urlencode(params, doseq=True)
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=45) as handle:
                return json.load(handle)
        except Exception as exc:
            if attempt == tries - 1:
                raise
            print(f"    {exc} — warte {2 ** attempt}s", file=sys.stderr)
            time.sleep(2 ** attempt)


def _page(box, offset):
    la1, la2, lo1, lo2 = box
    return _get("occurrence/search", {
        "kingdomKey": 5,
        "decimalLatitude": f"{la1},{la2}",
        "decimalLongitude": f"{lo1},{lo2}",
        "hasCoordinate": "true", "hasGeospatialIssue": "false",
        "basisOfRecord": "HUMAN_OBSERVATION",
        "license": ["CC0_1_0", "CC_BY_4_0"],
        "limit": 300, "offset": offset,
    })


def _collect(box, rows, depth=0):
    """Vierteilt die Kachel, solange sie über ES_WINDOW liegt."""
    total = _page(box, 0).get("count", 0)
    if total > ES_WINDOW and depth < 6:
        la1, la2, lo1, lo2 = box
        mlat, mlon = (la1 + la2) / 2, (lo1 + lo2) / 2
        for sub in ((la1, mlat, lo1, mlon), (la1, mlat, mlon, lo2),
                    (mlat, la2, lo1, mlon), (mlat, la2, mlon, lo2)):
            _collect(sub, rows, depth + 1)
        return
    offset = 0
    while offset < min(total, ES_WINDOW):
        page = _page(box, offset)
        got = page.get("results", [])
        if not got:
            break
        for record in got:
            lat = record.get("decimalLatitude")
            lon = record.get("decimalLongitude")
            if lat is None or lon is None:
                continue
            rows.append({
                "lat": lat, "lon": lon,
                "sci": record.get("species"), "genus": record.get("genus"),
                "month": record.get("month"), "year": record.get("year"),
                "by": record.get("recordedBy"),
            })
        offset += 300
        if page.get("endOfRecords"):
            break
        time.sleep(0.25)
    print(f"    {len(rows):,} gesamt (Kachel {box[0]:.2f}–{box[1]:.2f} / "
          f"{box[2]:.2f}–{box[3]:.2f}: {total:,})", file=sys.stderr)


def fetch_region(region):
    os.makedirs(CACHE, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9]+", "_", region["name"])
    path = os.path.join(CACHE, f"fungi_{safe}.json")
    if os.path.exists(path):
        rows = json.load(open(path, encoding="utf-8"))
        # Ein Bestand ohne `recordedBy` ist NICHT halb brauchbar: Ohne
        # ihn fallen alle Melder auf "?" zusammen, die Dominanz steht bei
        # 1,00 und die Abdeckung bei 0 % — plausible Zahlen, die nichts
        # messen. Genau so einmal passiert (2026-09-16), deshalb hier ein
        # Abbruch statt einer Warnung.
        if rows and not any(r.get("by") for r in rows):
            raise SystemExit(
                f"{path} stammt aus einem Lauf ohne recordedBy — löschen "
                f"und neu ziehen, sonst misst die Melder-Gegenprobe nichts.")
        print(f"{len(rows):,} Meldungen (festgenagelt)", file=sys.stderr)
        return rows
    rows = []
    _collect((region["lat"][0], region["lat"][1],
              region["lon"][0], region["lon"][1]), rows)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(rows, handle)
    return rows


# ---------------------------------------------------------- Auswertung

def load_targets(repo_root="."):
    """Die 91 Arten mit wissenschaftlichem Namen aus der Artenliste."""
    src = open(os.path.join(repo_root, "lib/core/mushroom_species.dart"),
               encoding="utf-8").read()
    names = set(re.findall(r"sci:\s*'([^']+)'", src))
    return names, {n for n in names if " " not in n}


def cells_of(rows, km, targets, genera):
    """Zelle -> Melder -> [Zielarten, gesamt]."""
    out = {}
    for row in rows:
        dlat = km / 111.32
        dlon = km / (111.32 * math.cos(math.radians(row["lat"])))
        key = (int(row["lat"] / dlat), int(row["lon"] / dlon))
        by = (row.get("by") or "?").strip().lower()
        slot = out.setdefault(key, {}).setdefault(by, [0, 0])
        slot[1] += 1
        if ((row.get("sci") and row["sci"] in targets)
                or (row.get("genus") and row["genus"] in genera)):
            slot[0] += 1
    return out


def totals(cell):
    return sum(v[0] for v in cell.values()), sum(v[1] for v in cell.values())


def fair_share(cell):
    """Anteil, bei dem jeder Melder EINE Stimme hat statt vieler.

    Ohne das misst der Zellwert zur Hälfte, wen man dort erwischt hat:
    Median 69 % der Meldungen einer Zelle stammen von einer Person.
    """
    votes = [v[0] / v[1] for v in cell.values() if v[1] >= MIN_PER_RECORDER]
    if len(votes) < MIN_RECORDERS:
        return None
    return sum(votes) / len(votes)


def spearman(xs, ys):
    def rank(vals):
        order = sorted(range(len(vals)), key=lambda i: vals[i])
        out = [0.0] * len(vals)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and vals[order[j + 1]] == vals[order[i]]:
                j += 1
            for k in range(i, j + 1):
                out[order[k]] = (i + j) / 2 + 1
            i = j + 1
        return out
    rx, ry = rank(xs), rank(ys)
    n = len(xs)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = math.sqrt(sum((a - mx) ** 2 for a in rx)
                    * sum((b - my) ** 2 for b in ry))
    return num / den if den else 0.0


def chi2_over_df(cells):
    """> 1 heißt: mehr Streuung als reines Stichprobenrauschen."""
    hit = sum(totals(c)[0] for c in cells)
    tot = sum(totals(c)[1] for c in cells)
    if not tot or len(cells) < 2:
        return 0.0
    p = hit / tot
    if p in (0.0, 1.0):
        return 0.0
    chi2 = sum((totals(c)[0] - totals(c)[1] * p) ** 2
               / (totals(c)[1] * p * (1 - p)) for c in cells)
    return chi2 / (len(cells) - 1)


def report(region, rows, targets, genera):
    print(f"\n=== {region['name']} — {len(rows):,} Fungi-Sichtungen ===")
    grid = cells_of(rows, 5.0, targets, genera)
    dense = [c for c in grid.values() if totals(c)[1] >= MIN_RECORDS]
    raw = [totals(c)[0] for c in dense]
    eff = [totals(c)[1] for c in dense]
    cor = [totals(c)[0] / totals(c)[1] for c in dense]
    print(f"\n1) Was misst die rohe Heatmap? ({len(dense)} Zellen a 5 km)")
    print(f"   Spearman(roh, Meldedichte)        = "
          f"{spearman(raw, eff):+.2f}")
    print(f"   Spearman(korrigiert, Meldedichte) = "
          f"{spearman(cor, eff):+.2f}")
    print(f"\n2) Bleibt Struktur? chi^2/df = {chi2_over_df(dense):.1f} "
          f"(1.0 = Rauschen)")
    doms = [max(v[1] for v in c.values()) / totals(c)[1] for c in dense]
    print(f"\n3) Melder-Dominanz: Median {statistics.median(doms):.2f} "
          f"der Meldungen einer Zelle von EINER Person")
    # Wie viel der Spannweite bleibt, wenn kein Melder eine Zelle traegt?
    grid10 = cells_of(rows, 10.0, targets, genera)
    both = [(totals(c)[0] / totals(c)[1], fair_share(c))
            for c in grid10.values()
            if totals(c)[1] >= MIN_RECORDS and fair_share(c) is not None]
    if len(both) >= 5:
        for label, idx in (("ungewichtet", 0), ("melder-gemittelt", 1)):
            vals = sorted(v[idx] for v in both)
            lo = vals[int(0.1 * len(vals))]
            hi = vals[int(0.9 * len(vals))]
            print(f"   Anteil 10.–90. Perzentil, {label:<16} "
                  f"{lo:.2f} … {hi:.2f}  (Faktor {hi / lo:.1f}x)"
                  if lo else "")
    print(f"\n4) Abdeckung — Fläche mit belastbarer Aussage")
    la, lo = region["lat"], region["lon"]
    for km in (2.5, 5.0, 10.0, 20.0):
        dlat = km / 111.32
        dlon = km / (111.32 * math.cos(math.radians(sum(la) / 2)))
        possible = math.ceil((la[1] - la[0]) / dlat) * \
            math.ceil((lo[1] - lo[0]) / dlon)
        g = cells_of(rows, km, targets, genera)
        ok = sum(1 for c in g.values()
                 if totals(c)[1] >= MIN_RECORDS and fair_share(c) is not None)
        print(f"   {km:>5g} km: {ok:>3} von {possible:>4} Zellen "
              f"= {ok / possible:>4.0%}")


# ------------------------------------------------------------ Selbsttest

def self_test():
    rows = []
    # Zelle A: viel gemeldet, durchschnittlicher Anteil, EIN Melder.
    for i in range(60):
        rows.append({"lat": 51.60, "lon": 10.10, "by": "a",
                     "sci": "Boletus edulis" if i % 5 == 0 else "Trametes x",
                     "genus": None, "month": 9, "year": 2024})
    # Zelle B: wenig gemeldet, hoher Anteil, drei Melder.
    for i in range(45):
        rows.append({"lat": 51.90, "lon": 10.60, "by": f"b{i % 3}",
                     "sci": "Boletus edulis" if i % 2 == 0 else "Trametes x",
                     "genus": None, "month": 9, "year": 2024})
    targets, genera = {"Boletus edulis"}, set()
    grid = cells_of(rows, 5.0, targets, genera)
    assert len(grid) == 2, grid
    cells = list(grid.values())
    a = next(c for c in cells if totals(c)[1] == 60)
    b = next(c for c in cells if totals(c)[1] == 45)
    assert fair_share(a) is None, "ein Melder darf keine Zelle tragen"
    assert fair_share(b) is not None, "drei Melder sind eine Aussage"
    assert abs(fair_share(b) - 0.5) < 0.06, fair_share(b)
    assert chi2_over_df([a, b]) > 1.0, "zwei verschiedene Anteile = Struktur"
    same = [a, a]
    assert chi2_over_df(same) < 1.0, "identische Zellen = kein Signal"
    assert spearman([1, 2, 3], [1, 2, 3]) == 1.0
    assert spearman([1, 2, 3], [3, 2, 1]) == -1.0
    print("Selbsttest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("region", nargs="?", default="harz", choices=list(REGIONS))
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--repo-root", default=".")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return
    targets, genera = load_targets(args.repo_root)
    region = REGIONS[args.region]
    report(region, fetch_region(region), targets, genera)


if __name__ == "__main__":
    main()
