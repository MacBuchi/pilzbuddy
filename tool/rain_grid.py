#!/usr/bin/env python3
"""Turns DWD rainfall products into a compact value grid for PilzBuddy.

The app draws its own contour lines in its own palette, and it answers
"how much rain fell at this spot" without ever sending a coordinate to
anyone. Both need the raw millimetres on the device, so this script
fetches them from the DWD's WCS, quantises them to one byte per square
kilometre and publishes the result as a release asset:

    rain_<layer>.bin.gz   row-delta encoded, gzipped, 1 byte per cell
    rain_manifest.json    extent, grid size, measurement time, checksums

Stdlib only, on purpose — same reason as tool/feedback_bot.py: this runs
in CI on a schedule, and a pipeline that installs numpy and rasterio to
read one uncompressed float raster is a pipeline that breaks on a
Tuesday. Reading the GeoTIFF takes `struct`, and gzip takes `zlib`.

Usage:
    python3 tool/rain_grid.py --layer w4 --out build/rain
    python3 tool/rain_grid.py --layer sf --out build/rain
    python3 tool/rain_grid.py --self-test        # no network

THE ONE TRAP (measured 2026-08-04, cost half an afternoon): a
GetCoverage request WITHOUT `subset=time(...)` does not fail. GeoServer
merges every granule of the mosaic and returns values roughly twice as
high — plausible-looking, wrong, and silent. With the time subset the
values match GetFeatureInfo to the decimal. Never drop it.
"""
import argparse
import gzip
import hashlib
import json
import math
import os
import random
import re
import struct
import sys
import time
import urllib.request

WCS = "https://maps.dwd.de/geoserver/dwd/wcs"

# Germany plus a thin margin. Deliberately not the DACH box of the radar
# layers: RADOLAN's calibrated sums stop at the border, and asking for
# more only buys empty cells that still cost bytes.
BOUNDS = (5.6, 47.0, 15.4, 55.2)  # west, south, east, north

LAYERS = {
    "w4": {
        "coverage": "dwd__RADOLAN-W4",
        "label": "30 Tage",
        # Daily product. The 30 day sum is the number foragers compute
        # (forum rule of thumb: >=100 mm) and the one the Czech weather
        # service bases its mushroom index on.
    },
    "sf": {
        "coverage": "dwd__SF-Produkt",
        "label": "24 Stunden",
    },
}

# The daily stack behind the 14 day course at a spot.
#
# `SF-Produkt_(0-24)` is the DWD's own fixed 00-24 UTC daily sum, and the
# service keeps 366 of them (measured 2026-08-04). So the days do not have
# to be summed out of hourly products, and a full year of history is there
# for the backward validation later.
#
# Why a stack instead of ready-made 7 and 14 day sums: a sum cannot tell
# whether the 40 mm fell eleven days ago or yesterday, and for mushrooms
# that is the whole difference. From the stack the app derives any window
# AND the course — one product instead of three.
#
# 26 days since 2026-08-09 (was 14): that is the rain window of the
# validated Ampel model (docs/pilzampel-konzept.md, tool/ampel_validate.py
# — 26-day weighted cumulation). The chart in the app keeps showing the
# last 14 days; the extra days feed only the model. Shipping a second,
# shorter window on the device instead would have meant a device model
# that differs from the validated one — exactly the drift the validation
# exists to prevent.
DAILY = {
    "coverage": "dwd__SF-Produkt_(0-24)",
    "label": "Tagessummen",
    "days": 26,
}

NO_DATA = 255  # in the quantised grid; the DWD marks it as -1.0 or NaN
MAX_MM = 254  # anything above is clamped — see _quantise


def _fetch(url, timeout=180, tries=4):
    """GET with a few retries.

    The daily stack makes twentysix requests of about nine megabytes in a
    row, and a single dropped TLS connection used to end the whole run
    (measured 2026-08-04: `SSL: UNEXPECTED_EOF_WHILE_READING` on the
    ninth day). Nothing is corrupted when that happens — the manifest is
    written last — but a nightly job that gives up on one flaky socket is
    a nightly job that is red every few days.
    """
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as response:
                return response.read()
        except Exception:
            if attempt == tries - 1:
                raise
            time.sleep(2 ** attempt)


def default_time(coverage):
    """The newest granule the service offers, as an ISO timestamp.

    Read from DescribeCoverage rather than computed from the clock: the
    products are published with a lag, and a timestamp the service does
    not have is answered with an exception, not with the nearest one.
    """
    xml = _fetch(f"{WCS}?service=WCS&version=2.0.1&request=DescribeCoverage"
                 f"&coverageId={coverage}").decode("utf-8", "replace")
    match = re.search(r'<wcsgs:TimeDomain[^>]*default="([^"]+)"', xml)
    if not match:
        raise SystemExit(f"{coverage}: no default time in DescribeCoverage")
    return match.group(1)


def available_times(coverage):
    """Every granule the service offers, oldest first.

    Read, not computed: the daily product has gaps when the radar
    composite failed, and a date the service does not have comes back as
    an exception. Guessing "yesterday minus n days" would turn one bad
    night at the DWD into a broken pipeline.
    """
    xml = _fetch(f"{WCS}?service=WCS&version=2.0.1&request=DescribeCoverage"
                 f"&coverageId={coverage}").decode("utf-8", "replace")
    return _parse_times(xml, coverage)


def _parse_times(xml, coverage="<coverage>"):
    times = re.findall(r"<gml:timePosition>([^<]+)</gml:timePosition>", xml)
    if not times:
        raise SystemExit(f"{coverage}: DescribeCoverage lists no time instants")
    return sorted(times)


def coverage_url(coverage, when, bounds):
    west, south, east, north = bounds
    return (
        f"{WCS}?service=WCS&version=2.0.1&request=GetCoverage"
        f"&coverageId={coverage}&format=image/tiff"
        # The native CRS cannot be written as GeoTIFF at all — GeoServer
        # answers "Unable to map projection Stereographic_North_Pole".
        # 3857 is what the map uses anyway.
        f"&outputCrs=http://www.opengis.net/def/crs/EPSG/0/3857"
        f"&subsettingCrs=http://www.opengis.net/def/crs/EPSG/0/4326"
        f"&subset=Long({west},{east})&subset=Lat({south},{north})"
        f'&subset=time("{when}")'
    )


def read_geotiff(data):
    """Minimal GeoTIFF reader: one band, 64 bit float, tiled, uncompressed.

    That is exactly what this WCS emits. Anything else is rejected loudly
    instead of decoded wrongly — a raster misread as the wrong sample
    format still produces numbers, and numbers get shipped.
    """
    if data[:2] not in (b"MM", b"II"):
        raise SystemExit("not a TIFF (did the service return an XML error?)")
    order = ">" if data[:2] == b"MM" else "<"
    offset = struct.unpack(order + "I", data[4:8])[0]
    count = struct.unpack(order + "H", data[offset:offset + 2])[0]
    sizes = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 11: 4, 12: 8}
    formats = {1: "B", 3: "H", 4: "I", 11: "f", 12: "d"}
    tags = {}
    for i in range(count):
        entry = data[offset + 2 + i * 12:offset + 14 + i * 12]
        tag, kind, n = struct.unpack(order + "HHI", entry[:8])
        total = sizes.get(kind, 1) * n
        raw = (entry[8:12][:total] if total <= 4
               else data[struct.unpack(order + "I", entry[8:12])[0]:][:total])
        fmt = formats.get(kind)
        tags[tag] = list(struct.unpack(order + fmt * n, raw)) if fmt else raw

    if tags.get(258, [0])[0] != 64 or tags.get(339, [0])[0] != 3:
        raise SystemExit("expected 64 bit IEEE float samples")
    if tags.get(259, [1])[0] != 1:
        raise SystemExit("expected an uncompressed raster")
    if tags.get(277, [1])[0] != 1:
        raise SystemExit("expected a single band")

    width, height = tags[256][0], tags[257][0]
    tile_w, tile_h = tags[322][0], tags[323][0]
    grid = [[float("nan")] * width for _ in range(height)]
    across = (width + tile_w - 1) // tile_w
    for i, start in enumerate(tags[324]):
        values = struct.unpack(order + "d" * (tile_w * tile_h),
                               data[start:start + tile_w * tile_h * 8])
        tx, ty = (i % across) * tile_w, (i // across) * tile_h
        for row in range(tile_h):
            y = ty + row
            if y >= height:
                break
            target = grid[y]
            for col in range(min(tile_w, width - tx)):
                target[tx + col] = values[row * tile_w + col]
    return grid, tags[34264]


def _has_value(v):
    # NaN pads the tiles beyond the coverage; -1.0 is the DWD's own
    # "outside the radar composite" marker. Both mean "we do not know",
    # and -1 mm of rain would otherwise quantise to something.
    return v == v and v > -0.5


def crop(grid):
    """Drop the fully empty border rows and columns."""
    height, width = len(grid), len(grid[0])
    rows = [y for y in range(height) if any(_has_value(v) for v in grid[y])]
    cols = [x for x in range(width)
            if any(_has_value(grid[y][x]) for y in range(height))]
    if not rows or not cols:
        raise SystemExit("the coverage came back empty")
    return min(cols), min(rows), max(cols), max(rows)


def _quantise(value):
    if not _has_value(value):
        return NO_DATA
    return min(MAX_MM, max(0, int(round(value))))


def encode(rows):
    """Row-delta, then gzip.

    The delta is what a PNG's Sub filter does, and it buys the same 18 %
    here (255 KB -> 216 KB measured) — without making the app decode an
    image to get at numbers. Undo it with a running sum per row.
    """
    delta = bytearray()
    for row in rows:
        previous = 0
        for byte in row:
            delta.append((byte - previous) & 0xFF)
            previous = byte
    return gzip.compress(bytes(delta), 9)


def build(layer, out_dir, bounds=BOUNDS):
    spec = LAYERS[layer]
    when = default_time(spec["coverage"])
    raw = _fetch(coverage_url(spec["coverage"], when, bounds))
    grid, transform = read_geotiff(raw)
    x0, y0, x1, y1 = crop(grid)
    width, height = x1 - x0 + 1, y1 - y0 + 1

    rows = [bytes(bytearray(_quantise(grid[y][x]) for x in range(x0, x1 + 1)))
            for y in range(y0, y1 + 1)]
    payload = encode(rows)

    # The corner coordinates of the CROPPED grid, in degrees, so the app
    # never has to know about Mercator metres or the tie point.
    step_x, step_y = transform[0], transform[5]
    left = transform[3] + x0 * step_x
    top = transform[7] + y0 * step_y
    right = left + width * step_x
    bottom = top + height * step_y

    values = [v for row in grid for v in row if _has_value(v)]
    entry = {
        "layer": layer,
        "label": spec["label"],
        "coverage": spec["coverage"],
        "measured": when,
        "width": width,
        "height": height,
        "west": round(_to_lon(left), 6),
        "east": round(_to_lon(right), 6),
        "north": round(_to_lat(top), 6),
        "south": round(_to_lat(bottom), 6),
        "file": f"rain_{layer}.bin.gz",
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "max_mm": round(max(values), 1) if values else 0,
        "median_mm": round(sorted(values)[len(values) // 2], 1) if values else 0,
    }

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, entry["file"]), "wb") as handle:
        handle.write(payload)
    return entry


def _rows(grid):
    """Quantise a whole raster, one byte per cell, row by row.

    Its own function so the self-test can reach it: everything around it
    in [build_day] needs the network, and this is where an off-by-one
    would live.
    """
    return [bytes(bytearray(_quantise(v) for v in row)) for row in grid]


def _geometry(transform, width, height):
    """Corner coordinates in degrees for an UNCROPPED raster."""
    left, top = transform[3], transform[7]
    right = left + width * transform[0]
    bottom = top + height * transform[5]
    return {
        "width": width,
        "height": height,
        "west": round(_to_lon(left), 6),
        "east": round(_to_lon(right), 6),
        "north": round(_to_lat(top), 6),
        "south": round(_to_lat(bottom), 6),
    }


def build_day(when, out_dir, bounds=BOUNDS):
    """One day of the stack. **Deliberately not cropped.**

    The other layers drop their empty border, which saves bytes. Here it
    would be poison: measured 2026-08-04, the cropped height varies from
    day to day (891-895 rows) because the edge with data moves. A stack
    whose days have different geometry cannot be read cell by cell, and
    the app would silently compare a spot against a shifted grid. The
    empty rows cost almost nothing after row-delta and gzip — a fully dry
    day came to 3.4 KB.
    """
    raw = _fetch(coverage_url(DAILY["coverage"], when, bounds))
    grid, transform = read_geotiff(raw)
    height, width = len(grid), len(grid[0])
    payload = encode(_rows(grid))
    values = [v for row in grid for v in row if _has_value(v)]
    entry = {
        "date": when[:10],
        "time": when,
        "file": f"rain_day_{when[:10].replace('-', '')}.bin.gz",
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "max_mm": round(max(values), 1) if values else 0,
        "wet_percent": round(100 * sum(1 for v in values if v >= 0.5)
                             / max(1, len(values)), 1),
    }
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, entry["file"]), "wb") as handle:
        handle.write(payload)
    return entry, _geometry(transform, width, height)


def build_daily(out_dir, previous=None, days=None, bounds=BOUNDS,
                times=None, fetch_day=None):
    """The last `days` daily grids — fetching only what is missing.

    A run normally adds ONE day. Rebuilding all twentysix every night
    would be twentysix 8 MB GeoTIFFs for one new file, every night,
    forever. `previous` is the manifest section from the last run; days
    already in it are carried over untouched.

    The geometry is shared by all days and checked against the carried
    ones. If the service ever changes it, everything is rebuilt rather
    than mixed — a stack of two geometries is the failure this whole
    function exists to prevent.
    """
    days = days or DAILY["days"]
    fetch_day = fetch_day or (lambda when: build_day(when, out_dir, bounds))
    wanted = (times if times is not None
              else available_times(DAILY["coverage"]))[-days:]
    if not wanted:
        raise SystemExit("the daily product offers no granules at all")

    known = {entry["date"]: entry
             for entry in (previous or {}).get("days", [])}
    geometry = {key: (previous or {}).get(key)
                for key in ("width", "height", "west", "east", "north", "south")}
    geometry = geometry if all(v is not None for v in geometry.values()) else None

    entries, fresh = [], []
    for when in wanted:
        carried = known.get(when[:10])
        if carried is not None and geometry is not None:
            entries.append(carried)
            continue
        entry, built = fetch_day(when)
        if geometry is None:
            geometry = built
        elif built != geometry:
            # Do not mix. Start over with the new geometry — the carried
            # entries describe files whose cells no longer line up.
            return build_daily(out_dir, previous=None, days=days, bounds=bounds,
                               times=times, fetch_day=fetch_day)
        entries.append(entry)
        fresh.append(entry)

    return {
        "coverage": DAILY["coverage"],
        "label": DAILY["label"],
        **geometry,
        "days": entries,
    }, fresh


def decode(payload, width, height):
    """Undo encode(). The app does exactly this, in Dart."""
    flat = gzip.decompress(payload)
    if len(flat) != width * height:
        raise SystemExit(f"grid is {len(flat)} bytes, expected {width * height}")
    rows = []
    for y in range(height):
        row, previous = bytearray(), 0
        for x in range(width):
            previous = (previous + flat[y * width + x]) & 0xFF
            row.append(previous)
        rows.append(bytes(row))
    return rows


def verify(out_dir, layer, samples=24):
    """Compare the built grid against the service, point by point.

    This exists because of the time-subset trap: a grid built from merged
    granules looks entirely normal — right size, plausible millimetres,
    a sensible-looking map. The only thing that gives it away is asking
    the service what it says at a given spot. Measured 2026-08-04, a
    correct grid lands within its own 3x3 neighbourhood at every sampled
    point; the merged one misses by a factor of two.

    The coordinates are scattered over the grid from a FIXED seed: a
    check that picks new points every night fails on a different one each
    time and turns into noise nobody reads. Same points every run, so a
    failure is reproducible. No user data is involved — this must never
    be pointed at a spot.
    """
    with open(os.path.join(out_dir, "rain_manifest.json")) as handle:
        entry = json.load(handle)["layers"][layer]
    with open(os.path.join(out_dir, entry["file"]), "rb") as handle:
        rows = decode(handle.read(), entry["width"], entry["height"])

    width, height = entry["width"], entry["height"]
    top, bottom = _to_y(entry["north"]), _to_y(entry["south"])
    random.seed(20260804)
    checked, outside, deltas = 0, 0, []
    attempts = 0
    while checked < samples and attempts < samples * 8:
        attempts += 1
        lon = random.uniform(entry["west"] + 0.3, entry["east"] - 0.3)
        lat = random.uniform(entry["south"] + 0.3, entry["north"] - 0.3)
        x = int((lon - entry["west"]) / (entry["east"] - entry["west"]) * width)
        y = int((_to_y(lat) - top) / (bottom - top) * height)
        if rows[y][x] == NO_DATA:
            continue
        near = [rows[j][i]
                for j in range(max(0, y - 1), min(height, y + 2))
                for i in range(max(0, x - 1), min(width, x + 2))
                if rows[j][i] != NO_DATA]
        reference = _feature_info(entry["coverage"], lat, lon)
        if reference is None:
            continue
        checked += 1
        deltas.append(rows[y][x] - reference)
        if not min(near) - 0.5 <= reference <= max(near) + 0.5:
            outside += 1

    if checked < samples // 2:
        raise SystemExit(f"only {checked} points could be checked")
    mean = sum(deltas) / len(deltas)
    worst = max(abs(d) for d in deltas)
    report = (f"- Gegenprobe gegen den Dienst: {checked} Punkte, "
              f"Mittel {mean:+.2f} mm, größter Betrag {worst:.1f} mm, "
              f"{checked - outside}/{checked} in der 3x3-Nachbarschaft\n")
    print(report, end="")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(report)
    # One outlier is a reprojected cell edge. A quarter of them is a
    # different dataset than the service thinks it served.
    if outside > max(2, checked // 5):
        raise SystemExit(
            f"{outside} of {checked} points disagree with the service — "
            "is subset=time(...) still in the request?")


def verify_daily(out_dir, samples=8):
    """Check that each day really is the day it claims to be.

    The stack has a failure mode the single grids do not: ask for the
    wrong date and the values are still plausible rain over Germany, the
    course still looks like weather, and nothing anywhere says otherwise.
    Only the service can tell us — so the comparison passes `time=`, and
    it runs on the OLDEST and the NEWEST day. An off-by-one in the day
    list moves both; a swap shows up in at least one.
    """
    with open(os.path.join(out_dir, "rain_manifest.json")) as handle:
        section = json.load(handle)["daily"]
    days = section["days"]
    if len(days) < 2:
        raise SystemExit("the stack has fewer than two days to check")

    width, height = section["width"], section["height"]
    top, bottom = _to_y(section["north"]), _to_y(section["south"])
    total_checked, total_outside, lines = 0, 0, []
    for day in (days[0], days[-1]):
        path = os.path.join(out_dir, day["file"])
        if not os.path.exists(path):
            # Carried over from an earlier run and not downloaded again.
            lines.append(f"- {day['date']}: nicht lokal, übersprungen\n")
            continue
        with open(path, "rb") as handle:
            rows = decode(handle.read(), width, height)
        random.seed(20260804)
        checked, outside, attempts = 0, 0, 0
        while checked < samples and attempts < samples * 10:
            attempts += 1
            lon = random.uniform(section["west"] + 0.3, section["east"] - 0.3)
            lat = random.uniform(section["south"] + 0.3, section["north"] - 0.3)
            x = int((lon - section["west"])
                    / (section["east"] - section["west"]) * width)
            y = int((_to_y(lat) - top) / (bottom - top) * height)
            if rows[y][x] == NO_DATA:
                continue
            reference = _feature_info(section["coverage"], lat, lon, day["time"])
            if reference is None:
                continue
            checked += 1
            near = [rows[j][i]
                    for j in range(max(0, y - 1), min(height, y + 2))
                    for i in range(max(0, x - 1), min(width, x + 2))
                    if rows[j][i] != NO_DATA]
            if not min(near) - 0.5 <= reference <= max(near) + 0.5:
                outside += 1
        total_checked += checked
        total_outside += outside
        lines.append(f"- {day['date']}: {checked - outside}/{checked} Punkte "
                     f"stimmen mit dem Dienst überein\n")

    report = "".join(lines)
    print(report, end="")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(report)
    if total_checked < samples:
        raise SystemExit(f"only {total_checked} points could be checked")
    if total_outside > max(2, total_checked // 5):
        raise SystemExit(
            f"{total_outside} of {total_checked} points disagree with the "
            "service — is the day being requested the day being stored?")


def _feature_info(coverage, lat, lon, when=None):
    layer = coverage.replace("__", ":")
    x, y = _to_x(lon), _to_y(lat)
    url = ("https://maps.dwd.de/geoserver/dwd/wms?service=WMS&version=1.3.0"
           f"&request=GetFeatureInfo&layers={layer}&query_layers={layer}"
           "&crs=EPSG:3857&info_format=application/json"
           "&width=3&height=3&i=1&j=1"
           + (f"&time={when}" if when else "")
           + f"&bbox={x - 150:.1f},{y - 150:.1f},{x + 150:.1f},{y + 150:.1f}")
    try:
        features = json.loads(_fetch(url, timeout=30))["features"]
        return features[0]["properties"]["GRAY_INDEX"] if features else None
    except Exception:
        return None


_HALF_CIRCUMFERENCE = 20037508.34
_EARTH_RADIUS = 6378137.0


def _to_x(lon):
    return lon * _HALF_CIRCUMFERENCE / 180


def _to_y(lat):
    return _EARTH_RADIUS * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))


def _to_lon(x):
    return x / _HALF_CIRCUMFERENCE * 180


def _to_lat(y):
    return math.degrees(2 * math.atan(math.exp(y / _EARTH_RADIUS)) - math.pi / 2)


def self_test():
    """Everything that does not need the network.

    Runs in CI next to the real build (see .github/workflows/rain-data.yml)
    so it cannot rot the way an unrun script does.
    """
    # Round trip of the encoding — this is the format the app must undo.
    # Includes a row that ends high and one that starts low, because the
    # bug this catches is forgetting to reset the running sum per row:
    # that still decodes row 0 correctly and corrupts everything after.
    rows = [bytes([0, 5, 5, 200, NO_DATA]), bytes([NO_DATA, 1, 0, 0, 7]),
            bytes([7, 7, 7, 7, 7])]
    assert decode(encode(rows), 5, 3) == rows, decode(encode(rows), 5, 3)
    try:
        decode(encode(rows), 4, 3)
    except SystemExit:
        pass
    else:
        raise AssertionError("a grid of the wrong size was accepted")

    # Quantisation: the two "no data" spellings, the clamp, and rounding.
    assert _quantise(float("nan")) == NO_DATA
    assert _quantise(-1.0) == NO_DATA
    assert _quantise(0.0) == 0
    assert _quantise(37.4) == 37
    assert _quantise(37.6) == 38
    assert _quantise(1e9) == MAX_MM

    # The projection helpers. Not against numbers copied out of this same
    # code — that proves nothing. Against two things from outside it: the
    # documented corner of the Web Mercator square (180 deg / 85.051129
    # deg, the definition of EPSG:3857), and a second, algebraically
    # different spelling of the same inverse. A typo in one of them
    # cannot survive both.
    assert abs(_to_lon(_HALF_CIRCUMFERENCE) - 180) < 1e-6
    assert abs(_to_lat(_HALF_CIRCUMFERENCE) - 85.051129) < 1e-5, \
        _to_lat(_HALF_CIRCUMFERENCE)
    assert abs(_to_lat(0.0)) < 1e-9
    for y in (-8_000_000.0, -1.0, 1234.5, 6_674_000.53, 12_000_000.0):
        other = math.degrees(math.asin(math.tanh(y / _EARTH_RADIUS)))
        assert abs(_to_lat(y) - other) < 1e-9, (y, _to_lat(y), other)

    # The time subset must be in every request. This is the silent-wrong
    # case from the module docstring, so it gets an assertion rather than
    # a comment.
    url = coverage_url("dwd__RADOLAN-W4", "2026-08-03T05:50:00.000Z", BOUNDS)
    assert 'subset=time("2026-08-03T05:50:00.000Z")' in url, url
    assert "outputCrs" in url and "3857" in url

    # The GeoTIFF reader, against a raster this file builds itself. Two
    # tiles wide so the tile-to-grid mapping is actually exercised, and
    # not square, so a transposed index cannot pass.
    values = [[1.5, 2.5, 3.5, 4.5, 5.5],
              [6.5, 7.5, 8.5, 9.5, 10.5],
              [11.5, 12.5, 13.5, 14.5, 15.5]]
    grid, transform = read_geotiff(_fake_tiff(values, 4, 2))
    assert [row[:5] for row in grid[:3]] == values, grid
    assert transform[3] == 100.0 and transform[7] == 900.0, transform

    # Anything this reader was not written for must be refused rather
    # than decoded into numbers that look fine and are not.
    for label, kwargs in (
        ("32 bit floats", {"bits": 32}),
        ("integer samples", {"sample_format": 2}),
        ("LZW compression", {"compression": 5}),
        ("three bands", {"samples": 3}),
    ):
        try:
            read_geotiff(_fake_tiff(values, 4, 2, **kwargs))
        except SystemExit:
            continue
        raise AssertionError(f"{label} was accepted")
    for bad in (b"<?xml version=", b""):
        try:
            read_geotiff(bad)
        except SystemExit:
            continue
        raise AssertionError("a non-TIFF was accepted")

    _self_test_daily()
    print("rain_grid self-test: ok")


def _self_test_daily():
    """The daily stack, without touching the network."""
    domain = ("""<wcsgs:TimeDomain default="2026-08-03T00:00:00.000Z">
      <gml:TimeInstant><gml:timePosition>2026-08-03T00:00:00.000Z"""
              """</gml:timePosition></gml:TimeInstant>
      <gml:TimeInstant><gml:timePosition>2026-08-01T00:00:00.000Z"""
              """</gml:timePosition></gml:TimeInstant>
    </wcsgs:TimeDomain>""")
    assert _parse_times(domain) == ["2026-08-01T00:00:00.000Z",
                                    "2026-08-03T00:00:00.000Z"], \
        "the time domain must come back sorted, oldest first"
    try:
        _parse_times("<wcsgs:TimeDomain/>")
    except SystemExit:
        pass
    else:
        raise AssertionError("an empty time domain was accepted")

    # Geometry of an UNCROPPED raster: north-west corner from the tie
    # point, the other two by stepping. Checked against degrees, because
    # that is what the app gets.
    # Raster to bytes: every row, every cell, both spellings of no data
    # and the clamp. Two rows of three, so a dropped row shows.
    raster = [[0.4, 1.6, float("nan")], [-1.0, 300.0, 2.0]]
    assert _rows(raster) == [bytes([0, 2, NO_DATA]),
                             bytes([NO_DATA, MAX_MM, 2])], _rows(raster)

    # Width and height are deliberately different (4 x 2): with a square
    # test raster, swapping them would go unnoticed.
    left, top = _to_x(6.0), _to_y(55.0)
    geo = _geometry([1000.0, 0, 0, left, 0, -1000.0, 0, top], 4, 2)
    assert geo["width"] == 4 and geo["height"] == 2
    assert abs(geo["west"] - 6.0) < 1e-6, geo
    assert abs(geo["north"] - 55.0) < 1e-6, geo
    assert abs(geo["east"] - round(_to_lon(left + 4 * 1000.0), 6)) < 1e-9, geo
    assert abs(geo["south"] - round(_to_lat(top - 2 * 1000.0), 6)) < 1e-9, geo

    # The stack: only missing days are fetched, and only the last N kept.
    times = [f"2026-07-{day:02d}T00:00:00.000Z" for day in range(20, 30)]
    shape = {"width": 4, "height": 2, "west": 6.0, "east": 6.1,
             "north": 55.0, "south": 54.9}
    calls = []

    def fake(when, geometry=shape):
        calls.append(when[:10])
        return {"date": when[:10], "time": when,
                "file": f"rain_day_{when[:10].replace('-', '')}.bin.gz",
                "bytes": 1, "sha256": "x", "max_mm": 0, "wet_percent": 0.0}, \
            dict(geometry)

    section, fresh = build_daily(".", previous=None, days=3, times=times,
                                 fetch_day=fake)
    assert [d["date"] for d in section["days"]] == \
        ["2026-07-27", "2026-07-28", "2026-07-29"], section["days"]
    assert len(fresh) == 3 and len(calls) == 3

    calls.clear()
    times.append("2026-07-30T00:00:00.000Z")
    section2, fresh2 = build_daily(".", previous=section, days=3, times=times,
                                   fetch_day=fake)
    assert calls == ["2026-07-30"], \
        f"a day already in the manifest was fetched again: {calls}"
    assert [d["date"] for d in section2["days"]] == \
        ["2026-07-28", "2026-07-29", "2026-07-30"], section2["days"]
    assert len(fresh2) == 1

    # A changed geometry must discard the carried days rather than mix
    # two rasters in one stack — the whole reason this stack is not
    # cropped per day. It can only show up on a day that is actually
    # fetched, so the run needs a new one; a run that fetches nothing
    # changes nothing, and that is correct.
    calls.clear()
    times.append("2026-07-31T00:00:00.000Z")
    moved = dict(shape, height=3)
    section3, _ = build_daily(".", previous=section2, days=3, times=times,
                              fetch_day=lambda when: fake(when, moved))
    assert calls == ["2026-07-31",
                     "2026-07-29", "2026-07-30", "2026-07-31"], \
        f"the stack was not rebuilt after the geometry changed: {calls}"
    assert section3["height"] == 3, section3
    assert [d["date"] for d in section3["days"]] == \
        ["2026-07-29", "2026-07-30", "2026-07-31"], section3["days"]


def _fake_tiff(values, tile_w, tile_h, bits=64, sample_format=3,
               compression=1, samples=1):
    """A minimal big-endian tiled TIFF, for the self-test only."""
    height, width = len(values), len(values[0])
    across = (width + tile_w - 1) // tile_w
    down = (height + tile_h - 1) // tile_h
    tiles = []
    for ty in range(down):
        for tx in range(across):
            cells = []
            for row in range(tile_h):
                for col in range(tile_w):
                    y, x = ty * tile_h + row, tx * tile_w + col
                    cells.append(values[y][x] if y < height and x < width
                                 else 0.0)
            tiles.append(struct.pack(">" + "d" * len(cells), *cells))

    transform = [1.0, 0, 0, 100.0, 0, -1.0, 0, 900.0] + [0.0] * 8
    entries = [(256, 4, [width]), (257, 4, [height]), (258, 3, [bits]),
               (259, 3, [compression]), (262, 3, [1]), (277, 3, [samples]),
               (322, 3, [tile_w]), (323, 3, [tile_h]),
               (324, 4, None), (325, 4, [len(t) for t in tiles]),
               (339, 3, [sample_format]), (34264, 12, transform)]
    sizes = {3: 2, 4: 4, 12: 8}
    ifd_end = 8 + 2 + len(entries) * 12 + 4
    extra, offsets = bytearray(), {}
    for tag, kind, payload in entries:
        if payload is None or sizes[kind] * len(payload) <= 4:
            continue
        offsets[tag] = ifd_end + len(extra)
        extra += struct.pack(">" + {3: "H", 4: "I", 12: "d"}[kind] * len(payload),
                             *payload)
    tile_start = ifd_end + len(extra) + 4 * len(tiles)
    positions, cursor = [], tile_start
    for tile in tiles:
        positions.append(cursor)
        cursor += len(tile)
    offsets[324] = ifd_end + len(extra)
    extra += struct.pack(">" + "I" * len(positions), *positions)

    ifd = struct.pack(">H", len(entries))
    for tag, kind, payload in entries:
        data = positions if tag == 324 else payload
        if tag in offsets:
            field = struct.pack(">I", offsets[tag])
        else:
            packed = struct.pack(">" + {3: "H", 4: "I", 12: "d"}[kind] * len(data),
                                 *data)
            field = packed.ljust(4, b"\0")
        ifd += struct.pack(">HHI", tag, kind, len(data)) + field
    ifd += struct.pack(">I", 0)
    return b"MM\x00\x2a" + struct.pack(">I", 8) + ifd + bytes(extra) + b"".join(tiles)


def _build_daily_cli(args, manifest, manifest_path):
    section, fresh = build_daily(args.out, previous=manifest.get("daily"),
                                 days=args.days)
    manifest["daily"] = section
    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)

    total = sum(day["bytes"] for day in section["days"])
    summary = (
        f"### Tagesraster ({len(section['days'])} Tage)\n\n"
        f"- Zeitraum: {section['days'][0]['date']} bis "
        f"{section['days'][-1]['date']}\n"
        f"- Neu geholt: {len(fresh)} "
        f"({', '.join(day['date'] for day in fresh) if fresh else 'nichts'})\n"
        f"- Gitter: {section['width']} x {section['height']} Zellen, "
        f"ungeschnitten (feste Geometrie für den ganzen Stapel)\n"
        f"- Stapel gesamt: {total / 1024:.0f} KB\n"
    )
    for day in section["days"]:
        summary += (f"  - {day['date']}: {day['bytes'] / 1024:.1f} KB, "
                    f"{day['wet_percent']} % nass, max {day['max_mm']} mm\n")
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(summary)

    # Which day files the stack still needs, so the workflow can delete
    # the rest from the release. Named here rather than guessed there:
    # this function knows what the stack keeps, a shell glob does not.
    # Written NEXT TO the output directory, not into it — everything in
    # there gets uploaded as an asset.
    keep = sorted(day["file"] for day in section["days"])
    with open(os.path.join(os.path.dirname(args.out) or ".", "keep.txt"),
              "w") as handle:
        handle.write("\n".join(keep) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layer", choices=sorted(LAYERS) + ["daily"])
    parser.add_argument("--out", default="build/rain")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verify", action="store_true",
                        help="compare the built grid against the live service")
    parser.add_argument("--days", type=int, default=DAILY["days"],
                        help="how many days the stack keeps (--layer daily)")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if not args.layer:
        parser.error("--layer is required unless --self-test is given")
    if args.verify:
        verify_daily(args.out) if args.layer == "daily" \
            else verify(args.out, args.layer)
        return

    manifest_path = os.path.join(args.out, "rain_manifest.json")
    manifest = {"layers": {}}
    if os.path.exists(manifest_path):
        with open(manifest_path) as handle:
            manifest = json.load(handle)

    if args.layer == "daily":
        _build_daily_cli(args, manifest, manifest_path)
        return

    entry = build(args.layer, args.out)
    manifest.setdefault("layers", {})[args.layer] = entry
    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)

    summary = (
        f"### Regen-Gitter `{args.layer}`\n\n"
        f"- Messzeitpunkt: `{entry['measured']}`\n"
        f"- Gitter: {entry['width']} x {entry['height']} Zellen "
        f"({entry['west']}..{entry['east']} / "
        f"{entry['south']}..{entry['north']})\n"
        f"- Werte: Median {entry['median_mm']} mm, Maximum "
        f"{entry['max_mm']} mm"
        + (" — **am Deckel von 254 mm abgeschnitten**"
           if entry["max_mm"] >= MAX_MM else "")
        + f"\n- Datei: {entry['bytes'] / 1024:.0f} KB gepackt\n"
    )
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(summary)


if __name__ == "__main__":
    sys.exit(main())
