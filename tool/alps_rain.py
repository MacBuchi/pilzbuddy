#!/usr/bin/env python3
"""Measured daily rain for the Alps, blended across borders (#646).

Beyond Germany the app had only the weather model (tool/model_weather.py).
Austria, Switzerland and Italy each publish a measured daily grid, and
docs/regendaten-alpenraum.md picked one per country:

    Austria                  GeoSphere INCA, hourly, summed to UTC days
    Switzerland, Liechtenst. MeteoSwiss RprelimD (06-06 UTC days)
    Italy                    DPC "Merging" CUM24 (radar + gauges)

Each is fetched onto ONE grid (1 km in Web Mercator over the model box)
and kept as its own day file. Then the sources are BLENDED into a single
day grid, `alps_rain_<YYYYMMDD>.bin.gz` — and that blend is the point of
this tool. Taking "the first source with a value" would put a hard edge
on every border, in the map's rain sums AND in the Ampel, because both
read the same stack. Blending in CI rather than on the phone keeps it to
ONE rule in one place; the app only adds this stack in front of the
radar and the model (national > DWD radar > model, docs §Empfehlung).

How the blend works:

  1. Every cell has an OWNER: the country it lies in (Natural Earth, see
     `MASK_FILE`). Germany owns it for the DWD radar, Austria for INCA,
     Switzerland and Liechtenstein for RprelimD, Italy for DPC, every
     other country for the model.
  2. Two shifts before blurring. DPC is worthless outside Italy (0.38 of
     INCA in Austria, 0.44 of RprelimD in Switzerland), so Italy's border
     band is handed to its neighbours and DPC's weight reaches zero AT
     the border. And the model is the weakest source, so the measured
     countries reach into their non-measured neighbours by the same band
     — the model's weight is zero inside Germany, Austria, Switzerland.
  3. The owner map is blurred, one indicator per source (three box
     passes ~ a Gaussian, sigma ~6 km). Blurring a partition of unity
     gives a partition of unity: the weights sum to 1 in every cell, so
     two sources can never add up — the "no double counting" property,
     tested with identical inputs on the real mask.
  4. Where a source has no data on a day, its weight fades out over the
     same distance instead of dropping to zero at the data edge
     (`feather`). Its weight goes to the other measured sources first,
     and to the model only where no measured source is left.

Licence: DPC is CC BY-SA, so the blended file is CC BY-SA 4.0 as a whole
(decision of the operator, 2026-10-01; the CC BY inputs may be adapted
under BY-SA). The per-source DPC files stay separate (`it_rain_*`).

GDAL (`gdalwarp`) only reprojects here; every sum and the blend are this
file, stdlib only, like tool/rain_grid.py.

Usage:
    python3 tool/alps_rain.py --out build/rain --inputs build/inputs
    python3 tool/alps_rain.py --verify --out build/rain --inputs build/inputs
    python3 tool/alps_rain.py --self-test                  # no network
    python3 tool/alps_rain.py --build-mask ne_10m_admin_0_countries.zip
"""
import argparse
import array
import collections
import datetime as dt
import gzip
import hashlib
import io
import itertools
import json
import math
import operator
import os
import random
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOL_DIR)

import model_weather  # noqa: E402  (after the path tweak)
import rain_grid  # noqa: E402

BOX = model_weather.BOX                 # the model's Alpine box
CELL_M = 1000                           # Mercator metres, like the radar stack
NO_DATA = rain_grid.NO_DATA
STACK_DAYS = model_weather.STACK_DAYS   # 30, the app's longest rain sum
# Days fetched again even when present: DPC recomputes a day when late
# gauge data arrives, INCA fills late station hours.
REFRESH_DAYS = 2

# Owner codes in the mask.
OTHER, DE, AT, CH, IT = 0, 1, 2, 3, 4
COUNTRY_CODES = {"DEU": DE, "AUT": AT, "CHE": CH, "LIE": CH, "ITA": IT}
MASK_FILE = os.path.join(TOOL_DIR, "alps_countries.bin.gz")
# Natural Earth 1:10m admin-0 countries v5.1.1, public domain, rasterised
# by `--build-mask`. Pinned so a regenerated mask is a visible change.
MASK_SHA256 = "b5450cf0526bc8896548aa746413389cf155cea09014f88031810654510a7b36"

# One box pass is BLUR_BOX cells wide; three passes reach REACH cells.
# A Mercator cell is ~0.68 km on the ground here, so the crossfade runs
# over ~32 km, ~15 km of it between 10 % and 90 %.
BLUR_BOX = 17
BLUR_PASSES = 3
REACH = BLUR_PASSES * (BLUR_BOX // 2)   # 24 cells
SHIFT = REACH                           # how far a band is handed over
FEATHER = REACH                         # fade at a source's data edge

MEASURED = ("inca", "rprelimd", "dpc", "radar")
NATIONAL = ("inca", "rprelimd", "dpc")
OWNER_OF = {"radar": DE, "inca": AT, "rprelimd": CH, "dpc": IT}
# Bits of the origin plane: which sources carry at least SHARE_MIN of a
# cell's value. The app names them in the spot sheet.
SOURCE_BITS = {"inca": 1, "rprelimd": 2, "dpc": 4, "radar": 8, "model": 16}
SHARE_MIN = 0.05

SOURCES = {
    "inca": {
        "file": "at_rain_{}.bin.gz",
        "label": "GeoSphere Austria, INCA",
        "licence": "CC BY 4.0",
        "doi": "10.60669/6akt-5p05",
    },
    "rprelimd": {
        "file": "ch_rain_{}.bin.gz",
        "label": "Quelle: MeteoSchweiz, RprelimD",
        "licence": "CC BY 4.0",
    },
    "dpc": {
        "file": "it_rain_{}.bin.gz",
        "label": "Radar-DPC, Merging CUM24",
        "licence": "CC BY-SA 4.0",
    },
}
BLEND_FILE = "alps_rain_{}.bin.gz"
ORIGIN_FILE = "alps_origin_{}.bin.gz"
KEEP_FILE = "alps_keep.txt"
ATTRIBUTION = [
    "GeoSphere Austria (CC BY 4.0, https://doi.org/10.60669/6akt-5p05)",
    "Quelle: MeteoSchweiz (CC BY 4.0)",
    "Radar-DPC (CC BY-SA 4.0)",
    "Deutscher Wetterdienst (GeoNutzV)",
    "Open-Meteo (CC BY 4.0)",
]

INCA_API = "https://dataset.api.hub.geosphere.at/v1/grid/historical/inca-v1-1h-1km"
INCA_BBOX = "45.77,8.1,49.48,17.74"     # south,west,north,east: the domain
SPARTACUS_API = ("https://dataset.api.hub.geosphere.at/v1/grid/historical/"
                 "spartacus-v3-1d-1km")
SPARTACUS_BBOX = "46.16,9.39,49.18,17.38"
STAC_ITEM = ("https://data.geo.admin.ch/api/stac/v1/collections/"
             "ch.meteoschweiz.ogd-surface-derived-grid/items/{}-ch")
DPC_API = "https://radar-api.protezionecivile.it/downloadProduct"
DPC_ORIGIN = "https://mappe.protezionecivile.gov.it"


# ------------------------------------------------------------- geometry

def geometry_of(box=BOX, cell_m=CELL_M):
    """The blend grid — the same arithmetic as `model_weather.lattice`,
    without building 725 000 centre tuples. Returns the manifest geometry
    and the Mercator extent (x0, y_bottom, x1, y_top) for gdalwarp."""
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
    extent = (x0, y_top - height * cell_m, x0 + width * cell_m, y_top)
    return geometry, extent


def cell_of(geometry, lat, lon):
    return model_weather.cell_index(geometry, lat, lon)


def _centres(geometry):
    """Latitude per row and longitude per column of the cell centres.
    Separable because the grid is axis-aligned in Mercator."""
    w, h = geometry["width"], geometry["height"]
    x0, x1 = rain_grid._to_x(geometry["west"]), rain_grid._to_x(geometry["east"])
    yt, yb = rain_grid._to_y(geometry["north"]), rain_grid._to_y(geometry["south"])
    lons = [rain_grid._to_lon(x0 + (c + 0.5) * (x1 - x0) / w) for c in range(w)]
    lats = [rain_grid._to_lat(yt - (r + 0.5) * (yt - yb) / h) for r in range(h)]
    return lats, lons


# ------------------------------------------------------------ the mask

def _dbf_records(data):
    count = struct.unpack("<I", data[4:8])[0]
    header_len, record_len = struct.unpack("<HH", data[8:12])
    fields, pos = [], 32
    while data[pos] != 0x0D:
        name = data[pos:pos + 11].split(b"\0")[0].decode("ascii")
        fields.append((name, data[pos + 16]))
        pos += 32
    records = []
    for i in range(count):
        start = header_len + i * record_len + 1   # skip the deletion flag
        row, cursor = {}, start
        for name, length in fields:
            row[name] = data[cursor:cursor + length].decode(
                "utf-8", "replace").strip()
            cursor += length
        records.append(row)
    return records


def _shp_polygons(data):
    """Rings of every polygon record, in file order (None for null shapes)."""
    shapes, pos = [], 100
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos + 4:pos + 8])[0] * 2
        content = data[pos + 8:pos + 8 + length]
        pos += 8 + length
        kind = struct.unpack("<i", content[:4])[0]
        if kind == 0:
            shapes.append(None)
            continue
        if kind != 5:
            raise SystemExit(f"expected polygons in the shapefile, got type {kind}")
        parts, points = struct.unpack("<ii", content[36:44])
        starts = list(struct.unpack(f"<{parts}i", content[44:44 + 4 * parts]))
        base = 44 + 4 * parts
        coords = struct.unpack(f"<{2 * points}d", content[base:base + 16 * points])
        xy = list(zip(coords[0::2], coords[1::2]))
        ends = starts[1:] + [points]
        shapes.append([xy[a:b] for a, b in zip(starts, ends)])
    return shapes


def read_countries(zip_path_or_bytes):
    """{owner code: [rings]} for the countries this tool cares about."""
    source = (io.BytesIO(zip_path_or_bytes)
              if isinstance(zip_path_or_bytes, bytes) else zip_path_or_bytes)
    with zipfile.ZipFile(source) as archive:
        names = archive.namelist()
        shp = archive.read(next(n for n in names if n.endswith(".shp")))
        dbf = archive.read(next(n for n in names if n.endswith(".dbf")))
    records, shapes = _dbf_records(dbf), _shp_polygons(shp)
    if len(records) != len(shapes):
        raise SystemExit(f"{len(records)} records but {len(shapes)} shapes")
    rings = collections.defaultdict(list)
    for record, shape in zip(records, shapes):
        code = COUNTRY_CODES.get(record.get("ADM0_A3"))
        if code is not None and shape:
            rings[code].extend(shape)
    return rings


def rasterise(rings_by_code, geometry):
    """Owner code per cell centre, even-odd rule, one scanline per row.

    Rings outside the box are dropped whole: their crossings on a row come
    in pairs of their own and never interleave with a ring inside it.
    """
    w, h = geometry["width"], geometry["height"]
    lats, lons = _centres(geometry)
    owner = bytearray(w * h)
    lat_top, lat_bottom = lats[0], lats[-1]
    for code, rings in rings_by_code.items():
        per_row = collections.defaultdict(list)
        for ring in rings:
            ys = [p[1] for p in ring]
            xs = [p[0] for p in ring]
            if (max(ys) < lat_bottom or min(ys) > lat_top
                    or max(xs) < geometry["west"] or min(xs) > geometry["east"]):
                continue
            for (x0, y0), (x1, y1) in zip(ring, ring[1:] + ring[:1]):
                if y0 == y1:
                    continue
                lo, hi = min(y0, y1), max(y0, y1)
                # Rows whose centre latitude lies in [lo, hi): lats fall
                # with the row index, so walk from the top.
                for r in _rows_between(lats, lo, hi):
                    lat = lats[r]
                    per_row[r].append(x0 + (lat - y0) * (x1 - x0) / (y1 - y0))
        for r, crossings in per_row.items():
            crossings.sort()
            for a, b in zip(crossings[0::2], crossings[1::2]):
                for c in _cols_between(lons, a, b):
                    owner[r * w + c] = code
    return owner


def _rows_between(lats, lo, hi):
    """Indices r with lo <= lats[r] < hi; lats is descending."""
    n = len(lats)
    first = _bisect_desc(lats, hi)          # first index with lat < hi
    r = first
    while r < n and lats[r] >= lo:
        yield r
        r += 1


def _bisect_desc(values, limit):
    lo, hi = 0, len(values)
    while lo < hi:
        mid = (lo + hi) // 2
        if values[mid] >= limit:
            lo = mid + 1
        else:
            hi = mid
    return lo


def _cols_between(lons, a, b):
    """Indices c with a <= lons[c] < b; lons is ascending."""
    lo, hi = 0, len(lons)
    while lo < hi:
        mid = (lo + hi) // 2
        if lons[mid] < a:
            lo = mid + 1
        else:
            hi = mid
    c = lo
    while c < len(lons) and lons[c] < b:
        yield c
        c += 1


def build_mask(zip_path, out=MASK_FILE):
    geometry, _ = geometry_of()
    owner = rasterise(read_countries(zip_path), geometry)
    rows = [bytes(owner[r * geometry["width"]:(r + 1) * geometry["width"]])
            for r in range(geometry["height"])]
    payload = rain_grid.encode(rows)
    with open(out, "wb") as handle:
        handle.write(payload)
    counts = collections.Counter(owner)
    print(f"{out}: {len(payload)} bytes, sha256 "
          f"{hashlib.sha256(payload).hexdigest()}")
    print("cells per owner:", {k: counts[k] for k in sorted(counts)})


def load_mask(path=MASK_FILE, check=True):
    geometry, _ = geometry_of()
    with open(path, "rb") as handle:
        payload = handle.read()
    if check and hashlib.sha256(payload).hexdigest() != MASK_SHA256:
        raise SystemExit(f"{path} does not match MASK_SHA256 — regenerated "
                         "without updating the pin?")
    rows = rain_grid.decode(payload, geometry["width"], geometry["height"])
    return geometry, bytearray(b"".join(rows))


# ----------------------------------------------------------- weights

_NEIGHBOURS = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))


def spread(owner, width, height, seeds, targets, steps):
    """Cells whose code is in `targets` and that lie within `steps` cells
    (8-neighbourhood) of a cell whose code is in `seeds` take the code of
    the nearest such seed. Breadth first, so "nearest" is exact and ties
    go the same way every run."""
    out = bytearray(owner)
    depth = bytearray(width * height)
    queue = collections.deque(i for i in range(width * height) if owner[i] in seeds)
    while queue:
        i = queue.popleft()
        d = depth[i]
        if d >= steps:
            continue
        y, x = divmod(i, width)
        code = out[i]
        for dy, dx in _NEIGHBOURS:
            yy, xx = y + dy, x + dx
            if 0 <= yy < height and 0 <= xx < width:
                j = yy * width + xx
                if owner[j] in targets and out[j] == owner[j] and depth[j] == 0:
                    out[j] = code
                    depth[j] = d + 1
                    queue.append(j)
    return out


def _box_pass(values, n, stride, count, box):
    """One running box sum along rows (stride 1) or columns, edges
    clamped. Integer in, integer out: the partition of unity stays exact
    until the one division at the end."""
    r = box // 2
    out = [0] * len(values)
    for line in range(count):
        start = line * (n if stride == 1 else 1)
        step = stride
        seq = values[start:start + n * step:step] if step != 1 else values[start:start + n]
        padded = [seq[0]] * (r + 1) + list(seq) + [seq[-1]] * r
        sums = list(itertools.accumulate(padded))
        smoothed = [sums[i + box] - sums[i] for i in range(n)]
        if step == 1:
            out[start:start + n] = smoothed
        else:
            out[start:start + n * step:step] = smoothed
    return out


def blur(indicator, width, height, box=BLUR_BOX, passes=BLUR_PASSES):
    """Separable box blur, `passes` times each way, as floats in [0, 1]."""
    values = list(indicator)
    for _ in range(passes):
        values = _box_pass(values, width, 1, height, box)
    for _ in range(passes):
        values = _box_pass(values, height, width, width, box)
    scale = float(box ** (2 * passes))
    return [v / scale for v in values]


def ownership(owner, width, height, shift=SHIFT):
    """The owner map after the two hand-overs described in the module
    docstring: Italy's border band goes to whoever is across the border,
    and the measured countries reach into the model's cells.

    In this order: at the Carinthian tripoint, Italy's band went to
    Slovenia — model cells, created AFTER the measured countries had
    reached out, so the model leaked back into Austria (the self-test
    found it at 46.61° N 13.52° O)."""
    handed = spread(owner, width, height, seeds={OTHER, DE, AT, CH},
                    targets={IT}, steps=shift)
    return spread(handed, width, height, seeds={DE, AT, CH},
                  targets={OTHER}, steps=shift)


def static_weights(owner, width, height):
    """Blurred ownership per source, plus the cells the blend stores."""
    owned = ownership(owner, width, height)
    weights = {}
    for name, code in list(OWNER_OF.items()) + [("model", OTHER)]:
        weights[name] = blur(bytes(1 if v == code else 0 for v in owned),
                             width, height)
    # Inside Germany a cell no national source touches is pure radar:
    # the radar stack already says that, so the blend leaves it empty
    # and the app falls through to the radar — with the same byte.
    active = array.array("i", (
        i for i in range(width * height)
        if owner[i] != DE or any(weights[n][i] > 0 for n in NATIONAL)))
    return weights, active


def feather(grid, width, height, reach=FEATHER):
    """1 deep inside a source's data, fading to 0 at its edge (NO_DATA
    cells are 0). Distance by breadth first search from the gaps; the
    edge of the grid is not a gap — the data goes on beyond it."""
    n = width * height
    depth = array.array("h", [-1]) * n
    queue = collections.deque()
    for i in range(n):
        if grid[i] == NO_DATA:
            depth[i] = 0
            queue.append(i)
    while queue:
        i = queue.popleft()
        d = depth[i]
        if d >= reach:
            continue
        y, x = divmod(i, width)
        for dy, dx in _NEIGHBOURS:
            yy, xx = y + dy, x + dx
            if 0 <= yy < height and 0 <= xx < width:
                j = yy * width + xx
                if depth[j] < 0:
                    depth[j] = d + 1
                    queue.append(j)
    return [1.0 if d < 0 else _smoothstep(d / reach) for d in depth]


def _smoothstep(t):
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------- blend

def blend(layers, model, weights, active, width, height):
    """One day. `layers`: name -> bytes on the grid (NO_DATA = missing)
    or None for a source absent that day; `model`: floats or None per
    cell, or None. Returns (value bytes, origin bytes).

    Value = measured sources normalised among themselves, crossfaded into
    the model by how much measured weight is left. A convex combination
    everywhere: never above the largest input, never below the smallest,
    and identical inputs give that input back."""
    n = width * height
    present = [name for name in MEASURED if layers.get(name) is not None]
    wf = {}
    for name in present:
        grid = layers[name]
        fade = feather(grid, width, height)
        static = weights[name]
        wf[name] = [s * f for s, f in zip(static, fade)]
    values = bytearray([NO_DATA]) * n
    origin = bytearray(n)
    for i in active:
        total, weighted = 0.0, 0.0
        for name in present:
            k = wf[name][i]
            if k > 0:
                v = layers[name][i]
                if v != NO_DATA:
                    total += k
                    weighted += k * v
        m = model[i] if model is not None else None
        if total > 0:
            measured = weighted / total
            alpha = 1.0 if m is None else _smoothstep(total)
            value = alpha * measured + (1 - alpha) * (m if m is not None else 0)
        elif m is not None:
            alpha, value = 0.0, m
        else:
            continue
        values[i] = min(rain_grid.MAX_MM, max(0, int(round(value))))
        bits = 0
        if total > 0:
            for name in present:
                k = wf[name][i]
                if k > 0 and layers[name][i] != NO_DATA \
                        and alpha * k / total >= SHARE_MIN:
                    bits |= SOURCE_BITS[name]
        if 1 - alpha >= SHARE_MIN:
            bits |= SOURCE_BITS["model"]
        origin[i] = bits
    return values, origin


def sample_nearest(grid, source_geometry, geometry):
    """A day of another 1-byte grid on the blend grid, nearest cell — the
    same lookup as `RainGrid.mmAt`, so a pure-radar cell here carries the
    byte the app would read from the radar stack itself."""
    w, h = geometry["width"], geometry["height"]
    lats, lons = _centres(geometry)
    sg = source_geometry
    sw, sh = sg["width"], sg["height"]
    top, bottom = rain_grid._to_y(sg["north"]), rain_grid._to_y(sg["south"])
    cols = [math.floor((lon - sg["west"]) / (sg["east"] - sg["west"]) * sw)
            for lon in lons]
    rows = [math.floor((rain_grid._to_y(lat) - top) / (bottom - top) * sh)
            for lat in lats]
    out = bytearray([NO_DATA]) * (w * h)
    for r, sr in enumerate(rows):
        if not 0 <= sr < sh:
            continue
        base = sr * sw
        for c, sc in enumerate(cols):
            if 0 <= sc < sw:
                out[r * w + c] = grid[base + sc]
    return out


def sample_bilinear(grid, source_geometry, geometry):
    """The 12 km model on the 1 km grid, bilinear between cell centres
    and renormalised over the corners that have a value — 12 km blocks
    would be an edge of their own."""
    w, h = geometry["width"], geometry["height"]
    lats, lons = _centres(geometry)
    sg = source_geometry
    sw, sh = sg["width"], sg["height"]
    sx0, sx1 = rain_grid._to_x(sg["west"]), rain_grid._to_x(sg["east"])
    st, sb = rain_grid._to_y(sg["north"]), rain_grid._to_y(sg["south"])
    fx = [(rain_grid._to_x(lon) - sx0) / (sx1 - sx0) * sw - 0.5 for lon in lons]
    fy = [(st - rain_grid._to_y(lat)) / (st - sb) * sh - 0.5 for lat in lats]
    out = [None] * (w * h)
    for r, y in enumerate(fy):
        j0 = math.floor(y)
        ty = y - j0
        for c, x in enumerate(fx):
            i0 = math.floor(x)
            tx = x - i0
            total = weight = 0.0
            for dj, wy in ((0, 1 - ty), (1, ty)):
                jj = min(max(j0 + dj, 0), sh - 1)
                for di, wx in ((0, 1 - tx), (1, tx)):
                    ii = min(max(i0 + di, 0), sw - 1)
                    v = grid[jj * sw + ii]
                    if v != NO_DATA and wx * wy > 0:
                        total += wx * wy * v
                        weight += wx * wy
            if weight > 0:
                out[r * w + c] = total / weight
    return out


# ---------------------------------------------------- reading rasters

class Gdal:
    """The two GDAL programs this tool calls. `gdalwarp` reprojects onto
    the blend grid — Float64, tiled, uncompressed, band interleaved, the
    one shape `sum_bands` reads. `gdalinfo` reports a band's scale and
    offset. Everything computed from the numbers happens in Python.

    A class so the self-test and a local trial can stand in for GDAL."""

    def __init__(self, run=subprocess.run):
        self.run = run

    def _config(self, bottom_up):
        return [] if bottom_up is None else \
            ["--config", "GDAL_NETCDF_BOTTOMUP", bottom_up]

    def warp(self, src, geometry, extent, s_srs=None, srcnodata=None,
             bottom_up=None):
        with tempfile.TemporaryDirectory() as tmp:
            dst = os.path.join(tmp, "warped.tif")
            cmd = ["gdalwarp", "-q", "-overwrite", *self._config(bottom_up),
                   "-t_srs", "EPSG:3857",
                   "-te", *(repr(v) for v in extent),
                   "-ts", str(geometry["width"]), str(geometry["height"]),
                   "-r", "bilinear", "-ot", "Float64", "-dstnodata", "nan",
                   "-co", "TILED=YES", "-co", "COMPRESS=NONE",
                   "-co", "INTERLEAVE=BAND"]
            if s_srs:
                cmd += ["-s_srs", s_srs]
            if srcnodata is not None:
                cmd += ["-srcnodata", str(srcnodata)]
            self.run(cmd + [src, dst], check=True)
            with open(dst, "rb") as handle:
                return handle.read()

    def info(self, src, bottom_up=None):
        out = self.run(["gdalinfo", "-json", *self._config(bottom_up), src],
                       check=True, capture_output=True)
        return json.loads(out.stdout)


def band_scale(info):
    """Scale and offset shared by every band. INCA stores int32 with
    scale 0.001, and gdalwarp copies the raw integers: without this the
    first trial had 254 mm (the clamp) on every day and INCA at 3.9 times
    SPARTACUS."""
    pairs = {(b.get("scale", 1.0), b.get("offset", 0.0))
             for b in info.get("bands", [])}
    if len(pairs) != 1:
        raise SystemExit(f"bands disagree on scale/offset: {sorted(pairs)}")
    return pairs.pop()


def orientation(gdal, src):
    """Which GDAL_NETCDF_BOTTOMUP setting makes the rows agree with the
    geotransform GDAL reports.

    Both files store their rows south to north. Measured 2026-10-01 with
    GDAL 3.12: the setting flips the DATA for every file, but the
    geotransform does not follow it — RprelimD and SPARTACUS report
    north-up (e < 0) either way, INCA reports south-up (e > 0) either
    way. Taken at face value, INCA came out mirrored (r −0.10 against
    SPARTACUS in the first trial) while the median looked fine.

    So: read the geotransform with the default (YES). North-up means YES
    is right — GDAL flipped the rows, or the file was north-up already.
    South-up means GDAL kept the file's order, and only NO keeps the
    rows in it. A GDAL that behaves reports north-up with YES and lands
    in the first case. --verify's correlations are the second net."""
    transform = gdal.info(src, bottom_up="YES").get("geoTransform")
    if not transform or transform[5] == 0 or transform[1] <= 0:
        raise SystemExit(f"{src}: no usable geotransform ({transform})")
    return "YES" if transform[5] < 0 else "NO"


def read_netcdf(gdal, path, variable, s_srs, geometry, extent, orient=None):
    """Every band of `variable` warped onto the grid, unscaled and summed.
    Returns (sums, band count, orientation used)."""
    src = f'NETCDF:"{path}":{variable}'
    flag = orient or orientation(gdal, src)
    scale, offset = band_scale(gdal.info(src, bottom_up=flag))
    sums, bands = sum_bands(gdal.warp(src, geometry, extent, s_srs=s_srs,
                                      bottom_up=flag),
                            geometry["width"], geometry["height"])
    if (scale, offset) != (1.0, 0.0):
        sums = array.array("d", (v * scale + bands * offset for v in sums))
    return sums, bands, flag


def sum_bands(data, width, height):
    """Sum every band of a warped GeoTIFF cell by cell, tile by tile —
    24 full hourly grids as Python floats would be half a gigabyte. NaN
    in any band makes the cell NaN (float addition does that by itself):
    a day with a missing hour is not a day. Returns (sums, band count)."""
    order, tags = rain_grid.tiff_tags(data)
    bands = tags.get(277, [1])[0]
    if bands > 1 and tags.get(284, [1])[0] != 2:
        raise SystemExit("expected band-interleaved tiles (INTERLEAVE=BAND)")
    if (tags[256][0], tags[257][0]) != (width, height):
        raise SystemExit(f"warped raster is {tags[256][0]}x{tags[257][0]}, "
                         f"expected {width}x{height}")
    tile_w, tile_h = tags[322][0], tags[323][0]
    across = (width + tile_w - 1) // tile_w
    down = (height + tile_h - 1) // tile_h
    per_band = across * down
    offsets = tags[324]
    if len(offsets) != per_band * bands:
        raise SystemExit("tile count does not match the band count")
    swap = (order == ">") != (sys.byteorder == "big")
    total = array.array("d", bytes(8 * width * height))
    for band in range(bands):
        for t in range(per_band):
            start = offsets[band * per_band + t]
            tile = array.array("d")
            tile.frombytes(data[start:start + tile_w * tile_h * 8])
            if swap:
                tile.byteswap()
            tx, ty = (t % across) * tile_w, (t // across) * tile_h
            cols = min(tile_w, width - tx)
            for row in range(min(tile_h, height - ty)):
                base = (ty + row) * width + tx
                seg = tile[row * tile_w:row * tile_w + cols]
                total[base:base + cols] = array.array(
                    "d", map(operator.add, total[base:base + cols], seg))
    return total, bands


def quantise(values):
    return bytearray(rain_grid._quantise(v) for v in values)


# ------------------------------------------------------------ fetching

def _get(url, timeout=120, tries=4, data=None, headers=None):
    """GET (or POST with `data`); None for a 404, retries otherwise."""
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, data=data, headers=headers or {})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code in (400, 403, 404):
                return None
            if attempt == tries - 1:
                raise
        except Exception:
            if attempt == tries - 1:
                raise
        time.sleep(2 ** attempt)


def inca_url(date):
    return (f"{INCA_API}?parameters=RR&start={date}T00:00&end={date}T23:00"
            f"&bbox={INCA_BBOX}&output_format=netcdf")


def dpc_product_ms(date):
    """The DPC file stamped D+1 00:00 UTC holds the 24 hours of day D
    (measured with a lag test, docs §Italien)."""
    end = dt.datetime.combine(dt.date.fromisoformat(date) + dt.timedelta(days=1),
                              dt.time(0), tzinfo=dt.timezone.utc)
    return int(end.timestamp() * 1000)


def stac_asset(item_json):
    """The RprelimD NetCDF among an item's assets, or None."""
    for asset in json.loads(item_json).get("assets", {}).values():
        href = asset.get("href", "")
        if "rprelimd" in href.lower() and href.endswith(".nc"):
            return href
    return None


def fetch_source(name, date, geometry, extent, get=_get, gdal=None,
                 orient=None):
    """One day of one source on the blend grid as bytes, or None when the
    service does not have it (yet). `orient` caches the NetCDF
    orientation per source for a run (name -> flag)."""
    gdal = gdal or Gdal()
    orient = {} if orient is None else orient
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "source.nc")
        if name in ("inca", "rprelimd"):
            if name == "inca":
                payload = get(inca_url(date), timeout=300)
            else:
                item = get(STAC_ITEM.format(date.replace("-", "")))
                href = stac_asset(item) if item else None
                payload = get(href, timeout=300) if href else None
            if not payload:
                return None
            with open(raw, "wb") as handle:
                handle.write(payload)
            variable, s_srs = (("RR", "EPSG:31287") if name == "inca"
                               else ("RprelimD", "EPSG:2056"))
            sums, bands, orient[name] = read_netcdf(
                gdal, raw, variable, s_srs, geometry, extent, orient.get(name))
            if name == "inca" and bands != 24:
                print(f"  inca {date}: {bands} hours, not a whole day",
                      file=sys.stderr)
                return None
            return quantise(sums)
        if name == "dpc":
            body = json.dumps({"productType": "CUM24",
                               "productDate": dpc_product_ms(date)}).encode()
            answer = get(DPC_API, data=body,
                         headers={"Content-Type": "application/json",
                                  "Origin": DPC_ORIGIN})
            url = json.loads(answer).get("url") if answer else None
            payload = get(url, timeout=300) if url else None
            if not payload:
                return None
            raw = os.path.join(tmp, "source.tif")
            with open(raw, "wb") as handle:
                handle.write(payload)
            scale, offset = band_scale(gdal.info(raw))
            sums, _ = sum_bands(gdal.warp(raw, geometry, extent, srcnodata=-9999),
                                geometry["width"], geometry["height"])
            return quantise(v * scale + offset for v in sums)
    raise ValueError(name)


# ------------------------------------------------------------ the run

def needed_dates(today):
    yesterday = today - dt.timedelta(days=1)
    return sorted((yesterday - dt.timedelta(days=i)).isoformat()
                  for i in range(STACK_DAYS))


def fetch_plan(previous, today):
    """Per national source the dates to ask for, newest first: every
    missing day, plus the last REFRESH_DAYS again."""
    dates = needed_dates(today)
    recent = set(dates[-REFRESH_DAYS:])
    plan = {}
    for name in NATIONAL:
        have = {d["date"] for d in
                ((previous or {}).get("sources", {}).get(name, {}).get("days", []))}
        plan[name] = sorted((d for d in dates if d not in have or d in recent),
                            reverse=True)
    return plan


def _write(out_dir, name, data, geometry):
    w = geometry["width"]
    rows = [bytes(data[r * w:(r + 1) * w]) for r in range(geometry["height"])]
    payload = rain_grid.encode(rows)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, name), "wb") as handle:
        handle.write(payload)
    known = [v for v in data if v != NO_DATA]
    return {"file": name, "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "max_mm": max(known) if known else 0,
            "valid_percent": round(100 * len(known) / max(1, len(data)), 1)}


def _read(dirs, name, geometry):
    for directory in dirs:
        path = os.path.join(directory, name)
        if os.path.exists(path):
            with open(path, "rb") as handle:
                rows = rain_grid.decode(handle.read(), geometry["width"],
                                        geometry["height"])
            return bytearray(b"".join(rows))
    return None


def build(out_dir, inputs_dir, manifest, today=None, fetch=None, mask=None):
    """Fetch what is missing, blend every day whose inputs changed, and
    write the manifest section `alps`. Returns (section, keep list)."""
    today = today or dt.datetime.now(dt.timezone.utc).date()
    fetch = fetch or (lambda *args: fetch_source(*args[:4], orient=args[4]))
    geometry, extent = geometry_of()
    mask_geometry, owner = mask or load_mask()
    assert mask_geometry == geometry
    w, h = geometry["width"], geometry["height"]
    previous = manifest.get("alps") or {}
    dates = needed_dates(today)
    dirs = [out_dir, inputs_dir]

    # 1. The national sources.
    sources, orient = {}, {}
    for name in NATIONAL:
        known = {d["date"]: d for d in
                 previous.get("sources", {}).get(name, {}).get("days", [])}
        for date in fetch_plan(previous, today)[name]:
            try:
                grid = fetch(name, date, geometry, extent, orient)
            except Exception as error:                  # noqa: BLE001
                # One flaky service must not cost the other two their
                # day; the gap shows in the summary and in --verify.
                print(f"  {name} {date}: {error}", file=sys.stderr)
                continue
            if grid is None:
                print(f"  {name} {date}: not available", file=sys.stderr)
                continue
            stamp = date.replace("-", "")
            entry = _write(out_dir, SOURCES[name]["file"].format(stamp), grid, geometry)
            if known.get(date, {}).get("sha256") != entry["sha256"]:
                print(f"  {name} {date}: {entry['valid_percent']} % cells, "
                      f"max {entry['max_mm']} mm", file=sys.stderr)
            known[date] = {"date": date, **entry}
        sources[name] = {**{k: v for k, v in SOURCES[name].items() if k != "file"},
                         "days": [known[d] for d in dates if d in known]}

    # 2. The two stacks that already exist.
    daily = manifest.get("daily") or {}
    radar_days = {d["date"]: d for d in daily.get("days", [])}
    model_rain = (manifest.get("model") or {}).get("rain") or {}
    model_days = {d["date"]: d for d in model_rain.get("days", [])}

    # 3. Blend every day whose inputs changed.
    old_days = {d["date"]: d for d in previous.get("rain", {}).get("days", [])}
    weights = active = None
    days = []
    for date in dates:
        stamp = date.replace("-", "")
        inputs = {name: e["sha256"] for name in NATIONAL
                  for e in sources[name]["days"] if e["date"] == date}
        if date in radar_days:
            inputs["radar"] = radar_days[date]["sha256"]
        if date in model_days:
            inputs["model"] = model_days[date]["sha256"]
        if not any(name in inputs for name in NATIONAL):
            continue
        old = old_days.get(date)
        if old and old.get("inputs") == inputs:
            days.append(old)
            continue
        if weights is None:
            weights, active = static_weights(owner, w, h)
        layers = {name: _read(dirs, SOURCES[name]["file"].format(stamp), geometry)
                  if name in inputs else None for name in NATIONAL}
        layers["radar"] = None
        if "radar" in inputs:
            grid = _read(dirs, radar_days[date]["file"], daily)
            layers["radar"] = sample_nearest(grid, daily, geometry) if grid else None
        model = None
        if "model" in inputs:
            grid = _read(dirs, model_days[date]["file"], model_rain)
            model = sample_bilinear(grid, model_rain, geometry) if grid else None
        missing = [n for n in inputs if n != "model" and n != "radar"
                   and layers.get(n) is None]
        if missing:
            raise SystemExit(f"{date}: day files of {missing} are in the "
                             f"manifest but not in {dirs}")
        values, origin = blend(layers, model, weights, active, w, h)
        entry = _write(out_dir, BLEND_FILE.format(stamp), values, geometry)
        origin_entry = _write(out_dir, ORIGIN_FILE.format(stamp), origin, geometry)
        days.append({"date": date, **entry, "inputs": inputs,
                     "origin": {k: origin_entry[k] for k in ("file", "bytes", "sha256")}})
        print(f"  blend {date}: {entry['bytes'] // 1024} KB, "
              f"max {entry['max_mm']} mm, from {sorted(inputs)}", file=sys.stderr)

    keep = sorted({d["file"] for d in days} | {d["origin"]["file"] for d in days}
                  | {e["file"] for s in sources.values() for e in s["days"]})
    section = {
        "licence": "CC BY-SA 4.0",
        "attribution": ATTRIBUTION,
        "built": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "blend": {"box": BLUR_BOX, "passes": BLUR_PASSES, "shift": SHIFT,
                  "feather": FEATHER, "mask": os.path.basename(MASK_FILE),
                  "mask_sha256": MASK_SHA256, "origin_bits": SOURCE_BITS},
        "sources": sources,
        "rain": {**geometry, "days": days},
    }
    manifest["alps"] = section
    return section, keep


# -------------------------------------------------------------- verify

def verify(out_dir, inputs_dir, manifest, get=_get, gdal=None, samples=400,
           today=None):
    """Three checks against the built files, each able to fail the run:

    1. Freshness: the day before yesterday has INCA and DPC, the day
       before that RprelimD. A silently broken fetch would otherwise only
       show as the map slowly sliding back to the model.
    2. The blend on real data: every stored cell lies between the
       smallest and largest of the inputs that carry weight there, and
       deep inside each country it IS that country's source. Read from
       the written files, so it checks what ships.
    3. Scale and place. INCA against SPARTACUS (GeoSphere's station-only
       grid), and the sources against each other where they overlap:
       sums over the shared days at random cells, median ratio AND
       correlation. The ratio catches a unit or scale (the first trial
       had INCA at 3.9 times SPARTACUS — int32 with scale 0.001); only
       the correlation catches a mirrored or shifted grid, whose sums
       look entirely normal.
    """
    gdal = gdal or Gdal()
    today = today or dt.datetime.now(dt.timezone.utc).date()
    section = manifest["alps"]
    geometry, extent = geometry_of()
    w, h = geometry["width"], geometry["height"]
    dirs = [out_dir, inputs_dir]
    lines, failures = [], []

    have = {name: {d["date"] for d in section["sources"][name]["days"]}
            for name in NATIONAL}
    for name, lag in (("inca", 2), ("dpc", 2), ("rprelimd", 3)):
        date = (today - dt.timedelta(days=lag)).isoformat()
        ok = date in have[name]
        lines.append(f"- {name}: {len(have[name])}/{STACK_DAYS} Tage, "
                     f"{date} {'da' if ok else '**fehlt**'}\n")
        if not ok:
            failures.append(f"{name} has no {date}")

    # 2. Bounds on the newest blended day that has local files.
    _, owner = load_mask()
    weights, active = static_weights(owner, w, h)
    daily, model_rain = manifest.get("daily") or {}, (manifest.get("model") or {}).get("rain") or {}
    for day in reversed(section["rain"]["days"]):
        values = _read([out_dir], day["file"], geometry)
        if values is None:
            continue
        stamp = day["date"].replace("-", "")
        layers = {name: _read(dirs, SOURCES[name]["file"].format(stamp), geometry)
                  for name in NATIONAL if name in day["inputs"]}
        if "radar" in day["inputs"]:
            entry = next(d for d in daily["days"] if d["date"] == day["date"])
            layers["radar"] = sample_nearest(_read(dirs, entry["file"], daily), daily, geometry)
        model = None
        if "model" in day["inputs"]:
            entry = next(d for d in model_rain["days"] if d["date"] == day["date"])
            model = sample_bilinear(_read(dirs, entry["file"], model_rain), model_rain, geometry)
        random.seed(20261001)
        outside = pure_bad = checked = 0
        for i in random.sample(list(active), min(samples, len(active))):
            if values[i] == NO_DATA:
                continue
            carried = [g[i] for n, g in layers.items()
                       if g is not None and g[i] != NO_DATA and weights[n][i] > 0]
            if model is not None and model[i] is not None:
                carried.append(model[i])
            if not carried:
                continue
            checked += 1
            if not min(carried) - 0.5 <= values[i] <= max(carried) + 0.5:
                outside += 1
            # Deep inside its own country, with no gap of its own nearby,
            # a source must come through untouched.
            for n, g in layers.items():
                if g is not None and weights[n][i] == 1.0 and g[i] != NO_DATA \
                        and values[i] != g[i] and _deep(g, i, w, h):
                    pure_bad += 1
        lines.append(f"- Mischung {day['date']}: {checked} Zellen, "
                     f"{outside} außerhalb ihrer Quellen, {pure_bad} im "
                     f"Landesinneren nicht gleich der Landesquelle\n")
        if outside or pure_bad:
            failures.append(f"blend {day['date']}: {outside} out of bounds, "
                            f"{pure_bad} not pure")
        break

    # 3. Scale and place.
    totals = {name: _stack_sums(dirs, section["sources"][name]["days"], geometry)
              for name in NATIONAL}
    inca_days = sorted(d["date"] for d in section["sources"]["inca"]["days"])
    if len(inca_days) >= 14:
        url = (f"{SPARTACUS_API}?parameters=RR&start={inca_days[0]}T00:00"
               f"&end={inca_days[-1]}T00:00&bbox={SPARTACUS_BBOX}"
               f"&output_format=netcdf")
        payload = get(url, timeout=300)
        if payload:
            with tempfile.TemporaryDirectory() as tmp:
                raw = os.path.join(tmp, "spartacus.nc")
                with open(raw, "wb") as handle:
                    handle.write(payload)
                sums, bands, _ = read_netcdf(gdal, raw, "RR", "EPSG:3416",
                                             geometry, extent)
            # SPARTACUS days run 06-06 UTC: over the whole span that is
            # six hours at each end, nothing in a ratio.
            totals["spartacus"] = (sums, bands)
        else:
            lines.append("- SPARTACUS nicht erreichbar, Vergleich entfällt\n")
    for first, second, min_r in PAIRS:
        if first not in totals or second not in totals:
            continue
        (a_sums, a_days), (b_sums, b_days) = totals[first], totals[second]
        # Only where the two are actually mixed: both carry weight. Deep
        # in Switzerland DPC is worthless and never used, and comparing
        # it there would measure that, not the grid's position.
        if second == "spartacus":
            where = [owner[i] == AT for i in range(w * h)]
        else:
            where = [weights[first][i] > 0 and weights[second][i] > 0
                     for i in range(w * h)]
        random.seed(20261001)
        cells = [i for i in range(w * h)
                 if where[i] and a_sums[i] == a_sums[i]
                 and b_sums[i] == b_sums[i] and b_sums[i] >= 10]
        cells = random.sample(cells, min(500, len(cells)))
        if len(cells) < 30:
            lines.append(f"- {first}/{second}: nur {len(cells)} gemeinsame Zellen\n")
            continue
        xs = [a_sums[i] / a_days for i in cells]
        ys = [b_sums[i] / b_days for i in cells]
        ratios = sorted(x / y for x, y in zip(xs, ys))
        median, r = ratios[len(ratios) // 2], _pearson(xs, ys)
        lines.append(f"- {first}/{second}: Median {median:.2f}, r {r:.2f} "
                     f"an {len(cells)} Zellen (je Tag gemittelt)\n")
        if not 0.7 <= median <= 1.4 or r < min_r:
            failures.append(f"{first}/{second}: median {median:.2f}, r {r:.2f}")

    report = "### Alpenraum gemessen\n\n" + "".join(lines)
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(report)
    if failures:
        raise SystemExit("; ".join(failures))


# Pairs compared in --verify, with the least correlation of their mean
# daily rain over the stack that a correctly placed pair keeps. Set from
# the trial on 30 real days (2026-08-31…09-29) with a margin; a mirrored
# grid falls far below.
PAIRS = (("inca", "spartacus", 0.8), ("inca", "rprelimd", 0.6),
         ("rprelimd", "dpc", 0.6))


def _stack_sums(dirs, days, geometry):
    """Sum per cell over a source's days; NaN where any day lacks it.
    Returns (sums, day count)."""
    n = geometry["width"] * geometry["height"]
    total = array.array("d", bytes(8 * n))
    count = 0
    for day in days:
        grid = _read(dirs, day["file"], geometry)
        if grid is None:
            continue
        count += 1
        for i, v in enumerate(grid):
            total[i] = float("nan") if v == NO_DATA else total[i] + v
    return total, max(1, count)


def _pearson(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    return sxy / math.sqrt(sxx * syy) if sxx and syy else 0.0


def _deep(grid, i, w, h, reach=FEATHER):
    """No gap of this source within `reach` cells — its feather is 1."""
    y, x = divmod(i, w)
    for yy in range(max(0, y - reach), min(h, y + reach + 1)):
        row = yy * w
        for xx in range(max(0, x - reach), min(w, x + reach + 1)):
            if grid[row + xx] == NO_DATA:
                return False
    return True


# ----------------------------------------------------------- self-test

TOWNS = (
    # (name, lat, lon, owner) — the border towns the operator would look
    # at first, plus one per neighbour that must stay "other".
    ("Bregenz", 47.503, 9.747, AT), ("Vaduz", 47.141, 9.521, CH),
    ("Chur", 46.850, 9.532, CH),
    # North of the Rhine: the old town touches Kreuzlingen, and 1:10m is
    # a few hundred metres off there — irrelevant under a 30 km blend.
    ("Konstanz", 47.676, 9.173, DE),
    ("Como", 45.810, 9.085, IT), ("Brixen", 46.716, 11.657, IT),
    ("Salzburg", 47.800, 13.045, AT), ("Freilassing", 47.840, 12.977, DE),
    ("Lugano", 46.004, 8.951, CH), ("Innsbruck", 47.269, 11.404, AT),
    ("Ljubljana", 46.056, 14.506, OTHER), ("Strasbourg", 48.573, 7.752, OTHER),
)


def self_test():
    _self_test_shapefile()
    _self_test_blend_unit()
    _self_test_reading()
    _self_test_plan()
    _self_test_real_mask()
    print("alps_rain self-test: ok")


def _fake_shapefile(polygons):
    """A zip with .shp and .dbf, for the reader test only.
    polygons: [(ADM0_A3, [ring, ...])]."""
    records = b""
    for n, (_, rings) in enumerate(polygons, 1):
        points = [p for ring in rings for p in ring]
        starts, at_ = [], 0
        for ring in rings:
            starts.append(at_)
            at_ += len(ring)
        content = struct.pack("<i4d2i", 5, 0, 0, 0, 0, len(rings), len(points))
        content += struct.pack(f"<{len(rings)}i", *starts)
        content += struct.pack(f"<{2 * len(points)}d", *[c for p in points for c in p])
        records += struct.pack(">2i", n, len(content) // 2) + content
    shp = bytes(100) + records
    fields = struct.pack("<11sc4xB15x", b"ADM0_A3", b"C", 3)
    header_len = 32 + len(fields) + 1
    dbf = struct.pack("<B3xIHH20x", 3, len(polygons), header_len, 4) + fields + b"\x0d"
    for code, _ in polygons:
        dbf += b" " + code.encode().ljust(3)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("x.shp", shp)
        archive.writestr("x.dbf", dbf)
    return buffer.getvalue()


def _self_test_shapefile():
    square = [(7.0, 46.0), (9.0, 46.0), (9.0, 48.0), (7.0, 48.0)]
    hole = [(7.5, 46.5), (8.5, 46.5), (8.5, 47.5), (7.5, 47.5)]
    tri = [(10.0, 46.0), (12.0, 46.0), (11.0, 48.0)]
    zipped = _fake_shapefile([("CHE", [square, hole]), ("XXX", [tri]),
                              ("ITA", [tri])])
    rings = read_countries(zipped)
    assert set(rings) == {CH, IT}, rings.keys()
    geometry, _ = geometry_of((6.5, 45.7, 12.5, 48.3), 10_000)
    owner = rasterise(rings, geometry)

    def at(lat, lon):
        return owner[cell_of(geometry, lat, lon)]
    assert at(46.2, 7.2) == CH, "inside the square"
    assert at(47.0, 8.0) == OTHER, "inside the hole (even-odd)"
    assert at(46.3, 11.0) == IT and at(47.8, 10.2) == OTHER
    assert at(48.2, 8.0) == OTHER and at(46.0, 6.6) == OTHER


def _self_test_blend_unit():
    # Blur: a partition of unity stays one, exactly, edges included.
    w, h = 40, 30
    owner = bytearray((AT if x < 20 else CH) if y < 20 else IT
                      for y in range(h) for x in range(w))
    blurred = [blur(bytes(1 if v == c else 0 for v in owner), w, h, box=5, passes=3)
               for c in (AT, CH, IT)]
    for i in range(w * h):
        assert abs(sum(b[i] for b in blurred) - 1) < 1e-12, i
    assert blurred[0][0] == 1.0 and blurred[1][w - 1] == 1.0

    # Spread: nearest seed, limited reach, only into targets.
    row = bytearray([AT, OTHER, OTHER, OTHER, CH])
    assert spread(row, 5, 1, {AT, CH}, {OTHER}, 1) == bytearray([AT, AT, OTHER, CH, CH])
    assert spread(row, 5, 1, {AT}, {OTHER}, 9) == bytearray([AT, AT, AT, AT, CH])

    # Feather: 0 on the gap, 1 beyond reach, monotone in between.
    grid = bytearray([NO_DATA] + [5] * 9)
    f = feather(grid, 10, 1, reach=4)
    assert f[0] == 0 and f[4] == 1 and f[9] == 1
    assert all(f[i] <= f[i + 1] for i in range(9))


def _self_test_reading():
    # sum_bands over three bands, band-interleaved, little and big endian.
    bands = [[[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]],
             [[0.5, 0.5, 0.5], [0.5, float("nan"), 0.5]],
             [[1.0, 1.0, 1.0], [1.0, 1.0, 1.0]]]
    data = _fake_bands(bands, 2, 2)
    total, count = sum_bands(data, 3, 2)
    assert count == 3
    assert list(total)[:4] == [2.5, 3.5, 4.5, 5.5] and total[5] == 7.5
    assert total[4] != total[4], "a missing hour must make the day missing"
    try:
        sum_bands(data, 2, 2)
    except SystemExit:
        pass
    else:
        raise AssertionError("a raster of the wrong size was accepted")
    assert quantise([0.4, 2.6, float("nan"), 999]) == bytearray([0, 3, NO_DATA, 254])

    # Scale and offset: shared by all bands, or the run stops.
    assert band_scale({"bands": [{"scale": 0.001}, {"scale": 0.001}]}) == (0.001, 0.0)
    assert band_scale({"bands": [{}]}) == (1.0, 0.0)
    try:
        band_scale({"bands": [{"scale": 0.001}, {}]})
    except SystemExit:
        pass
    else:
        raise AssertionError("bands with different scales were accepted")

    # The orientation rule, on the three geotransforms measured with
    # GDAL 3.12 (INCA south-up, RprelimD and SPARTACUS north-up), and a
    # file without one, which must stop the run.
    class ReportingGdal:
        def __init__(self, transform):
            self.transform = transform

        def info(self, src, bottom_up=None):
            return {"geoTransform": self.transform} if self.transform else {}

    assert orientation(ReportingGdal([19500, 1000, 0, 219500, 0, 1000]), "x") == "NO"
    assert orientation(ReportingGdal([2474000, 1000, 0, 1324000, 0, -1000]), "x") == "YES"
    for broken in (None, [0, 1, 0, 0, 0, 0]):
        try:
            orientation(ReportingGdal(broken), "x")
        except SystemExit:
            continue
        raise AssertionError(f"geotransform {broken} was accepted")

    # The service details that fail silently when wrong.
    assert dpc_product_ms("2026-09-29") == 1790726400000  # 2026-09-30T00:00Z
    assert "start=2026-09-29T00:00&end=2026-09-29T23:00" in inca_url("2026-09-29")
    item = json.dumps({"assets": {
        "a": {"href": "https://x/…tabsd_ch01h.swiss.lv95_20260929000000.nc"},
        "b": {"href": "https://x/…rprelimd_ch01h.swiss.lv95_20260929000000.nc"}}})
    assert stac_asset(item).endswith("rprelimd_ch01h.swiss.lv95_20260929000000.nc")

    # The grid is the model's box at 1 km, with the model's arithmetic.
    geometry, extent = geometry_of(model_weather.BOX, model_weather.CELL_M)
    assert geometry == model_weather.lattice()[0], geometry
    geometry, extent = geometry_of()
    assert (geometry["width"], geometry["height"]) == (1258, 576), geometry
    assert abs((extent[2] - extent[0]) / geometry["width"] - CELL_M) < 1e-6


def _fake_bands(bands, tile_w, tile_h):
    """A little-endian, tiled, band-interleaved Float64 TIFF."""
    height, width = len(bands[0]), len(bands[0][0])
    across = (width + tile_w - 1) // tile_w
    down = (height + tile_h - 1) // tile_h
    tiles = []
    for band in bands:
        for ty in range(down):
            for tx in range(across):
                cells = [band[y][x] if y < height and x < width else 0.0
                         for y in range(ty * tile_h, ty * tile_h + tile_h)
                         for x in range(tx * tile_w, tx * tile_w + tile_w)]
                tiles.append(struct.pack("<" + "d" * len(cells), *cells))
    entries = [(256, 4, [width]), (257, 4, [height]), (258, 3, [64]),
               (259, 3, [1]), (277, 3, [len(bands)]), (284, 3, [2]),
               (322, 3, [tile_w]), (323, 3, [tile_h]), (324, 4, None),
               (339, 3, [3])]
    ifd_end = 8 + 2 + len(entries) * 12 + 4
    offsets_at = ifd_end
    tile_start = offsets_at + 4 * len(tiles)
    positions, cursor = [], tile_start
    for tile in tiles:
        positions.append(cursor)
        cursor += len(tile)
    ifd = struct.pack("<H", len(entries))
    for tag, kind, payload in entries:
        if tag == 324:
            ifd += struct.pack("<HHII", tag, kind, len(tiles), offsets_at)
        else:
            fmt = {3: "H", 4: "I"}[kind]
            ifd += struct.pack("<HHI", tag, kind, 1) \
                + struct.pack("<" + fmt, payload[0]).ljust(4, b"\0")
    ifd += struct.pack("<I", 0)
    return (b"II\x2a\x00" + struct.pack("<I", 8) + ifd
            + struct.pack(f"<{len(positions)}I", *positions) + b"".join(tiles))


def _self_test_plan():
    today = dt.date(2026, 10, 1)
    dates = needed_dates(today)
    assert len(dates) == STACK_DAYS and dates[-1] == "2026-09-30"
    previous = {"sources": {"inca": {"days": [{"date": d} for d in dates]},
                            "dpc": {"days": [{"date": d} for d in dates[:-5]]}}}
    plan = fetch_plan(previous, today)
    assert plan["inca"] == ["2026-09-30", "2026-09-29"], plan["inca"]
    assert plan["dpc"] == sorted(dates[-5:], reverse=True), plan["dpc"]
    assert len(plan["rprelimd"]) == STACK_DAYS


def _self_test_real_mask():
    """The tests the operator asked for, on the REAL border (2026-10-01):
    identical inputs must come back unchanged everywhere — the
    double-counting test — and two different sources must meet without
    an edge."""
    geometry, owner = load_mask()
    w, h = geometry["width"], geometry["height"]
    for name, lat, lon, expected in TOWNS:
        got = owner[cell_of(geometry, lat, lon)]
        assert got == expected, f"{name}: owner {got}, expected {expected}"

    weights, active = static_weights(owner, w, h)
    sample = range(0, w * h, 97)
    for i in sample:
        total = sum(weights[n][i] for n in weights)
        assert abs(total - 1) < 1e-9, (i, total)
        if owner[i] != IT:
            assert weights["dpc"][i] == 0, f"DPC outside Italy at cell {i}"
        if owner[i] in (DE, AT, CH):
            assert weights["model"][i] == 0, f"model inside DE/AT/CH at cell {i}"

    # The double-counting test: every source carries the same field.
    field = bytearray(((r * 7 + c * 13) % 200) for r in range(h) for c in range(w))
    layers = {name: bytearray(field) for name in MEASURED}
    model = [float(v) for v in field]
    values, origin = blend(layers, model, weights, active, w, h)
    bad = [i for i in active if values[i] != field[i]]
    assert not bad, f"{len(bad)} cells changed under identical inputs, e.g. {bad[:3]}"
    for name, lat, lon, _ in TOWNS:
        i = cell_of(geometry, lat, lon)
        assert values[i] == field[i]
    # Each source covers only its own country plus a seam, like the real
    # ones; the result must still be the field.
    lats, lons = _centres(geometry)
    for name, code in OWNER_OF.items():
        seam = ownership(owner, w, h, shift=SHIFT * 2)
        layers[name] = bytearray(field[i] if seam[i] == code or owner[i] == code
                                 else NO_DATA for i in range(w * h))
    values, _ = blend(layers, model, weights, active, w, h)
    bad = [i for i in active if values[i] != field[i]]
    assert not bad, f"{len(bad)} cells changed with ragged coverage, e.g. {bad[:3]}"

    # No edge: constant but different sources, a step of 30 mm between
    # Austria and Switzerland, 50 mm to Italy. The largest jump between
    # neighbouring cells must stay a small fraction of the step.
    levels = {"inca": 10, "rprelimd": 40, "dpc": 60, "radar": 20}
    layers = {n: bytearray([levels[n]]) * (w * h) for n in MEASURED}
    model = [30.0] * (w * h)
    values, origin = blend(layers, model, weights, active, w, h)
    stored = set(active)
    worst = 0
    for i in active:
        y, x = divmod(i, w)
        for j in (i + 1 if x + 1 < w else None, i + w if y + 1 < h else None):
            if j is not None and j in stored and values[j] != NO_DATA:
                worst = max(worst, abs(values[i] - values[j]))
    assert worst <= 3, f"largest step between neighbours {worst} mm"
    assert all(10 <= values[i] <= 60 for i in active)
    # Ljubljana is beyond every measured band; Strasbourg, 2 km from Kehl,
    # is inside the one where the DWD radar reaches over the border.
    for name, bits in (("Ljubljana", SOURCE_BITS["model"]),
                       ("Strasbourg", SOURCE_BITS["radar"])):
        _, lat, lon, _ = next(t for t in TOWNS if t[0] == name)
        assert origin[cell_of(geometry, lat, lon)] == bits, \
            (name, origin[cell_of(geometry, lat, lon)])
    print(f"  real border: largest step between neighbours {worst} mm "
          f"for steps of 10 to 50 mm between sources")


# ---------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="build/rain")
    parser.add_argument("--inputs", default="build/inputs",
                        help="day files of earlier runs (radar, model, sources)")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--build-mask", metavar="NE_ZIP")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if args.build_mask:
        build_mask(args.build_mask)
        return

    manifest_path = os.path.join(args.out, "rain_manifest.json")
    with open(manifest_path) as handle:
        manifest = json.load(handle)
    if args.verify:
        verify(args.out, args.inputs, manifest)
        return

    section, keep = build(args.out, args.inputs, manifest)
    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
    with open(os.path.join(os.path.dirname(args.out) or ".", KEEP_FILE), "w") as handle:
        handle.write("\n".join(keep) + "\n")

    days = section["rain"]["days"]
    summary = (f"### Alpenraum gemessen ({len(days)} Tage)\n\n"
               + "".join(f"- {name}: {len(section['sources'][name]['days'])} Tage\n"
                         for name in NATIONAL)
               + f"- gemischt: {sum(d['bytes'] for d in days) // 1024} KB\n")
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(summary)


if __name__ == "__main__":
    sys.exit(main())
