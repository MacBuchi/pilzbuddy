#!/usr/bin/env python3
"""Turns DWD station observations into a small table the app can carry.

The rain course at a spot answers "how much"; this answers "how warm".
Same rule as the rain grid: the app looks the value up ON THE DEVICE, so
no coordinate ever reaches a weather service. Here that means shipping
every station's last fourteen days — air maxima and minima from the `kl`
network, soil means at 5 cm depth from the `EB` network — and letting the
app pick the nearest one itself.

    weather_stations.json.gz   stations with coordinates and 14 days
    (merged into rain_manifest.json under "weather")

Stdlib only, same reason as tool/rain_grid.py: this runs on a schedule,
and a pipeline that installs pandas to read semicolon-separated text is a
pipeline that breaks on a Tuesday.

WHY DAILY AND NOT HOURLY (measured 2026-08-04): hourly air temperature is
available and current (504 stations, `hourly/air_temperature/recent`,
column TT_TU, updated 08:40 the same morning). It was not chosen. Fourteen
days hourly are 336 values per station against 28 — twenty times the
payload — and they are drawn into a bar chart about 340 pixels wide,
where 336 points is one point per pixel. Maximum and minimum bracket the
day and answer the same question; a night frost is the daily minimum.

THE TRAP THAT COST TIME ELSEWHERE and applies here too: the description
file lists 1386 stations, most of them long closed. Only the ZIPs in
`recent/` are real. Filtering by the ZIP list rather than by the
description changed the measured "distance to the nearest station" from
132 km worst case to 46 km.
"""
import argparse
import gzip
import io
import json
import os
import re
import sys
import time
import urllib.request
import zipfile

CDC = ("https://opendata.dwd.de/climate_environment/CDC/"
       "observations_germany/climate/daily/")

# Two station networks, one asset. Air delivers daily EXTREMES (TXK/TNK);
# the soil network delivers daily MEANS per depth — V_TE005M is the 5 cm
# layer, the one the mycelium lives in. Columns are picked by NAME, and
# soil is where that stops being pedantry: at station 44 the neighbouring
# 2 cm column is all -999 while 5 cm measures (seen 2026-08-04) — one
# column off would not fail, it would show a different instrument.
AIR = {
    "base": CDC + "kl/recent/",
    "kind": "KL",
    "stations": "KL_Tageswerte_Beschreibung_Stationen.txt",
    "columns": ("TXK", "TNK"),
}
SOIL = {
    "base": CDC + "soil_temperature/recent/",
    "kind": "EB",
    "stations": "EB_Tageswerte_Beschreibung_Stationen.txt",
    "columns": ("V_TE005M",),
}

DAYS = 14
MISSING = -999  # the DWD's own marker, in every numeric column


def _fetch(url, timeout=90, tries=4):
    """GET with retries — 576 requests in a row, and one dropped socket
    used to end the whole run (same lesson as tool/rain_grid.py)."""
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as response:
                return response.read()
        except Exception:
            if attempt == tries - 1:
                raise
            time.sleep(2 ** attempt)


def active_ids(index_html, kind):
    """The station ids that actually deliver, from the ZIP listing."""
    return {int(m) for m in re.findall(
        rf"tageswerte_{kind}_(\d+)_akt\.zip", index_html)}


def parse_stations(text, keep):
    """Coordinates, elevation and name — fixed-width, latin-1.

    Rows that do not parse are skipped rather than guessed: a station
    without coordinates cannot be the nearest to anything.
    """
    stations = []
    for line in text.splitlines()[2:]:
        if len(line) < 61:
            continue
        try:
            sid = int(line[0:5])
            height = int(line[24:38])
            lat = float(line[38:50])
            lon = float(line[50:60])
        except ValueError:
            continue
        if sid not in keep:
            continue
        stations.append({
            "id": sid,
            "lat": round(lat, 4),
            "lon": round(lon, 4),
            "h": height,
            "name": line[61:101].strip(),
        })
    return stations


def parse_measurements(text, dates, columns):
    """{date: value tuple} for the wanted dates, from a produkt_*.txt.

    Columns are found by NAME from the header, never by position: the
    DWD has more than one daily product and they do not share a column
    order. Air reads ("TXK", "TNK") — daily maximum and minimum; soil
    reads ("V_TE005M",) — the daily mean at 5 cm. All in °C.
    """
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return {}
    header = [part.strip() for part in lines[0].split(";")]
    try:
        i_date = header.index("MESS_DATUM")
        i_cols = [header.index(name) for name in columns]
    except ValueError:
        return {}
    wanted = set(dates)
    out = {}
    for line in lines[1:]:
        parts = [part.strip() for part in line.split(";")]
        if len(parts) <= max([i_date, *i_cols]):
            continue
        raw = parts[i_date]
        if len(raw) != 8:
            continue
        date = f"{raw[:4]}-{raw[4:6]}-{raw[6:]}"
        if date not in wanted:
            continue
        out[date] = tuple(_value(parts[i]) for i in i_cols)
    return out


def has_temperature(values):
    """Hat diese Station im Fenster überhaupt eine Temperatur gemessen?

    Der `kl`-Datensatz enthält auch reine Niederschlagsstationen: Sie
    stehen in der Liste, ihre Temperaturspalten sind aber durchgehend
    -999 (gemessen 2026-08-04: 3 von 12 in der Stichprobe). Als „nächste
    Station" wären sie eine Antwort, die keine ist. Für Boden gilt
    dieselbe Prüfung auf dem Einer-Tupel.
    """
    return any(value is not None
               for row in values.values() for value in row)


def _value(text):
    try:
        number = float(text)
    except ValueError:
        return None
    return None if number <= MISSING + 0.5 else round(number, 1)


def _dates_ending(last, count):
    """`count` ISO dates ending at `last` (inclusive), oldest first."""
    year, month, day = (int(part) for part in last.split("-"))
    days = []
    for back in range(count - 1, -1, -1):
        stamp = _shift(year, month, day, -back)
        days.append(stamp)
    return days


def _shift(year, month, day, delta):
    """Date arithmetic without `datetime`, so the self-test stays pure."""
    total = _to_ordinal(year, month, day) + delta
    return _from_ordinal(total)


def _leap(year):
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def _month_days(year):
    return [31, 29 if _leap(year) else 28, 31, 30, 31, 30,
            31, 31, 30, 31, 30, 31]


def _to_ordinal(year, month, day):
    total = day
    for y in range(1900, year):
        total += 366 if _leap(y) else 365
    for m in range(month - 1):
        total += _month_days(year)[m]
    return total


def _from_ordinal(total):
    year = 1900
    while True:
        size = 366 if _leap(year) else 365
        if total <= size:
            break
        total -= size
        year += 1
    month = 1
    for length in _month_days(year):
        if total <= length:
            break
        total -= length
        month += 1
    return f"{year:04d}-{month:02d}-{total:02d}"


def newest_date(text):
    """The last measured day in a produkt file, as an ISO date."""
    for line in reversed([l for l in text.splitlines() if l.strip()]):
        parts = line.split(";")
        if len(parts) > 1 and parts[1].strip().isdigit() \
                and len(parts[1].strip()) == 8:
            raw = parts[1].strip()
            return f"{raw[:4]}-{raw[4:6]}-{raw[6:]}"
    return None


def _produkt(zip_bytes):
    archive = zipfile.ZipFile(io.BytesIO(zip_bytes))
    names = [n for n in archive.namelist() if n.startswith("produkt")]
    if not names:
        return None
    return archive.read(names[0]).decode("latin-1")


def _collect(network, dates, days, limit=None):
    """One network: the index, the station list, then every ZIP.

    Returns the dates (anchored at the first delivering station if none
    were passed in), the stations with their values, and the skip count.
    """
    base = network["base"]
    index = _fetch(base).decode("utf-8", "replace")
    ids = active_ids(index, network["kind"])
    stations = parse_stations(
        _fetch(base + network["stations"]).decode("latin-1"), ids)
    if limit:
        stations = stations[:limit]
    rows, missing = [], 0
    for station in stations:
        try:
            text = _produkt(_fetch(
                f"{base}tageswerte_{network['kind']}_{station['id']:05d}"
                "_akt.zip"))
        except Exception:
            missing += 1
            continue
        if text is None:
            missing += 1
            continue
        if dates is None:
            last = newest_date(text)
            if last is None:
                missing += 1
                continue
            dates = _dates_ending(last, days)
        values = parse_measurements(text, dates, network["columns"])
        # Beide Netze listen Stationen, die das Gesuchte nicht messen —
        # `kl` etwa reine Niederschlagsstationen (Spalten durchgehend
        # -999). Als „nächste Station" wären sie eine Antwort, die
        # keine ist.
        if not has_temperature(values):
            missing += 1
            continue
        rows.append((station, values))
    return dates, rows, missing


def _payload(dates, air, soil):
    """The asset's content — pure, so the self-test can pin the mapping.

    A reversed day list or a swapped max/min slot would not fail
    anything at build time; it would ship weather that looks right.
    """
    return {
        "days": dates,
        "stations": [{
            **station,
            "max": [values.get(d, (None, None))[0] for d in dates],
            "min": [values.get(d, (None, None))[1] for d in dates],
        } for station, values in air],
        "soil": [{
            **station,
            "soil": [values.get(d, (None,))[0] for d in dates],
        } for station, values in soil],
    }


def build(out_dir, days=DAYS, limit=None):
    dates, air, air_skipped = _collect(AIR, None, days, limit)
    if not air:
        raise SystemExit("no air station delivered measurements")
    # Der Boden fährt auf DEMSELBEN Fenster: Das Diagramm zeichnet eine
    # gemeinsame Zeitachse, und eine um einen Tag anders verankerte
    # Bodenliste legte still den gestrigen Boden unter den heutigen
    # Regen. Tage, die das Bodennetz noch nicht geliefert hat, bleiben
    # None — die Linie endet früher, statt zu raten. Ein leeres Bodennetz
    # ist erlaubt: Dann trägt das Asset nur Luft, die App zeigt weniger.
    _, soil, soil_skipped = _collect(SOIL, dates, days, limit)

    payload = gzip.compress(json.dumps(
        _payload(dates, air, soil),
        separators=(",", ":")).encode("utf-8"), 9)
    os.makedirs(out_dir, exist_ok=True)
    name = "weather_stations.json.gz"
    with open(os.path.join(out_dir, name), "wb") as handle:
        handle.write(payload)
    return {
        "file": name,
        "days": dates,
        "stations": len(air),
        "soil": len(soil),
        "skipped": air_skipped + soil_skipped,
        "bytes": len(payload),
    }


def self_test():
    """Everything that does not need the network."""
    listing = ('href="tageswerte_KL_00044_akt.zip" '
               'href="tageswerte_KL_00003_akt.zip" '
               'href="tageswerte_EB_00078_akt.zip"')
    assert active_ids(listing, "KL") == {44, 3}
    assert active_ids(listing, "EB") == {78}, \
        "an air ZIP must never count as a soil station"
    assert active_ids("nothing here", "KL") == set()

    # The description file is fixed-width and lists LONG CLOSED stations
    # too — 1386 against 576 that deliver. Filtering by the ZIP list is
    # the whole point of `keep`.
    # Zwei ECHTE Zeilen aus der Beschreibungsdatei (abgerufen 2026-08-04).
    # Von Hand nachgebaute wären um eine Spalte verschoben — genau das ist
    # beim ersten Versuch passiert, und der Parser war unschuldig.
    header = ("Stations_id von_datum bis_datum Stationshoehe geoBreite "
              "geoLaenge Stationsname Bundesland Abgabe\n" + "-" * 40 + "\n")
    row = (
        "00044 19690101 20260803             44     52.9336    8.2370 "
        "Großenkneten                             Niedersachsen"
        "                            Frei\n"
        "00001 19370101 19860630            478     47.8413    8.8493 "
        "Aach                                     Baden-Württemberg"
        "                        Frei\n"
    )
    parsed = parse_stations(header + row, {44})
    assert len(parsed) == 1, parsed
    assert parsed[0]["id"] == 44
    assert abs(parsed[0]["lat"] - 52.9336) < 1e-6, parsed
    assert abs(parsed[0]["lon"] - 8.2370) < 1e-6, parsed
    assert parsed[0]["h"] == 44
    assert parsed[0]["name"] == "Großenkneten", parsed

    # Columns BY NAME. This fixture puts TXK and TNK in a different order
    # than the real file on purpose: reading them positionally would swap
    # maximum and minimum, and a swapped pair still looks like weather.
    produkt = (
        "STATIONS_ID;MESS_DATUM;QN_3;TNK;TXK;eor\n"
        "         44;20260802;    1;  12.1;  31.5;eor\n"
        "         44;20260803;    1;-999;  23.2;eor\n"
    )
    air = AIR["columns"]
    values = parse_measurements(produkt, ["2026-08-02", "2026-08-03"], air)
    assert values["2026-08-02"] == (31.5, 12.1), values
    assert values["2026-08-03"] == (23.2, None), 'missing must be None'
    assert parse_measurements(produkt, ["2026-07-01"], air) == {}
    assert parse_measurements("", ["2026-08-02"], air) == {}
    assert parse_measurements("no;header;here\n", ["2026-08-02"], air) == {}

    # The REAL soil header (fetched 2026-08-04), values shaped like the
    # real station 44: the 2 cm column all -999 while 5 cm measures. A
    # read one column off would not fail — it would show a different
    # instrument's numbers.
    soil = (
        "STATIONS_ID;MESS_DATUM;QN_2;V_TE002M;V_TE005M;V_TE010M;"
        "V_TE020M;V_TE050M;eor\n"
        "         44;20260802;    1;  -999;  24.2;  23.3;  22.0;"
        "  19.8;eor\n"
        "         44;20260803;    1;  -999;  -999;  23.1;  21.9;"
        "  19.7;eor\n"
    )
    values = parse_measurements(soil, ["2026-08-02", "2026-08-03"],
                                SOIL["columns"])
    assert values["2026-08-02"] == (24.2,), values
    assert values["2026-08-03"] == (None,), values
    assert parse_measurements(soil, ["2026-08-02"], air) == {}, \
        "an air read on a soil file must come back empty, not guessed"

    assert newest_date(produkt) == "2026-08-03"
    assert newest_date("") is None

    # Dates: the window ends at the newest measured day, and it has to
    # step over month and year boundaries — a wrong date silently reads
    # the wrong day's weather.
    assert _dates_ending("2026-08-03", 3) == \
        ["2026-08-01", "2026-08-02", "2026-08-03"]
    assert _dates_ending("2026-03-01", 2) == ["2026-02-28", "2026-03-01"]
    assert _dates_ending("2024-03-01", 2) == ["2024-02-29", "2024-03-01"], \
        "2024 is a leap year"
    assert _dates_ending("2026-01-01", 2) == ["2025-12-31", "2026-01-01"]
    assert _dates_ending("2100-03-01", 2) == ["2100-02-28", "2100-03-01"], \
        "1900-style century rule"
    assert len(_dates_ending("2026-08-03", 14)) == 14

    assert has_temperature({"2026-08-02": (31.5, 12.1)}) is True
    assert has_temperature({"2026-08-02": (None, 12.1)}) is True
    assert has_temperature({"2026-08-02": (None, None)}) is False
    assert has_temperature({}) is False
    # Boden liefert Einer-Tupel — dieselbe Prüfung muss auch dort greifen.
    assert has_temperature({"2026-08-02": (24.2,)}) is True
    assert has_temperature({"2026-08-02": (None,)}) is False

    assert _value("-999") is None
    assert _value("  23.2") == 23.2
    assert _value("eor") is None
    assert _value("-3.4") == -3.4, "frost is a real measurement"

    # Der Zusammenbau: Tag-Reihenfolge und die max/min-Plätze. Ein
    # vertauschtes Paar oder rückwärts gefüllte Bodentage sähen im
    # fertigen Asset aus wie Wetter.
    station = {"id": 44, "lat": 52.9, "lon": 8.2, "h": 44, "name": "G"}
    built = _payload(
        ["2026-08-02", "2026-08-03"],
        [(station, {"2026-08-02": (31.5, 12.1)})],
        [(station, {"2026-08-03": (24.2,)})],
    )
    assert built["stations"][0]["max"] == [31.5, None], built
    assert built["stations"][0]["min"] == [12.1, None], built
    assert built["soil"][0]["soil"] == [None, 24.2], built
    assert built["soil"][0]["name"] == "G"
    assert _payload(["2026-08-02"], [(station, {})], [])["soil"] == [], \
        "an empty soil network must not break the asset"

    print("spot_weather self-test: ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="build/rain")
    parser.add_argument("--days", type=int, default=DAYS)
    parser.add_argument("--limit", type=int,
                        help="only the first N stations (for a quick check)")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    entry = build(args.out, days=args.days, limit=args.limit)
    manifest_path = os.path.join(args.out, "rain_manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as handle:
            manifest = json.load(handle)
    manifest["weather"] = entry
    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)

    summary = (
        f"### Stationswerte ({entry['stations']} Luft, "
        f"{entry['soil']} Boden)\n\n"
        f"- Zeitraum: {entry['days'][0]} bis {entry['days'][-1]}\n"
        f"- Ohne Messwerte übersprungen: {entry['skipped']}\n"
        f"- Datei: {entry['bytes'] / 1024:.0f} KB gepackt\n"
    )
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(summary)


if __name__ == "__main__":
    sys.exit(main())
