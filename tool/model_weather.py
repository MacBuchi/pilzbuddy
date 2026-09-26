#!/usr/bin/env python3
"""Model weather for the Alpine region beyond the DWD's reach (#612).

    python3 tool/model_weather.py --out build/rain        # build / top up
    python3 tool/model_weather.py --out build/rain --verify
    python3 tool/model_weather.py --self-test             # no network

WHY. The Ampel needs rain (26 days) and temperature (28 days) at the
spot, and the app looks both up ON THE DEVICE: the RADOLAN stack
(tool/rain_grid.py) and the DWD station table (tool/spot_weather.py).
Both stop at the German border. Austria ran on the radar's edge and on
a Bavarian station 100 km away; South Tyrol had nothing. There is no
free Europe-wide radar or station network — what exists Europe-wide are
numerical model fields, and the Ampel was VALIDATED on exactly those
(Open-Meteo archive: IFS HRES 9 km, ERA5 before 2017; never on radar).
So this tool fetches model values for a fixed lattice over the Alpine
region and publishes them next to the radar, in the same encoding.

WHAT LEAVES CI, WHAT REACHES THE APP. CI asks Open-Meteo for FIXED
lattice points — nothing about any user. The app keeps loading from
our own release mirror; no new network target, no coordinate leaves a
device (the rule that put the grids on the device in the first place).

THE LATTICE. A regular grid in EPSG:3857, 12 km cells, over the box
5.9–17.2 E / 45.6–49.1 N, MINUS Germany (an approximate polyline of the
German southern border, see `DE_BORDER`). Mercator, because the app's
`RainGrid.mmAt` maps rows in Mercator — the model grid is read by the
very same Dart code as the radar grid, nothing new to get wrong. About
3 000 points. A point on the wrong side of the polyline simply gets the
other instrument; both are honest.

THE QUOTA. Open-Meteo's free tier (non-commercial, CC BY 4.0): 600
calls a minute, 5 000 an hour, 10 000 a day — where a call is one
location for up to seven days (two weeks count 1.5–2, four weeks 3).
Each run therefore fetches only the days that are missing, newest
first, within a budget (`BUDGET_CALLS`); a fresh stack fills over three
or four daily runs. Day files are the state: they live in the release
like the RADOLAN days, and a run that finds nothing missing fetches
nothing.

TWO APIs, ONE DATA SET. Days up to yesterday come from the forecast
endpoint with `past_days`; older gaps come from the historical-forecast
endpoint with explicit dates. Both serve the archived first hours of
the same model runs. Pinned to `icon_d2` (ICON-D2, 2.2 km): measured on
2026-09-26, `icon_seamless` returned the SAME values at every point of
the box on both endpoints — but it falls back to ICON-EU (7 km) silently
wherever D2 has no data. Pinned, a missing D2 day is a gap the next run
fills; unpinned it would be another instrument under the same label.

HOW THE APP SEES IT. Rain: a second day stack (`model_rain_*`), same
bytes as the radar days; the app falls back per day and per point.
Temperature: the lattice points ride in `weather_stations.json.gz` as
VIRTUAL STATIONS (`src: "openmeteo"`, height = Open-Meteo's own
downscaling elevation), so nearest-station logic, lapse correction and
the Ampel surface stay exactly as they are. Temperatures are stored as
day files too (`model_tmax_*`, `model_tmin_*`, 0.5 °C steps) — the
station rows are rebuilt from them each run.

Stdlib only, like the other tools here: this runs on a schedule.
"""
import argparse
import datetime as dt
import gzip
import hashlib
import json
import math
import os
import random
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
import rain_grid  # noqa: E402
import spot_weather  # noqa: E402

FORECAST_API = "https://api.open-meteo.com/v1/forecast"
HISTORY_API = "https://historical-forecast-api.open-meteo.com/v1/forecast"
MODELS = "icon_d2"
VARIABLES = ("precipitation_sum", "temperature_2m_max", "temperature_2m_min")

# west, south, east, north — the Alpine box: Aosta valley to the Vienna
# basin, Po plain edge to the Bavarian Forest. Deliberately wider than the
# GBIF box (tool/gbif_download.py): weather is cheap per point, finds are
# not.
BOX = (5.9, 45.6, 17.2, 49.1)
CELL_M = 12_000

# The German southern border as a polyline (lon, lat), west to east.
# Points NORTH of it and west of its last vertex are Germany and get no
# model value — there the DWD radar and stations are the instrument.
# Approximate on purpose: Basel, Lake Constance, Lindau, Füssen,
# Garmisch, Kufstein, Salzburg, Braunau, Passau, Bavarian Forest.
DE_BORDER = [
    (5.9, 47.56), (7.59, 47.56), (9.2, 47.66), (9.69, 47.54), (9.9, 47.56),
    (10.0, 47.53), (10.35, 47.30), (10.6, 47.57), (11.1, 47.42),
    (11.4, 47.42), (11.7, 47.58), (12.2, 47.62), (12.8, 47.68),
    (13.0, 47.83), (12.93, 48.0), (12.75, 48.12), (13.0, 48.26),
    (13.45, 48.55), (13.84, 48.77),
]

RAIN_DAYS = rain_grid.DAILY["days"]      # 26 — the Ampel's rain window
TEMP_DAYS = spot_weather.DAYS            # 28 — the station table's window
NO_DATA = rain_grid.NO_DATA              # 255, same marker as the radar
TEMP_OFFSET_C = 50.0                     # byte 0 = -50 °C, 254 = +77 °C
TEMP_STEP_C = 0.5

LOCATIONS_PER_REQUEST = 100
# Calls a single run may spend; the hourly limit is 5 000 and the job
# shares the day with nothing else on this key.
BUDGET_CALLS = 4_500
STATION_ID_BASE = 900_000
STATION_SRC = "openmeteo"

FILES = {
    "rain": "model_rain_{}.bin.gz",
    "tmax": "model_tmax_{}.bin.gz",
    "tmin": "model_tmin_{}.bin.gz",
}
ELEVATION_FILE = "model_elevation.bin.gz"


# ------------------------------------------------------------- lattice

def lattice(box=BOX, cell_m=CELL_M):
    """Geometry and cell centres of the model grid.

    Width and height are whole cells; east and south are moved OUT to the
    last cell edge, so a cell is exactly `cell_m` in Mercator metres and
    `RainGrid.mmAt` (floor of the fraction) lands every centre in its own
    cell.
    """
    west, south, east, north = box
    x0, x1 = rain_grid._to_x(west), rain_grid._to_x(east)
    y_top, y_bottom = rain_grid._to_y(north), rain_grid._to_y(south)
    width = math.ceil((x1 - x0) / cell_m)
    height = math.ceil((y_top - y_bottom) / cell_m)
    geometry = {
        "width": width, "height": height,
        "west": round(west, 6),
        "east": round(rain_grid._to_lon(x0 + width * cell_m), 6),
        "north": round(north, 6),
        "south": round(rain_grid._to_lat(y_top - height * cell_m), 6),
    }
    centres = []
    for row in range(height):
        lat = rain_grid._to_lat(y_top - (row + 0.5) * cell_m)
        for col in range(width):
            lon = rain_grid._to_lon(x0 + (col + 0.5) * cell_m)
            centres.append((round(lat, 5), round(lon, 5)))
    return geometry, centres


def border_lat(lon, border=DE_BORDER):
    """The German border's latitude at this longitude, or None east of it."""
    if lon < border[0][0] or lon > border[-1][0]:
        return None
    for (x0, y0), (x1, y1) in zip(border, border[1:]):
        if x0 <= lon <= x1:
            t = 0 if x1 == x0 else (lon - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
    return None


def in_germany(lat, lon):
    limit = border_lat(lon)
    return limit is not None and lat > limit


def cell_index(geometry, lat, lon):
    """The same arithmetic as `RainGrid.mmAt` in Dart — kept here so the
    self-test can prove every lattice centre maps back to its own cell."""
    g = geometry
    if lon < g["west"] or lon > g["east"] or lat > g["north"] or lat < g["south"]:
        return None
    x = math.floor((lon - g["west"]) / (g["east"] - g["west"]) * g["width"])
    top, bottom = rain_grid._to_y(g["north"]), rain_grid._to_y(g["south"])
    y = math.floor((rain_grid._to_y(lat) - top) / (bottom - top) * g["height"])
    if x < 0 or x >= g["width"] or y < 0 or y >= g["height"]:
        return None
    return y * g["width"] + x


# ------------------------------------------------------------ encoding

def temp_byte(celsius):
    if celsius is None or celsius != celsius:
        return NO_DATA
    return max(0, min(254, int(round((celsius + TEMP_OFFSET_C) / TEMP_STEP_C))))


def temp_value(byte):
    return None if byte == NO_DATA else byte * TEMP_STEP_C - TEMP_OFFSET_C


def rain_byte(mm):
    if mm is None or mm != mm:
        return NO_DATA
    return min(rain_grid.MAX_MM, max(0, int(round(mm))))


def grid_rows(values, geometry):
    """A flat list of bytes (row-major, length width*height) as rows."""
    w, h = geometry["width"], geometry["height"]
    assert len(values) == w * h, (len(values), w * h)
    return [bytes(values[y * w:(y + 1) * w]) for y in range(h)]


def write_grid(out_dir, name, values, geometry):
    payload = rain_grid.encode(grid_rows(values, geometry))
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, name), "wb") as handle:
        handle.write(payload)
    return {"file": name, "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest()}


def read_grid(out_dir, name, geometry):
    path = os.path.join(out_dir, name)
    if not os.path.exists(path):
        # The manifest lists a day this directory does not hold. On an
        # existing stack the workflow must download `model_*` from the
        # release first — a stack trace on `open` said none of that.
        raise SystemExit(f"{name} is in the manifest but not in {out_dir}: "
                         "a run on an existing stack needs the previous day "
                         "files (gh release download rain-data --pattern 'model_*')")
    with open(path, "rb") as handle:
        rows = rain_grid.decode(handle.read(), geometry["width"],
                                geometry["height"])
    return [b for row in rows for b in row]


def write_elevation(out_dir, elevation):
    raw = struct.pack(f"<{len(elevation)}h",
                      *[-32768 if e is None else int(round(e)) for e in elevation])
    payload = gzip.compress(raw, 9)
    with open(os.path.join(out_dir, ELEVATION_FILE), "wb") as handle:
        handle.write(payload)
    return {"file": ELEVATION_FILE, "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest()}


def read_elevation(out_dir, count):
    path = os.path.join(out_dir, ELEVATION_FILE)
    if not os.path.exists(path):
        return None
    with open(path, "rb") as handle:
        raw = gzip.decompress(handle.read())
    values = struct.unpack(f"<{count}h", raw)
    return [None if v == -32768 else v for v in values]


# ------------------------------------------------------------ planning

def needed_dates(today):
    """Every date the stacks should hold: the last TEMP_DAYS complete days
    (yesterday backwards). Rain needs 26 of them, temperature all 28."""
    yesterday = today - dt.timedelta(days=1)
    return [yesterday - dt.timedelta(days=i) for i in range(TEMP_DAYS)]


def missing_dates(previous, today):
    """Dates without a complete set of day files, newest first."""
    have = set()
    if previous:
        rain = {d["date"] for d in previous.get("rain", {}).get("days", [])}
        temp = {d["date"] for d in previous.get("temperature", {}).get("days", [])}
        have = rain & temp
    return [d for d in needed_dates(today) if d.isoformat() not in have]


def call_weight(days):
    """Open-Meteo's accounting, conservatively: a location for up to seven
    days is one call, longer windows count proportionally."""
    return max(1.0, days / 7.0)


def plan_windows(missing, today, points, budget=BUDGET_CALLS):
    """Contiguous date windows to fetch, newest first, within the budget.

    Returns a list of (start, end, via_past_days). The newest window ends
    yesterday and goes through the forecast endpoint (`past_days`); older
    ones through the historical endpoint with explicit dates. Stops
    before a window that would break the budget — the next run continues.
    """
    if not missing or not points:
        return []
    windows = []
    run = [missing[0]]
    for date in missing[1:]:
        if run[-1] - date == dt.timedelta(days=1):
            run.append(date)
        else:
            windows.append(run)
            run = [date]
    windows.append(run)
    spent = 0.0
    planned = []
    yesterday = today - dt.timedelta(days=1)
    for window in windows:
        newest, oldest = window[0], window[-1]
        # Trim from the OLD end until it fits: newest days first.
        while window:
            days = (newest - window[-1]).days + 1
            cost = call_weight(days) * points
            if spent + cost <= budget:
                break
            window = window[:-1]
        if not window:
            break
        oldest = window[-1]
        spent += call_weight((newest - oldest).days + 1) * points
        planned.append((oldest, newest, newest == yesterday))
        if len(window) < len(windows[len(planned) - 1]):
            break  # budget cut this window short; older ones wait
    return planned


# ------------------------------------------------------------- fetching

def _get_json(url, params, tries=5):
    query = urllib.parse.urlencode(params, safe=",")
    request = urllib.request.Request(f"{url}?{query}",
                                     headers={"User-Agent": "pilzbuddy/model_weather"})
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            if error.code == 429 or error.code >= 500:
                wait = 60 * (attempt + 1)
                print(f"  HTTP {error.code}, waiting {wait} s", file=sys.stderr)
                time.sleep(wait)
                continue
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            print(f"  {error}, retrying", file=sys.stderr)
            time.sleep(30 * (attempt + 1))
    raise SystemExit("Open-Meteo did not answer")


def fetch_window(points, start, end, via_past_days, today, chunk=LOCATIONS_PER_REQUEST,
                 get=_get_json, sleep=time.sleep):
    """{date: {index: (rain, tmax, tmin)}} plus elevation per index.

    `points` is a list of (index, lat, lon). Requests carry `chunk`
    locations each and are paced to stay under 600 calls a minute.
    """
    days = (end - start).days + 1
    result = {}
    elevation = {}
    for offset in range(0, len(points), chunk):
        batch = points[offset:offset + chunk]
        params = {
            "latitude": ",".join(f"{lat:.5f}" for _, lat, _ in batch),
            "longitude": ",".join(f"{lon:.5f}" for _, _, lon in batch),
            "daily": ",".join(VARIABLES),
            "models": MODELS,
            "timezone": "UTC",
        }
        if via_past_days:
            params["past_days"] = (today - start).days
            params["forecast_days"] = 1
            url = FORECAST_API
        else:
            params["start_date"] = start.isoformat()
            params["end_date"] = end.isoformat()
            url = HISTORY_API
        payload = get(url, params)
        answers = payload if isinstance(payload, list) else [payload]
        if len(answers) != len(batch):
            raise SystemExit(f"asked for {len(batch)} locations, got {len(answers)}")
        for (index, _, _), answer in zip(batch, answers):
            elevation[index] = answer.get("elevation")
            daily = answer["daily"]
            for i, date in enumerate(daily["time"]):
                d = dt.date.fromisoformat(date)
                if d < start or d > end:
                    continue  # today's partial day, or outside the window
                result.setdefault(date, {})[index] = (
                    daily[VARIABLES[0]][i], daily[VARIABLES[1]][i],
                    daily[VARIABLES[2]][i])
        # 600 calls a minute: a chunk of 100 locations × weight(days).
        sleep(60.0 * chunk * call_weight(days) / 600.0)
    return result, elevation


# --------------------------------------------------------------- build

def build(out_dir, manifest, today=None, get=_get_json, sleep=time.sleep,
          limit=None, budget=None):
    today = today or dt.datetime.now(dt.timezone.utc).date()
    geometry, centres = lattice()
    active = [(i, lat, lon) for i, (lat, lon) in enumerate(centres)
              if not in_germany(lat, lon)]
    if limit:
        active = active[:limit]
    previous = manifest.get("model")
    missing = missing_dates(previous, today)
    windows = plan_windows(missing, today, len(active),
                           budget=budget or BUDGET_CALLS)

    cells = geometry["width"] * geometry["height"]
    elevation = read_elevation(out_dir, cells) or [None] * cells
    fetched_days = []
    for start, end, via_past in windows:
        print(f"  {start} … {end} for {len(active)} points "
              f"({'past_days' if via_past else 'history'})", file=sys.stderr)
        values, elev = fetch_window(active, start, end, via_past, today,
                                    get=get, sleep=sleep)
        for index, e in elev.items():
            if e is not None:
                elevation[index] = e
        for date, per_point in sorted(values.items()):
            rain = [NO_DATA] * cells
            tmax = [NO_DATA] * cells
            tmin = [NO_DATA] * cells
            for index, (mm, hi, lo) in per_point.items():
                rain[index] = rain_byte(mm)
                tmax[index] = temp_byte(hi)
                tmin[index] = temp_byte(lo)
            stamp = date.replace("-", "")
            write_grid(out_dir, FILES["rain"].format(stamp), rain, geometry)
            write_grid(out_dir, FILES["tmax"].format(stamp), tmax, geometry)
            write_grid(out_dir, FILES["tmin"].format(stamp), tmin, geometry)
            fetched_days.append(date)
    if any(e is not None for e in elevation):
        elevation_entry = write_elevation(out_dir, elevation)
    else:
        elevation_entry = (previous or {}).get("elevation")

    # The section: every day that exists as a file, in date order, the
    # oldest beyond the window dropped — unchanged days carried over from
    # the previous manifest (they were never downloaded here).
    def carry(kind):
        old = {d["date"]: d for d in ((previous or {}).get(kind, {}).get("days", []))}
        return old

    rain_days, temp_days = [], []
    keep = set()
    wanted = {d.isoformat() for d in needed_dates(today)}
    old_rain, old_temp = carry("rain"), carry("temperature")
    for date in sorted(wanted):
        stamp = date.replace("-", "")
        if date in fetched_days:
            entry = _entry(out_dir, FILES["rain"].format(stamp), geometry)
            rain_days.append({"date": date, **entry})
            temp_days.append({"date": date,
                              "tmax": _entry(out_dir, FILES["tmax"].format(stamp), geometry),
                              "tmin": _entry(out_dir, FILES["tmin"].format(stamp), geometry)})
        else:
            if date in old_rain:
                rain_days.append(old_rain[date])
            if date in old_temp:
                temp_days.append(old_temp[date])
    for day in rain_days:
        keep.add(day["file"])
    for day in temp_days:
        keep.add(day["tmax"]["file"])
        keep.add(day["tmin"]["file"])
    if elevation_entry:
        keep.add(elevation_entry["file"])

    section = {
        "source": "Open-Meteo, model " + MODELS,
        "licence": "CC BY 4.0",
        "api": FORECAST_API,
        "cell_m": CELL_M,
        "points": len(active),
        "mask": "Germany excluded (polyline of the southern border)",
        "built": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "fetched": fetched_days,
        "rain": {**geometry, "days": rain_days},
        "temperature": {**geometry, "days": temp_days},
        "elevation": elevation_entry,
    }
    manifest["model"] = section
    return section, sorted(keep), active, elevation


def _entry(out_dir, name, geometry):
    with open(os.path.join(out_dir, name), "rb") as handle:
        payload = handle.read()
    values = read_grid(out_dir, name, geometry)
    known = [v for v in values if v != NO_DATA]
    entry = {"file": name, "bytes": len(payload),
             "sha256": hashlib.sha256(payload).hexdigest()}
    if name.startswith("model_rain_"):
        entry["max_mm"] = max(known) if known else 0
        entry["wet_percent"] = round(100 * sum(1 for v in known if v >= 1)
                                     / max(1, len(known)), 1)
    return entry


# ------------------------------------------------------------ stations

def station_name(lat, lon):
    return (f"Modell {lat:.2f}° N {lon:.2f}° O".replace(".", ","))


def virtual_stations(out_dir, section, table_days, active=None, elevation=None):
    """Rows for `weather_stations.json.gz`: one per lattice point, values
    aligned to the TABLE's day list (missing days stay null).

    Only points with an elevation get a row — the lapse correction needs
    a height, and a station without one would be corrected from zero.
    """
    geometry = section["temperature"]
    if active is None or elevation is None:
        _, centres = lattice()
        active = [(i, lat, lon) for i, (lat, lon) in enumerate(centres)
                  if not in_germany(lat, lon)]
        elevation = read_elevation(out_dir, geometry["width"] * geometry["height"])
        if elevation is None:
            return []
    grids = {}
    for day in geometry["days"]:
        if day["date"] not in table_days:
            continue
        grids[day["date"]] = (read_grid(out_dir, day["tmax"]["file"], geometry),
                              read_grid(out_dir, day["tmin"]["file"], geometry))
    rows = []
    for index, lat, lon in active:
        height = elevation[index]
        if height is None:
            continue
        maxs, mins = [], []
        for date in table_days:
            pair = grids.get(date)
            maxs.append(None if pair is None else temp_value(pair[0][index]))
            mins.append(None if pair is None else temp_value(pair[1][index]))
        if all(v is None for v in maxs):
            continue
        rows.append({"id": STATION_ID_BASE + index, "lat": lat, "lon": lon,
                     "h": int(round(height)), "name": station_name(lat, lon),
                     "src": STATION_SRC, "max": maxs, "min": mins})
    return rows


def append_stations(out_dir, manifest, rows):
    """Add the virtual stations to the station table of THIS run and fix
    the manifest's byte count (the app keys its cache on it)."""
    path = os.path.join(out_dir, "weather_stations.json.gz")
    if not os.path.exists(path):
        raise SystemExit("weather_stations.json.gz is not in the output "
                         "directory — run tool/spot_weather.py first (the "
                         "workflow builds 'daily weather model' together)")
    with open(path, "rb") as handle:
        table = json.loads(gzip.decompress(handle.read()).decode("utf-8"))
    table["stations"] = [s for s in table["stations"]
                         if s.get("src") != STATION_SRC] + rows
    payload = gzip.compress(json.dumps(table, separators=(",", ":")).encode("utf-8"), 9)
    with open(path, "wb") as handle:
        handle.write(payload)
    weather = manifest.setdefault("weather", {})
    weather["bytes"] = len(payload)
    weather["model_points"] = len(rows)
    return len(payload)


# ---------------------------------------------------------------- verify

def verify(out_dir, manifest, sample=6, get=_get_json, seed=None):
    """Re-ask the service for a few random points of the newest day and
    compare with what the grids say — the one check that catches a
    shifted lattice, a swapped max/min, or a stale file."""
    section = manifest.get("model")
    if not section or not section["rain"]["days"]:
        raise SystemExit("no model section to verify")
    geometry = section["rain"]
    newest = section["rain"]["days"][-1]["date"]
    temp_day = next(d for d in section["temperature"]["days"] if d["date"] == newest)
    rain = read_grid(out_dir, section["rain"]["days"][-1]["file"], geometry)
    tmax = read_grid(out_dir, temp_day["tmax"]["file"], geometry)
    tmin = read_grid(out_dir, temp_day["tmin"]["file"], geometry)
    _, centres = lattice()
    active = [(i, lat, lon) for i, (lat, lon) in enumerate(centres)
              if not in_germany(lat, lon) and rain[i] != NO_DATA]
    rng = random.Random(seed)
    bad = []
    for index, lat, lon in rng.sample(active, min(sample, len(active))):
        answer = get(HISTORY_API, {
            "latitude": f"{lat:.5f}", "longitude": f"{lon:.5f}",
            "daily": ",".join(VARIABLES), "models": MODELS, "timezone": "UTC",
            "start_date": newest, "end_date": newest})
        daily = answer["daily"]
        got = (rain_byte(daily[VARIABLES[0]][0]), temp_byte(daily[VARIABLES[1]][0]),
               temp_byte(daily[VARIABLES[2]][0]))
        have = (rain[index], tmax[index], tmin[index])
        ok = all(abs(g - h) <= 1 for g, h in zip(got, have))
        print(f"  {lat:.3f},{lon:.3f}: grid {have} service {got} "
              f"{'ok' if ok else 'MISMATCH'}", file=sys.stderr)
        if not ok:
            bad.append((lat, lon, have, got))
    if bad:
        raise SystemExit(f"{len(bad)} of {sample} points disagree with the service")
    print(f"verify: {sample} points agree on {newest}", file=sys.stderr)


# -------------------------------------------------------------- self-test

def self_test():
    import tempfile
    geometry, centres = lattice()
    assert geometry["width"] * geometry["height"] == len(centres)
    # Every centre maps back to its own cell — the Dart arithmetic.
    for i in (0, 1, geometry["width"], len(centres) // 2, len(centres) - 1):
        lat, lon = centres[i]
        assert cell_index(geometry, lat, lon) == i, (i, cell_index(geometry, lat, lon))
    # Cells are 12 km in Mercator, so the row count follows from the box.
    y_span = rain_grid._to_y(geometry["north"]) - rain_grid._to_y(geometry["south"])
    # South is rounded to six decimals in the manifest (~0.1 m), so a
    # cell is 12 km give or take centimetres — not metres.
    assert abs(y_span / geometry["height"] - CELL_M) < 0.05, \
        y_span / geometry["height"]
    # The mask: Munich and Freiburg are Germany; Innsbruck, Bozen, Zurich,
    # Vienna, Salzburg city, Vaduz are not.
    assert in_germany(48.14, 11.58), "München"
    assert in_germany(47.99, 7.85), "Freiburg"
    assert in_germany(47.72, 10.31), "Kempten"
    for name, lat, lon in (("Innsbruck", 47.27, 11.39), ("Bozen", 46.50, 11.35),
                           ("Zürich", 47.38, 8.54), ("Wien", 48.21, 16.37),
                           ("Salzburg", 47.80, 13.04), ("Vaduz", 47.14, 9.52),
                           ("Bregenz", 47.50, 9.75), ("Linz", 48.31, 14.29),
                           ("Reutte", 47.49, 10.72), ("Kufstein", 47.58, 12.17),
                           ("Braunau", 48.25, 13.04)):
        assert not in_germany(lat, lon), name
    for name, lat, lon in (("Oberstdorf", 47.41, 10.28), ("Füssen", 47.57, 10.70),
                           ("Garmisch", 47.49, 11.10), ("Freilassing", 47.84, 12.98),
                           ("Burghausen", 48.16, 12.83), ("Passau", 48.574, 13.46),
                           ("Lindau", 47.55, 9.69)):
        assert in_germany(lat, lon), name
    active = sum(1 for lat, lon in centres if not in_germany(lat, lon))
    assert 2000 < active < 4000, active
    # Temperature bytes: half degrees, both ends clamped, no-data kept.
    assert temp_value(temp_byte(12.3)) == 12.5
    assert temp_value(temp_byte(-7.75)) in (-7.5, -8.0)
    assert temp_byte(None) == NO_DATA and temp_value(NO_DATA) is None
    assert temp_byte(-90) == 0 and temp_byte(200) == 254
    assert rain_byte(3.4) == 3 and rain_byte(None) == NO_DATA and rain_byte(999) == 254
    # Planning: nothing there → newest window first, cut to the budget.
    today = dt.date(2026, 9, 26)
    missing = missing_dates(None, today)
    assert len(missing) == TEMP_DAYS and missing[0] == dt.date(2026, 9, 25)
    planned = plan_windows(missing, today, points=3000, budget=4500)
    assert len(planned) == 1, planned
    start, end, via_past = planned[0]
    assert end == dt.date(2026, 9, 25) and via_past
    assert call_weight((end - start).days + 1) * 3000 <= 4500
    assert (end - start).days + 1 >= 7, "at least a week fits"
    # A stack with one gap in the middle: the gap comes via history.
    previous = {"rain": {"days": [{"date": d.isoformat()} for d in needed_dates(today)
                                  if d != dt.date(2026, 9, 20)]},
                "temperature": {"days": [{"date": d.isoformat()} for d in needed_dates(today)
                                         if d != dt.date(2026, 9, 20)]}}
    gap = plan_windows(missing_dates(previous, today), today, 3000)
    assert gap == [(dt.date(2026, 9, 20), dt.date(2026, 9, 20), False)], gap
    # Up to date → nothing to fetch.
    full = {"rain": previous["rain"], "temperature": previous["temperature"]}
    full["rain"]["days"].append({"date": "2026-09-20"})
    full["temperature"]["days"].append({"date": "2026-09-20"})
    assert plan_windows(missing_dates(full, today), today, 3000) == []
    # An end-to-end build against a fake service, then the station rows.
    tmp = tempfile.mkdtemp()

    def fake_get(url, params):
        lats = [float(v) for v in params["latitude"].split(",")]
        lons = [float(v) for v in params["longitude"].split(",")]
        if "past_days" in params:
            first = today - dt.timedelta(days=params["past_days"])
            dates = [first + dt.timedelta(days=i) for i in range(params["past_days"] + 1)]
        else:
            start = dt.date.fromisoformat(params["start_date"])
            end = dt.date.fromisoformat(params["end_date"])
            dates = [start + dt.timedelta(days=i) for i in range((end - start).days + 1)]
        out = []
        for lat, lon in zip(lats, lons):
            out.append({"elevation": 1000 + lat, "daily": {
                "time": [d.isoformat() for d in dates],
                VARIABLES[0]: [round((lat + lon) % 7, 1) for _ in dates],
                VARIABLES[1]: [20.0 - (lat - 45) for _ in dates],
                VARIABLES[2]: [10.0 - (lat - 45) for _ in dates]}})
        return out if len(out) > 1 else out[0]

    manifest = {}
    # Budget 450 for 150 points: three weeks fit (weight 3), the oldest
    # week waits for the next run — the cut the real first run makes.
    section, keep, active_pts, elevation = build(
        tmp, manifest, today=today, get=fake_get, sleep=lambda _: None,
        limit=150, budget=450)
    assert section["points"] == 150
    assert 7 <= len(section["rain"]["days"]) < TEMP_DAYS, len(section["rain"]["days"])
    assert section["rain"]["days"][-1]["date"] == "2026-09-25"
    assert all(f in keep for f in (section["rain"]["days"][0]["file"], ELEVATION_FILE))
    # Round trip through the day file, at one of the fetched points.
    index, lat, lon = active_pts[3]
    grid = read_grid(tmp, section["rain"]["days"][-1]["file"], section["rain"])
    assert grid[index] == rain_byte((lat + lon) % 7), (grid[index], lat, lon)
    assert grid[0] == NO_DATA or 0 in [a[0] for a in active_pts]
    # Station rows: aligned to the table's days, null where the stack has none.
    table_days = [d.isoformat() for d in reversed(needed_dates(today))]
    rows = virtual_stations(tmp, section, table_days, active_pts, elevation)
    assert len(rows) == 150 and rows[0]["src"] == STATION_SRC
    assert rows[0]["id"] == STATION_ID_BASE + active_pts[0][0]
    assert len(rows[0]["max"]) == TEMP_DAYS
    assert rows[0]["max"][-1] is not None and rows[0]["max"][0] is None, \
        "first run fills only the newest window"
    assert rows[0]["h"] == int(round(1000 + active_pts[0][1]))
    assert "Modell" in rows[0]["name"] and "," in rows[0]["name"]
    # Appending into a station table keeps the DWD rows and replaces ours.
    with open(os.path.join(tmp, "weather_stations.json.gz"), "wb") as handle:
        handle.write(gzip.compress(json.dumps({
            "days": table_days,
            "stations": [{"id": 44, "name": "G", "lat": 52.9, "lon": 8.2, "h": 44,
                          "max": [1.0] * TEMP_DAYS, "min": [0.0] * TEMP_DAYS},
                         {"id": 900001, "src": STATION_SRC, "name": "alt",
                          "lat": 0, "lon": 0, "h": 0, "max": [], "min": []}],
            "soil": []}).encode("utf-8")))
    manifest["weather"] = {"bytes": 1}
    size = append_stations(tmp, manifest, rows)
    with open(os.path.join(tmp, "weather_stations.json.gz"), "rb") as handle:
        table = json.loads(gzip.decompress(handle.read()))
    assert table["stations"][0]["id"] == 44
    assert len(table["stations"]) == 151, len(table["stations"])
    assert manifest["weather"]["bytes"] == size and manifest["weather"]["model_points"] == 150
    # A second build on top fetches nothing and carries the days over.
    before = json.loads(json.dumps(manifest["model"]))
    calls = []

    def counting_get(url, params):
        calls.append(url)
        return fake_get(url, params)

    section2, _, _, _ = build(tmp, manifest, today=today, get=counting_get,
                              sleep=lambda _: None, limit=150, budget=450)
    assert len(calls) == 2, "the oldest week comes now, via history"
    assert calls[0] == HISTORY_API
    assert len(section2["rain"]["days"]) == TEMP_DAYS
    assert section2["rain"]["days"][-1] == before["rain"]["days"][-1], \
        "unchanged days are carried over, not rebuilt"
    section3, _, _, _ = build(tmp, manifest, today=today, get=counting_get,
                              sleep=lambda _: None, limit=150, budget=450)
    assert len(calls) == 2 and section3["rain"]["days"] == section2["rain"]["days"]
    # Verify against the fake service agrees with the grids it built.
    verify(tmp, manifest, sample=3, get=fake_get, seed=1)
    print(f"Selbsttest ok — {geometry['width']}×{geometry['height']} Zellen, "
          f"{active} Punkte außerhalb Deutschlands")


# ------------------------------------------------------------------ main

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="build/rain")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--limit", type=int, default=None,
                        help="only the first N lattice points (trial runs)")
    parser.add_argument("--budget", type=float, default=BUDGET_CALLS)
    args = parser.parse_args()
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
    section, keep, active, elevation = build(args.out, manifest,
                                             limit=args.limit, budget=args.budget)
    table_days = manifest.get("weather", {}).get("days")
    rows = []
    if table_days:
        rows = virtual_stations(args.out, section, table_days, active, elevation)
        size = append_stations(args.out, manifest, rows)
    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
    with open(os.path.join(os.path.dirname(args.out) or ".", "model_keep.txt"),
              "w") as handle:
        handle.write("\n".join(keep) + "\n")
    summary = (
        f"### Modellgitter Alpenraum ({len(section['rain']['days'])} Regentage, "
        f"{len(section['temperature']['days'])} Temperaturtage)\n\n"
        f"- Punkte: {section['points']} (12 km, außerhalb Deutschlands)\n"
        f"- Neu geholt: {', '.join(section['fetched']) or 'nichts'}\n"
        f"- Virtuelle Stationen in der Tabelle: {len(rows)}"
        + (f" ({size / 1024:.0f} KB gesamt)\n" if rows else " (keine Tabelle in diesem Lauf)\n")
    )
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(summary)


if __name__ == "__main__":
    main()
