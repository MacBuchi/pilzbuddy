"""Kommt aus der eigenen Instanz dasselbe wie aus der Cloud? (#460)

    python3 tool/openmeteo_local_check.py \
        "Herbsttrompete" "Craterellus cornucopioides" 2014,2016,2020,2022


Vergleicht Tag für Tag: die GESICHERTEN Reihen im Cache (Cloud-API,
Vorgabe „best match") gegen die lokale Instanz — einmal mit derselben
Vorgabe, einmal auf ERA5 festgenagelt.

Kostet KEIN Cloud-Kontingent: Der Cache hält die Cloud-Antworten schon.
"""
import importlib.util, json, os, random, statistics, sys, urllib.parse
import urllib.request

spec = importlib.util.spec_from_file_location("av", "tool/ampel_validate.py")
av = importlib.util.module_from_spec(spec)
spec.loader.exec_module(av)

CACHE = os.path.expanduser("~/pilzbuddy-ampel2000/ampel_cache")
LOKAL = "http://127.0.0.1:8080/v1/archive"
if len(sys.argv) < 4:
    raise SystemExit(
        'Aufruf: openmeteo_local_check.py "<Art>" "<wissenschaftlich>" '
        "<Jahre, kommagetrennt>\n"
        "Die Art muss im Cache liegen — verglichen werden GESICHERTE "
        "Cloud-Antworten gegen die eigene Instanz.")
ART, SCI = sys.argv[1], sys.argv[2]
JAHRE = [int(j) for j in sys.argv[3].split(",")]


def lokal(points, year, span, modell=None):
    """Dieselbe Anfrage wie fetch_weather, aber gegen die Instanz."""
    series = []
    for start in range(0, len(points), 100):
        chunk = points[start:start + 100]
        params = {
            "latitude": ",".join(f"{p[0]:.4f}" for p in chunk),
            "longitude": ",".join(f"{p[1]:.4f}" for p in chunk),
            "start_date": av._date_from_index(year, span[0]),
            "end_date": av._date_from_index(year, span[1]),
            "daily": "precipitation_sum,temperature_2m_mean",
            "timezone": "Europe/Berlin",
        }
        if modell:
            params["models"] = modell
        url = f"{LOKAL}?{urllib.parse.urlencode(params)}"
        with urllib.request.urlopen(url, timeout=1800) as r:
            answer = json.load(r)
        if isinstance(answer, dict):
            answer = [answer]
        for place in answer:
            series.append({"rain": place["daily"]["precipitation_sum"],
                           "temp": place["daily"]["temperature_2m_mean"],
                           "first": span[0]})
    return series


def abweichung(a, b, feld):
    """Größte und mittlere Abweichung über alle Orte und Tage."""
    diffs = []
    for pa, pb in zip(a, b):
        for x, y in zip(pa[feld], pb[feld]):
            if x is None or y is None:
                continue
            diffs.append(abs(x - y))
    if not diffs:
        return None
    return max(diffs), statistics.fmean(diffs), len(diffs)


finds = av.fetch_finds(SCI, cache_dir=CACHE, progress=False)
if len(finds) > av.SAMPLE_PER_SPECIES:
    finds = random.Random(42).sample(finds, av.SAMPLE_PER_SPECIES)
by_year = {}
for f in finds:
    by_year.setdefault(f["year"], []).append(f)

print(f"{ART} ({SCI}) — {len(finds)} Meldungen, "
      f"Jahre {min(by_year)}…{max(by_year)}")
for year in JAHRE:
    group = by_year.get(year)
    if not group:
        print(f"  {year}: keine Funde")
        continue
    points = [(f["lat"], f["lon"]) for f in group]
    span = av.season_span(
        [av.day_index(year, f["month"], f["day"]) for f in group], year=year)
    cached = av._cache_read(CACHE, year, points, span[0], span[1])
    if cached is None:
        print(f"  {year}: nicht im Cache ({len(points)} Orte)")
        continue
    for modell in (None, "era5"):
        hier = lokal(points, year, span, modell)
        t = abweichung(cached, hier, "temp")
        n = abweichung(cached, hier, "rain")
        label = modell or "DEFAULT"
        print(f"  {year} · {len(points):4} Orte · lokal {label:<8} "
              f"T max {t[0]:.2f} K Ø {t[1]:.3f} · "
              f"N max {n[0]:.2f} mm Ø {n[1]:.3f}  (n={t[2]})")
