"""Welchen Datensatz nageln wir fest? — Phase 0.1 des Fahrplans

    python3 tool/openmeteo_variables.py --self-test     # netzfrei
    python3 tool/openmeteo_variables.py --local         # nur eigene Instanz
    python3 tool/openmeteo_variables.py --cloud         # + oeffentlicher Dienst

`docs/pilzampel-openmeteo-lokal.md` hat gezeigt, dass unsere Messungen
gar keinen Datensatz pinnen: Die Vorgabe „best match" nimmt bis 2016
ERA5-Land-Temperatur mit ERA5-Niederschlag und ab 2017 IFS HRES. Die
Trennlinie jedes Hold-outs liegt bei 2018/2019 — angepasst wird also
ueberwiegend auf einem Instrument und geprueft auf einem anderen.

Dieses Werkzeug beantwortet die drei Fragen, die vor dem Pinnen zu
klaeren sind, und zwar je Variable, Modell, Jahreszeit und Land:

1. **Liefert die eigene Instanz die Variable ueberhaupt?**
2. **Liefert sie dasselbe wie der oeffentliche Dienst?** Das ist die
   Zusage, auf der `--api` ueberhaupt beruht; sie gilt nur, solange sie
   gemessen ist, und sie ist bisher nur fuer die VORGABE gemessen.
3. **Wie weit weicht der gepinnte Datensatz von der bisherigen Vorgabe
   ab?** Das ist kein Tor, sondern die Zahl, an der sich spaeter ein
   verschobener Referenzlauf erklaeren laesst.

**Getrennt nach Winter und AT/CH**, weil genau dort der Instrumentwechsel
am ehesten durchschlaegt: Tiefstwerte, Frost und Gebirge sind die Faelle,
in denen ein 25-km-Raster und ein 9-km-Raster auseinanderlaufen.

Nur Standardbibliothek, wie jedes Werkzeug in `tool/`.
"""
import argparse
import json
import statistics
import sys
import urllib.parse
import urllib.request

LOCAL_API = "http://127.0.0.1:8080/v1/archive"
CLOUD_API = "https://archive-api.open-meteo.com/v1/archive"

# Die Kandidaten aus dem Fahrplan. `snow_depth` ist stuendlich; als
# Tageswert heisst sie `snow_depth_max`.
DAILY_VARS = ["temperature_2m_mean", "temperature_2m_min",
              "precipitation_sum", "snow_depth_max"]
HOURLY_VARS = ["soil_moisture_7_to_28cm", "soil_temperature_0_to_7cm"]

MODELS = [None, "era5", "era5_land"]     # None = die bisherige Vorgabe

# Orte: je Land Tiefland und Gebirge, damit die Hoehenabhaengigkeit
# sichtbar wird und nicht in einem Mittelwert verschwindet.
POINTS = [
    ("DE", "Lueneburger Heide", 53.15, 10.05),
    ("DE", "Thueringer Wald", 50.65, 10.75),
    ("DE", "Schwarzwald", 48.05, 8.20),
    ("DE", "Bayerischer Wald", 48.95, 13.40),
    ("AT", "Muehlviertel", 48.50, 14.20),
    ("AT", "Tirol Inntal", 47.30, 11.40),
    ("AT", "Hohe Tauern", 47.10, 12.70),
    ("CH", "Mittelland", 47.10, 7.60),
    ("CH", "Berner Oberland", 46.60, 7.95),
    ("CH", "Graubuenden", 46.60, 9.80),
]

# Zwei Fenster je Jahreszeit, eines vor und eines nach dem Wechsel der
# Vorgabe 2017. Ohne das Paar waere „Abweichung zur Vorgabe" eine Zahl
# ohne Bezug — sie MUSS vor 2017 anders ausfallen als danach.
WINDOWS = [
    ("Herbst", 2015, "2015-09-15", "2015-10-15"),
    ("Herbst", 2020, "2020-09-15", "2020-10-15"),
    ("Winter", 2015, "2015-01-01", "2015-01-31"),
    ("Winter", 2020, "2020-01-01", "2020-01-31"),
]


def fetch(api, points, start, end, daily=(), hourly=(), model=None,
          timeout=1800):
    """Eine Anfrage fuer alle Orte; Rueckgabe je Ort ein dict von Reihen.

    Die API antwortet bei EINER Koordinate mit einem Objekt und bei
    mehreren mit einer Liste — beides wird hier zur Liste.
    """
    params = {
        "latitude": ",".join(f"{p[2]:.4f}" for p in points),
        "longitude": ",".join(f"{p[3]:.4f}" for p in points),
        "start_date": start,
        "end_date": end,
        "timezone": "Europe/Berlin",
    }
    if daily:
        params["daily"] = ",".join(daily)
    if hourly:
        params["hourly"] = ",".join(hourly)
    if model:
        params["models"] = model
    url = f"{api}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=timeout) as response:
        answer = json.load(response)
    if isinstance(answer, dict):
        answer = [answer]
    out = []
    for place in answer:
        series = {"elevation": place.get("elevation")}
        for name in daily:
            series[name] = place.get("daily", {}).get(name)
        for name in hourly:
            series[name] = daily_mean(
                place.get("hourly", {}).get("time"),
                place.get("hourly", {}).get(name))
        out.append(series)
    return out


def daily_mean(times, values):
    """Stuendliche Werte zu Tagesmitteln, gruppiert nach dem Datum.

    Gruppiert wird ueber den Datumsteil der ZURUECKGEGEBENEN Zeitangabe,
    nicht ueber die Position: Bei `timezone=Europe/Berlin` liefert die
    API Ortszeit, und die Zeitumstellung macht aus einem Tag 23 bzw. 25
    Stunden. Wer durch 24 teilt, verschiebt danach jeden Tag.
    """
    if times is None or values is None:
        return None
    buckets = {}
    order = []
    for stamp, value in zip(times, values):
        day = stamp[:10]
        if day not in buckets:
            buckets[day] = []
            order.append(day)
        if value is not None:
            buckets[day].append(value)
    return [statistics.fmean(buckets[d]) if buckets[d] else None
            for d in order]


def deviation(left, right):
    """Groesste und mittlere Abweichung zweier Reihenpaare.

    `None` heisst: nichts Vergleichbares da. Das ist ausdruecklich NICHT
    dasselbe wie 0,0 — eine fehlende Variable darf nicht als perfekte
    Uebereinstimmung durchgehen.
    """
    diffs = []
    for a, b in zip(left, right):
        if a is None or b is None:
            continue
        for x, y in zip(a, b):
            if x is None or y is None:
                continue
            diffs.append(abs(x - y))
    if not diffs:
        return None
    return max(diffs), statistics.fmean(diffs), len(diffs)


def available(series_per_place, name):
    """Wieviele Orte liefern die Variable mit mindestens einem Wert?"""
    count = 0
    for series in series_per_place:
        values = series.get(name)
        if values and any(v is not None for v in values):
            count += 1
    return count


def column(series_per_place, name):
    return [series.get(name) for series in series_per_place]


def fmt(dev, unit):
    if dev is None:
        return "     —      "
    return f"{dev[1]:6.3f} ({dev[0]:5.2f}) {unit}"


def run(use_cloud):
    every = DAILY_VARS + HOURLY_VARS
    by_country = {}
    for country, name, lat, lon in POINTS:
        by_country.setdefault(country, []).append((country, name, lat, lon))

    print("# Verfuegbarkeit und Abweichung je Variable, Modell, "
          "Jahreszeit und Land")
    print(f"\nQuelle lokal: {LOCAL_API}")
    if use_cloud:
        print(f"Quelle Cloud: {CLOUD_API}  (kostet Kontingent)")
    else:
        print("Cloud-Vergleich uebersprungen (--cloud schaltet ihn ein).")

    rows = []
    for season, year, start, end in WINDOWS:
        for country, points in sorted(by_country.items()):
            got = {}
            for model in MODELS:
                got[model] = fetch(LOCAL_API, points, start, end,
                                   DAILY_VARS, HOURLY_VARS, model)
            cloud = {}
            if use_cloud:
                for model in MODELS:
                    cloud[model] = fetch(CLOUD_API, points, start, end,
                                         DAILY_VARS, HOURLY_VARS, model)

            for model in MODELS:
                label = model or "VORGABE"
                for name in every:
                    unit = "mm" if name == "precipitation_sum" else (
                        "m" if name == "snow_depth_max" else (
                            "m3/m3" if name.startswith("soil_moisture")
                            else "K"))
                    rows.append({
                        "season": season, "year": year, "country": country,
                        "model": label, "var": name, "unit": unit,
                        "places": available(got[model], name),
                        "of": len(points),
                        "vs_cloud": deviation(column(got[model], name),
                                              column(cloud[model], name))
                        if use_cloud else None,
                        "vs_default": deviation(column(got[model], name),
                                                column(got[None], name))
                        if model else None,
                    })
            print(f"  · {season} {year} {country} "
                  f"({len(points)} Orte) gemessen", file=sys.stderr)

    print("\n## Verfuegbarkeit (Orte mit mindestens einem Wert)\n")
    print("| Variable | Modell | " + " | ".join(
        f"{s} {y}" for s, y, _, _ in
        [(w[0], w[1], w[2], w[3]) for w in WINDOWS]) + " |")
    print("|---|---|" + "---|" * len(WINDOWS))
    for name in every:
        for model in MODELS:
            label = model or "VORGABE"
            cells = []
            for season, year, _, _ in WINDOWS:
                hit = sum(r["places"] for r in rows
                          if r["var"] == name and r["model"] == label
                          and r["season"] == season and r["year"] == year)
                total = sum(r["of"] for r in rows
                            if r["var"] == name and r["model"] == label
                            and r["season"] == season and r["year"] == year)
                cells.append("—" if hit == 0 else f"{hit}/{total}")
            print(f"| `{name}` | {label} | " + " | ".join(cells) + " |")

    if use_cloud:
        print("\n## Eigene Instanz gegen den oeffentlichen Dienst\n")
        print("Mittlere Abweichung (groesste in Klammern). "
              "Nur wo beide liefern.\n")
        print("| Variable | Modell | " + " | ".join(
            f"{s} {y}" for s, y, _, _ in WINDOWS) + " |")
        print("|---|---|" + "---|" * len(WINDOWS))
        for name in every:
            for model in MODELS:
                label = model or "VORGABE"
                cells = []
                for season, year, _, _ in WINDOWS:
                    parts = [r["vs_cloud"] for r in rows
                             if r["var"] == name and r["model"] == label
                             and r["season"] == season and r["year"] == year
                             and r["vs_cloud"]]
                    if not parts:
                        cells.append("—")
                    else:
                        cells.append(
                            f"{statistics.fmean(p[1] for p in parts):.3f} "
                            f"({max(p[0] for p in parts):.2f})")
                print(f"| `{name}` | {label} | " + " | ".join(cells) + " |")

    print("\n## Gepinnter Datensatz gegen die bisherige Vorgabe\n")
    print("Je Land getrennt — der Instrumentwechsel schlaegt im Gebirge "
          "und im Winter am staerksten durch.\n")
    print("| Variable | Modell | Jahreszeit | Jahr | " +
          " | ".join(sorted(by_country)) + " |")
    print("|---|---|---|---|" + "---|" * len(by_country))
    for name in every:
        for model in MODELS:
            if model is None:
                continue
            for season, year, _, _ in WINDOWS:
                cells = []
                unit = ""
                for country in sorted(by_country):
                    match = [r for r in rows
                             if r["var"] == name and r["model"] == model
                             and r["season"] == season and r["year"] == year
                             and r["country"] == country]
                    dev = match[0]["vs_default"] if match else None
                    unit = match[0]["unit"] if match else ""
                    cells.append("—" if dev is None
                                 else f"{dev[1]:.3f} ({dev[0]:.2f})")
                print(f"| `{name}` [{unit}] | {model} | {season} | {year} | "
                      + " | ".join(cells) + " |")

    return rows


def self_test():
    # Tagesmittel: die Gruppierung haengt am Datum, nicht an der Position.
    times = ["2020-09-01T00:00", "2020-09-01T01:00", "2020-09-02T00:00"]
    assert daily_mean(times, [1.0, 3.0, 5.0]) == [2.0, 5.0]
    # Ein einzelnes Loch faellt aus dem Mittel, der Tag bleibt.
    assert daily_mean(times, [1.0, None, 5.0]) == [1.0, 5.0]
    # Ein ganz leerer Tag wird None und nicht 0.0 — sonst sieht eine
    # fehlende Stunde aus wie Frost.
    assert daily_mean(times, [None, None, 5.0]) == [None, 5.0]
    assert daily_mean(None, [1.0]) is None
    assert daily_mean(times, None) is None

    # Eine 25-Stunden-Nacht (Zeitumstellung) darf den Tag nicht verschieben.
    long_day = (["2020-10-25T%02d:00" % h for h in range(24)]
                + ["2020-10-25T02:00"] + ["2020-10-26T00:00"])
    got = daily_mean(long_day, [2.0] * 25 + [9.0])
    assert got == [2.0, 9.0], got

    # Abweichung: fehlende Reihen sind KEINE perfekte Uebereinstimmung.
    assert deviation([[1.0, 2.0]], [[1.0, 2.5]]) == (0.5, 0.25, 2)
    assert deviation([None], [[1.0]]) is None
    assert deviation([[None]], [[1.0]]) is None
    assert deviation([], []) is None

    # Verfuegbarkeit zaehlt Orte, nicht Werte.
    places = [{"a": [1.0, None]}, {"a": [None, None]}, {"a": None}, {}]
    assert available(places, "a") == 1
    assert available(places, "b") == 0

    # Gegenprobe: Waere `deviation` bei fehlender Reihe 0.0, ginge eine
    # nicht gelieferte Variable als perfekte Uebereinstimmung durch —
    # genau der stille Ausfall, den der Fahrplan verbietet.
    assert fmt(None, "K") .strip() == "—"
    assert "0.250" in fmt((0.5, 0.25, 2), "K")

    # Die Fenster muessen den Wechsel 2017 einschliessen, sonst misst die
    # Spalte „Abweichung zur Vorgabe" gar nichts.
    years = {y for _, y, _, _ in WINDOWS}
    assert any(y < 2017 for y in years) and any(y >= 2017 for y in years)
    assert {s for s, _, _, _ in WINDOWS} == {"Herbst", "Winter"}
    # Und beide Laender des Hold-outs muessen vertreten sein.
    assert {c for c, _, _, _ in POINTS} == {"DE", "AT", "CH"}

    print("Selbsttest ok")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--local", action="store_true",
                        help="nur die eigene Instanz befragen")
    parser.add_argument("--cloud", action="store_true",
                        help="zusaetzlich gegen den oeffentlichen Dienst")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.local or args.cloud:
        run(use_cloud=args.cloud)
    else:
        parser.print_help()
