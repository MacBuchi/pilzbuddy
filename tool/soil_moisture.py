#!/usr/bin/env python3
"""Soil moisture 7–28 cm from ERA5-Land for all of DACH (#676).

    python3 tool/soil_moisture.py --out build/rain --api http://127.0.0.1:8080/v1/archive
    python3 tool/soil_moisture.py --out build/rain --verify
    python3 tool/soil_moisture.py --self-test             # no network

WHY. The logit class Herbsttrompete & Co. needs the soil moisture of the
last 26 days at the spot. Until now that was the DWD station value
`BFGL_AG` (% nFK) of the nearest station within 30 km — Germany only, so
the class was grey in Austria, Switzerland and South Tyrol. Lab run 25
(2026-10-08) refit the class on ERA5-Land 7–28 cm (m³/m³): it holds
against the DWD value in Germany and leads beyond the border. The
operator chose ONE source for all of DACH ("am besten nur eine Quelle"):
this grid, also inside Germany.

THE GRID. 0.1° in latitude and longitude, every cell centre ON an
ERA5-Land grid point (5.8, 5.9, … E; 45.6, 45.7, … N) — each value is
one model cell, nothing resampled. Not Mercator like the rain grids:
nothing here is drawn, the app only looks a value up, and a lat/lon
lattice keeps that lookup one division per axis. The rectangle runs
5.8–17.2 E / 45.6–55.1 N; only cells in Germany's box or the Alpine
box (`model_weather.BOX`) are asked for, the rest stays NO_DATA. Over
sea ERA5-Land has no value; near a coast Open-Meteo snaps to the
nearest land cell, so two lattice points can carry one model cell.

THE LAG, AND WHO BRIDGES IT. ERA5-Land arrives about five days late.
The stack holds REAL days only, and the manifest names the newest one.
Carrying the last value forward to yesterday is the app's job (PR C) —
exactly the seam lab run 25 measured (≤ 0.003 log-lik per stratum). A
day CI had carried forward would look measured in the file.

THE SERVICE. Built against a self-hosted Open-Meteo container in the
job (`rain-data.yml`), which reads the open S3 bucket on demand — ~9 500
points are two days of the public free tier per run. `--api` is
therefore REQUIRED for a build: no default that silently talks to
localhost, and none that would burn the public quota. `--verify`
always asks the PUBLIC archive API, the independent second channel.
The container is the instrument lab run 25 used on the operator's
machine (same image digest, checked bit for bit against the cache).

ENCODING. One byte per cell, 0.003 m³/m³ per step (254 = 0.762), 255 =
no data; row-delta + gzip like the rain grids (`rain_grid.encode`).
Measured on the 2026-09 grid: highest value 0.72; after the 26-day mean
the rounding moves the class logit by 0.002 median, 0.019 at most (at
15 °C) — the two thresholds are 0.76 apart.

Stdlib only, like the other tools here: this runs on a schedule.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
import model_weather  # noqa: E402
import rain_grid  # noqa: E402

PUBLIC_API = "https://archive-api.open-meteo.com/v1/archive"
MODELS = "era5_land"
VARIABLE = "soil_moisture_7_to_28cm_mean"

STEP_DEG = 0.1
# west, south, east, north of the cell CENTRES; cell edges lie half a
# step outside.
RECT = (5.8, 45.6, 17.2, 55.1)
# Where cells are asked for: Germany's box and the Alpine box.
GERMANY_BOX = (5.8, 47.2, 15.1, 55.1)
ALPINE_BOX = model_weather.BOX

MOISTURE_STEP = 0.003
NO_DATA = rain_grid.NO_DATA              # 255
# The Ampel averages 26 days (`ampelMoistureWindow`); four more keep a
# late or missing day from greying the class at once.
STACK_DAYS = 30
# A stack this far behind is not continued but started over.
RESTART_DAYS = 45
# Newest real day older than this: the lag is no longer ERA5's usual
# five days — the summary says so loudly.
STALE_DAYS = 10
LOCATIONS_PER_REQUEST = 100
FILE = "soil_{}.bin.gz"


# ------------------------------------------------------------- lattice

def lattice():
    """Geometry and cell centres, row-major from the north-west."""
    west, south, east, north = RECT
    width = round((east - west) / STEP_DEG) + 1
    height = round((north - south) / STEP_DEG) + 1
    geometry = {
        "width": width, "height": height, "step_deg": STEP_DEG,
        "west": round(west - STEP_DEG / 2, 6),
        "east": round(east + STEP_DEG / 2, 6),
        "north": round(north + STEP_DEG / 2, 6),
        "south": round(south - STEP_DEG / 2, 6),
    }
    centres = []
    for row in range(height):
        lat = round(north - row * STEP_DEG, 1)
        for col in range(width):
            centres.append((lat, round(west + col * STEP_DEG, 1)))
    return geometry, centres


def in_box(lat, lon, box):
    west, south, east, north = box
    return west <= lon <= east and south <= lat <= north


def wanted(lat, lon):
    return in_box(lat, lon, GERMANY_BOX) or in_box(lat, lon, ALPINE_BOX)


def cell_index(geometry, lat, lon):
    """What the app will do: floor of the fraction from the outer edge."""
    col = int((lon - geometry["west"]) / STEP_DEG)
    row = int((geometry["north"] - lat) / STEP_DEG)
    if not (0 <= col < geometry["width"] and 0 <= row < geometry["height"]):
        return None
    return row * geometry["width"] + col


def moisture_byte(value):
    if value is None:
        return NO_DATA
    return max(0, min(254, round(value / MOISTURE_STEP)))


def moisture_value(byte):
    return None if byte == NO_DATA else byte * MOISTURE_STEP


def write_grid(out_dir, name, values, geometry):
    return model_weather.write_grid(out_dir, name, values, geometry)


def read_grid(out_dir, name, geometry):
    path = os.path.join(out_dir, name)
    if not os.path.exists(path):
        raise SystemExit(f"{name} is in the manifest but not in {out_dir}: "
                         "fetch the previous day files first "
                         "(gh release download rain-data --pattern 'soil_*')")
    with open(path, "rb") as handle:
        rows = rain_grid.decode(handle.read(), geometry["width"],
                                geometry["height"])
    return [b for row in rows for b in row]


# ------------------------------------------------------------ planning

def fetch_range(previous, today):
    """(start, end) to ask for: from the day after the newest real day
    (or RESTART_DAYS back) to yesterday. The service answers the days it
    does not have yet with nulls; asking again costs nothing locally."""
    yesterday = today - dt.timedelta(days=1)
    floor = yesterday - dt.timedelta(days=RESTART_DAYS)
    newest = (previous or {}).get("newest")
    start = floor
    if newest:
        start = max(floor, dt.date.fromisoformat(newest) + dt.timedelta(days=1))
    return (start, yesterday) if start <= yesterday else None


def complete_days(values):
    """The days every point with a value on some day has a value on.

    `values` is {date: {index: float or None}}. A day ERA5-Land has not
    published comes back all null; a half-filled one must not enter the
    stack as if it were measured — the next run asks again."""
    known = {i for per in values.values() for i, v in per.items() if v is not None}
    if not known:
        return []
    return sorted(d for d, per in values.items()
                  if all(per.get(i) is not None for i in known))


# ------------------------------------------------------------- fetching

def _get_json(url, params, tries=5):
    query = urllib.parse.urlencode(params, safe=",")
    request = urllib.request.Request(f"{url}?{query}",
                                     headers={"User-Agent": "pilzbuddy/soil_moisture"})
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(request, timeout=600) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            if error.code == 429 or error.code >= 500:
                wait = 30 * (attempt + 1)
                print(f"  HTTP {error.code}, waiting {wait} s", file=sys.stderr)
                time.sleep(wait)
                continue
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            print(f"  {error}, retrying", file=sys.stderr)
            time.sleep(15 * (attempt + 1))
    raise SystemExit("Open-Meteo did not answer")


def fetch(api, points, start, end, chunk=LOCATIONS_PER_REQUEST, get=_get_json):
    """{date: {index: value}} for `points` = [(index, lat, lon)]."""
    result = {}
    for offset in range(0, len(points), chunk):
        batch = points[offset:offset + chunk]
        payload = get(api, {
            "latitude": ",".join(f"{lat:.1f}" for _, lat, _ in batch),
            "longitude": ",".join(f"{lon:.1f}" for _, _, lon in batch),
            "daily": VARIABLE, "models": MODELS, "timezone": "UTC",
            "start_date": start.isoformat(), "end_date": end.isoformat(),
        })
        answers = payload if isinstance(payload, list) else [payload]
        if len(answers) != len(batch):
            raise SystemExit(f"asked for {len(batch)} locations, got {len(answers)}")
        for (index, _, _), answer in zip(batch, answers):
            daily = answer["daily"]
            for date, value in zip(daily["time"], daily[VARIABLE]):
                result.setdefault(date, {})[index] = value
    return result


# --------------------------------------------------------------- build

def build(out_dir, manifest, api, today=None, get=_get_json, limit=None, source=None):
    today = today or dt.datetime.now(dt.timezone.utc).date()
    geometry, centres = lattice()
    active = [(i, lat, lon) for i, (lat, lon) in enumerate(centres)
              if wanted(lat, lon)]
    if limit:
        active = active[:limit]
    previous = manifest.get("soil")
    span = fetch_range(previous, today)
    days = {d["date"]: d for d in (previous or {}).get("days", [])}
    fetched = []
    if span:
        print(f"  {span[0]} … {span[1]} for {len(active)} points", file=sys.stderr)
        values = fetch(api, active, *span, get=get)
        complete = complete_days(values)
        # Only days that stay in the stack are written: on a first run
        # the range is RESTART_DAYS long, and the older files would be
        # uploaded only to be deleted by the next step.
        stays = set(sorted(set(days) | set(complete))[-STACK_DAYS:])
        cells = geometry["width"] * geometry["height"]
        for date in complete:
            if date not in stays:
                continue
            grid = [NO_DATA] * cells
            for index, value in values[date].items():
                grid[index] = moisture_byte(value)
            write_grid(out_dir, FILE.format(date.replace("-", "")), grid, geometry)
            fetched.append(date)

    for date in fetched:
        days[date] = {"date": date, **_entry(out_dir, FILE.format(date.replace("-", "")),
                                            geometry)}
    kept = sorted(days)[-STACK_DAYS:]
    section = {
        "source": "Copernicus ERA5-Land via Open-Meteo, " + VARIABLE,
        "licence": "Copernicus licence (C3S), Open-Meteo CC BY 4.0",
        "unit": "m3/m3",
        "encoding": {"step": MOISTURE_STEP, "no_data": NO_DATA},
        "instrument": source or api,
        "points": len(active),
        "built": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "fetched": fetched,
        # The newest REAL day; the app carries it forward to yesterday.
        "newest": kept[-1] if kept else None,
        **geometry,
        "days": [days[d] for d in kept],
    }
    manifest["soil"] = section
    return section, [days[d]["file"] for d in kept]


def _entry(out_dir, name, geometry):
    with open(os.path.join(out_dir, name), "rb") as handle:
        payload = handle.read()
    known = [b for b in read_grid(out_dir, name, geometry) if b != NO_DATA]
    return {"file": name, "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "cells": len(known),
            "mean": round(sum(known) / len(known) * MOISTURE_STEP, 4) if known else None}


def staleness(section, today):
    """Days between the newest real day and yesterday — five is ERA5's
    normal; the app bridges them."""
    if not section or not section.get("newest"):
        return None
    return (today - dt.timedelta(days=1) - dt.date.fromisoformat(section["newest"])).days


# --------------------------------------------------------------- verify

def verify(out_dir, manifest, sample=6, get=_get_json, seed=None, api=PUBLIC_API):
    """Re-ask the PUBLIC archive for a few random cells of the newest day.
    Catches a shifted lattice, a wrong step, a stale or swapped file."""
    section = manifest.get("soil")
    if not section or not section.get("days"):
        raise SystemExit("no soil section to verify")
    newest = section["days"][-1]
    grid = read_grid(out_dir, newest["file"], section)
    _, centres = lattice()
    active = [(i, lat, lon) for i, (lat, lon) in enumerate(centres)
              if grid[i] != NO_DATA]
    rng = random.Random(seed)
    bad = []
    for index, lat, lon in rng.sample(active, min(sample, len(active))):
        answer = get(api, {
            "latitude": f"{lat:.1f}", "longitude": f"{lon:.1f}",
            "daily": VARIABLE, "models": MODELS, "timezone": "UTC",
            "start_date": newest["date"], "end_date": newest["date"]})
        got = moisture_byte(answer["daily"][VARIABLE][0])
        ok = abs(got - grid[index]) <= 1
        print(f"  {lat:.1f},{lon:.1f}: grid {grid[index]} service {got} "
              f"{'ok' if ok else 'MISMATCH'}", file=sys.stderr)
        if not ok:
            bad.append((lat, lon, grid[index], got))
    if bad:
        raise SystemExit(f"{len(bad)} of {sample} cells disagree with the service")
    print(f"verify: {sample} cells agree on {newest['date']}", file=sys.stderr)


# ------------------------------------------------------------- self-test

def self_test():
    import tempfile
    geometry, centres = lattice()
    assert (geometry["width"], geometry["height"]) == (115, 96), geometry
    assert len(centres) == 115 * 96
    assert centres[0] == (55.1, 5.8) and centres[-1] == (45.6, 17.2)
    # Every centre sits on an ERA5-Land point and maps back to its cell.
    for i, (lat, lon) in enumerate(centres):
        assert abs(lat * 10 - round(lat * 10)) < 1e-9, lat
        assert cell_index(geometry, lat, lon) == i, (i, lat, lon)
    # ... and so does any point within half a step of it.
    i = 40 * 115 + 50
    lat, lon = centres[i]
    for dlat, dlon in ((0.049, 0.049), (-0.049, -0.049), (0.049, -0.049)):
        assert cell_index(geometry, lat + dlat, lon + dlon) == i
    assert cell_index(geometry, 56.0, 10.0) is None
    assert cell_index(geometry, 50.0, 18.0) is None
    # Asked for: Germany and the Alps; not Poland, not the Po plain.
    for name, lat, lon in (("Kiel", 54.3, 10.1), ("München", 48.1, 11.6),
                           ("Freiburg", 48.0, 7.8), ("Wien", 48.2, 16.4),
                           ("Bozen", 46.5, 11.3), ("Genf", 46.2, 6.1),
                           ("Klagenfurt", 46.6, 14.3), ("Görlitz", 51.2, 15.0)):
        assert wanted(lat, lon), name
    for name, lat, lon in (("Posen", 52.4, 16.9), ("Breslau", 51.1, 17.0),
                           ("Mailand", 45.5, 9.2), ("Prag", 50.1, 14.4 + 1.0)):
        assert not wanted(lat, lon), name
    assert 9_000 < sum(1 for la, lo in centres if wanted(la, lo)) < 10_000
    # Encoding: step, clamp, no data, round trip within half a step.
    assert moisture_byte(None) == NO_DATA
    assert moisture_byte(0.0) == 0 and moisture_byte(0.9) == 254
    assert moisture_byte(-0.01) == 0
    for v in (0.061, 0.255, 0.38, 0.72):
        assert abs(moisture_value(moisture_byte(v)) - v) <= MOISTURE_STEP / 2 + 1e-12
    # The fetch range: day after the newest real one up to yesterday,
    # restarted when far behind, nothing when up to date.
    today = dt.date(2026, 10, 8)
    assert fetch_range(None, today) == (dt.date(2026, 8, 23), dt.date(2026, 10, 7))
    assert fetch_range({"newest": "2026-10-02"}, today) == \
        (dt.date(2026, 10, 3), dt.date(2026, 10, 7))
    assert fetch_range({"newest": "2026-07-01"}, today)[0] == dt.date(2026, 8, 23)
    assert fetch_range({"newest": "2026-10-07"}, today) is None
    # Complete days only: all null is unpublished, half null is unfinished;
    # a cell null on EVERY day (sea) does not hold a day back.
    v = {"2026-10-01": {0: 0.3, 1: 0.2, 2: None},
         "2026-10-02": {0: 0.3, 1: None, 2: None},
         "2026-10-03": {0: None, 1: None, 2: None}}
    assert complete_days(v) == ["2026-10-01"], complete_days(v)
    assert complete_days({"2026-10-03": {0: None}}) == []

    # A build against a fake service: five days asked, three published,
    # the third only half. Then a second run, one day later, publishes
    # one more — the stack grows, `newest` moves, old entries carry over.
    calls = []

    def place_value(lat, lon):
        # Neighbours differ by 17 or 31 steps, far beyond verify's one-step
        # tolerance — a lattice shifted by one cell reads a wrong value.
        key = round(float(lat) * 10) * 31 + round(float(lon) * 10) * 17
        return round(0.05 + (key % 200) * MOISTURE_STEP, 3)

    def fake(url, params, published=("2026-09-30", "2026-10-01")):
        calls.append(params)
        lats = params["latitude"].split(",")
        lons = params["longitude"].split(",")
        start = dt.date.fromisoformat(params["start_date"])
        end = dt.date.fromisoformat(params["end_date"])
        dates = [(start + dt.timedelta(days=k)).isoformat()
                 for k in range((end - start).days + 1)]
        out = []
        for n, lat in enumerate(lats):
            series = []
            for d in dates:
                if d in published:
                    series.append(place_value(lat, lons[n]))
                elif d == "2026-10-02" and n % 2:
                    series.append(0.25)   # half a day
                else:
                    series.append(None)
            out.append({"daily": {"time": dates, VARIABLE: series}})
        return out

    with tempfile.TemporaryDirectory() as out:
        manifest = {"soil": {"newest": "2026-09-29", "days": []}}
        section, keep = build(out, manifest, "http://fake", today=dt.date(2026, 10, 4),
                              get=fake, limit=250)
        assert section["fetched"] == ["2026-09-30", "2026-10-01"], section["fetched"]
        assert section["newest"] == "2026-10-01"
        assert keep == ["soil_20260930.bin.gz", "soil_20261001.bin.gz"]
        assert calls[0]["start_date"] == "2026-09-30"
        assert calls[0]["end_date"] == "2026-10-03"
        assert len(calls) == 3                                      # 250 points / 100
        assert calls[0]["models"] == "era5_land"
        grid = read_grid(out, keep[-1], section)
        lat, lon = centres[0]                                       # first active cell
        assert grid[0] == moisture_byte(place_value(lat, lon)), grid[0]
        assert len(set(grid[:250])) > 20, "the fake must tell cells apart"
        assert section["days"][-1]["cells"] == 250
        # The second run, a day later: 10-02 is now complete.
        calls.clear()
        section, keep = build(out, manifest, "http://fake", today=dt.date(2026, 10, 5),
                              get=lambda u, p: fake(u, p, ("2026-10-02",)), limit=250)
        assert calls[0]["start_date"] == "2026-10-02"
        assert section["fetched"] == ["2026-10-02"]
        assert [d["date"] for d in section["days"]] == \
            ["2026-09-30", "2026-10-01", "2026-10-02"]
        assert staleness(section, dt.date(2026, 10, 8)) == 5
        # The stack is capped at STACK_DAYS, oldest out.
        manifest["soil"]["days"] = [{"date": (dt.date(2026, 8, 1) + dt.timedelta(days=k)).isoformat(),
                                     "file": f"x{k}"} for k in range(40)]
        manifest["soil"]["newest"] = "2026-10-02"
        section, keep = build(out, manifest, "http://fake", today=dt.date(2026, 10, 3),
                              get=fake, limit=10)
        assert len(keep) == STACK_DAYS and keep[-1] == "x39", keep[-3:]
        # A first run asks RESTART_DAYS but writes only what stays.
        with tempfile.TemporaryDirectory() as fresh:
            many = tuple((dt.date(2026, 8, 20) + dt.timedelta(days=k)).isoformat()
                         for k in range(40))
            m = {}
            section, keep = build(fresh, m, "http://fake", today=dt.date(2026, 10, 4),
                                  get=lambda u, p: fake(u, p, many), limit=5)
            assert len(keep) == STACK_DAYS == len(section["fetched"])
            assert sorted(os.listdir(fresh)) == keep, len(os.listdir(fresh))
        # Verify reads the newest day and asks the PUBLIC archive.
        manifest["soil"] = None
        section, _ = build(out, manifest, "http://fake", today=dt.date(2026, 10, 4),
                           get=fake, limit=250)
        asked = []

        def public(url, params):
            asked.append(url)
            return {"daily": {"time": [params["start_date"]],
                              VARIABLE: [place_value(params["latitude"],
                                                     params["longitude"])]}}
        verify(out, manifest, get=public, seed=1)
        assert asked and set(asked) == {PUBLIC_API}
        try:
            verify(out, manifest, get=lambda u, p: {"daily": {"time": [p["start_date"]],
                                                             VARIABLE: [0.6]}}, seed=1)
            raise AssertionError("a wrong service value must fail verify")
        except SystemExit:
            pass
    # A build without --api is refused (no silent default).
    try:
        main(["--out", "/nonexistent"])
        raise AssertionError("build without --api must be refused")
    except SystemExit as error:
        assert error.code != 0
    print("soil_moisture self-test: ok")


# ------------------------------------------------------------------ main

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="build/rain")
    parser.add_argument("--api", help="archive endpoint to build from (required for a build)")
    parser.add_argument("--source", help="what the manifest names as instrument, "
                        "e.g. the container image digest")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--limit", type=int, default=None,
                        help="only the first N lattice points (trial runs)")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        return
    manifest_path = os.path.join(args.out, "rain_manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as handle:
            manifest = json.load(handle)
    if args.verify:
        verify(args.out, manifest)
        return
    if not args.api:
        parser.error("--api is required for a build (see WHY in the docstring)")
    started = time.monotonic()
    section, keep = build(args.out, manifest, args.api, limit=args.limit,
                          source=args.source)
    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
    with open(os.path.join(os.path.dirname(args.out) or ".", "soil_keep.txt"),
              "w") as handle:
        handle.write("\n".join(keep) + "\n")
    lag = staleness(section, dt.datetime.now(dt.timezone.utc).date())
    summary = (
        f"### Bodenfeuchte ERA5-Land ({len(section['days'])} Tage)\n\n"
        f"- Punkte: {section['points']} (0,1°, Deutschland + Alpenbox)\n"
        f"- Neu geholt: {', '.join(section['fetched']) or 'nichts'}\n"
        f"- Jüngster echter Tag: {section['newest']} ({lag} Tage vor gestern)\n"
        f"- Dauer: {time.monotonic() - started:.0f} s\n"
    )
    print(summary)
    if lag is not None and lag > STALE_DAYS:
        print(f"::warning::ERA5-Land is {lag} days behind (usual: 5)")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(summary)


if __name__ == "__main__":
    main()
