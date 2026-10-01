#!/usr/bin/env python3
"""Daily rain sums from the EUMETNET OPERA 1-h accumulation composite at
our places and at the Alpine model lattice — a MEASUREMENT for
docs/regendaten-alpenraum.md (#645, #646), not a data source: OPERA
carries no Austrian or Italian radars.

Source: anonymous S3, openradar-archive (CloudFerro), ODIM HDF5.
A file's time is the END of its 1-h accumulation, so UTC day D is the 24
files D 01:00 ... D+1 00:00. Raw codes: nodata (missing) and undetect
(= 0 mm) come from dataset1/data1/what; values are gain*raw+offset.
A point-day is complete only if all 24 hours have a value there.

Usage (needs numpy, h5py, pyproj):
  python3 measure/opera_measure.py --out measure
"""
import argparse
import concurrent.futures as cf
import csv
import datetime as dt
import io
import json
import os
import sys
import time
import urllib.request

import h5py
import numpy as np
from pyproj import Proj

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tool"))
import model_weather  # noqa: E402

BASE = "https://s3.waw3-1.cloudferro.com/openradar-archive"
FIRST, LAST = dt.date(2026, 8, 31), dt.date(2026, 9, 29)
LATTICE_FROM = dt.date(2026, 9, 4)  # 26 days, the table in the doc
PLACES = [
    ("Salzburg", 47.80, 13.04), ("Kufstein", 47.58, 12.17),
    ("Gmunden", 47.92, 13.80), ("Zell am See", 47.32, 12.80),
    ("Innsbruck", 47.27, 11.39), ("Bregenz", 47.50, 9.75),
    ("Bozen", 46.50, 11.35), ("Brixen", 46.72, 11.66),
    ("Chur", 46.85, 9.53), ("Luzern", 47.05, 8.31),
    ("Davos", 46.80, 9.84),
]


def url_for(end):
    return (f"{BASE}/{end:%Y/%m/%d}/OPERA/COMP/"
            f"OPERA@{end:%Y%m%dT%H%M}@0@ACRR.h5")


def fetch(end):
    t0 = time.monotonic()
    req = urllib.request.Request(url_for(end), headers={
        "User-Agent": "pilzbuddy-measure (github.com/MacBuchi/pilzbuddy)"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
            return end, data, time.monotonic() - t0, None
        except Exception as e:  # noqa: BLE001 — reported, not hidden
            err = f"{type(e).__name__}: {e}"
            time.sleep(2 * (attempt + 1))
    return end, None, time.monotonic() - t0, err


def attr(group, name, default=None):
    v = group.attrs.get(name, default)
    if isinstance(v, bytes):
        v = v.decode()
    if isinstance(v, np.ndarray) and v.size == 1:
        v = v.item()
    return v


def index_points(f, points):
    where = f["where"]
    proj = Proj(attr(where, "projdef"))
    xs = float(attr(where, "xscale", 2000.0))
    ys = float(attr(where, "yscale", 2000.0))
    ulx, uly = proj(float(attr(where, "UL_lon")), float(attr(where, "UL_lat")))
    lats = np.array([p[0] for p in points])
    lons = np.array([p[1] for p in points])
    x, y = proj(lons, lats)
    cols = np.floor((x - ulx) / xs).astype(int)
    rows = np.floor((uly - y) / ys).astype(int)
    return rows, cols


def read_values(data, idx_cache, points):
    with h5py.File(io.BytesIO(data), "r") as f:
        if "rc" not in idx_cache:
            idx_cache["rc"] = index_points(f, points)
        what = f["dataset1/data1/what"]
        raw = f["dataset1/data1/data"][()]
        nodata = float(attr(what, "nodata", -9999000.0))
        undetect = float(attr(what, "undetect", -8888000.0))
        gain = float(attr(what, "gain", 1.0))
        offset = float(attr(what, "offset", 0.0))
    rows, cols = idx_cache["rc"]
    h, w = raw.shape
    inside = (rows >= 0) & (rows < h) & (cols >= 0) & (cols < w)
    out = np.full(len(points), np.nan)
    v = raw[rows[inside], cols[inside]].astype(float)
    val = np.where(v == undetect, 0.0, v * gain + offset)
    val = np.where(v == nodata, np.nan, val)
    out[inside] = val
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="measure")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    _geom, centres = model_weather.lattice()
    lattice = [(i, la, lo) for i, (la, lo) in enumerate(centres)
               if not model_weather.in_germany(la, lo)]
    points = [(la, lo) for _n, la, lo in PLACES] + \
             [(la, lo) for _i, la, lo in lattice]
    days = [FIRST + dt.timedelta(d) for d in range((LAST - FIRST).days + 1)]
    ends = [dt.datetime(d.year, d.month, d.day) + dt.timedelta(hours=h)
            for d in days for h in range(1, 25)]

    # hour sums per day and point; a NaN in any hour makes the day missing
    daily = {d: np.zeros(len(points)) for d in days}
    timings, failures = [], []
    idx_cache = {}
    with cf.ThreadPoolExecutor(args.workers) as pool:
        for end, data, secs, err in pool.map(fetch, ends):
            day = (end - dt.timedelta(hours=1)).date()
            if data is None:
                failures.append({"end": end.isoformat(), "error": err})
                daily[day][:] = np.nan
                continue
            timings.append(secs)
            try:
                daily[day] += read_values(data, idx_cache, points)
            except Exception as e:  # noqa: BLE001
                failures.append({"end": end.isoformat(),
                                 "error": f"read: {type(e).__name__}: {e}"})
                daily[day][:] = np.nan

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "opera_places.csv"), "w",
              newline="") as f:
        w = csv.writer(f)
        w.writerow(["place", "date", "mm"])
        for p, (name, _la, _lo) in enumerate(PLACES):
            for d in days:
                v = daily[d][p]
                w.writerow([name, d.isoformat(),
                            "" if np.isnan(v) else f"{v:.1f}"])

    lat_days = [d for d in days if d >= LATTICE_FROM]
    with open(os.path.join(args.out, "opera_lattice.csv"), "w",
              newline="") as f:
        w = csv.writer(f)
        w.writerow(["idx", "lat", "lon", "sum_mm", "days_complete"])
        complete_all = 0
        for k, (i, la, lo) in enumerate(lattice):
            p = len(PLACES) + k
            vals = [daily[d][p] for d in lat_days]
            ok = [v for v in vals if not np.isnan(v)]
            if len(ok) == len(lat_days):
                complete_all += 1
            w.writerow([i, la, lo, f"{sum(ok):.1f}" if ok else "",
                        len(ok)])

    def window(p, n):
        sel = days[-n:]
        vals = [daily[d][p] for d in sel]
        missing = [d.isoformat() for d, v in zip(sel, vals) if np.isnan(v)]
        return round(float(np.nansum(vals)), 1), missing

    summary = {
        "files": len(ends), "failed": failures,
        "download_s": {"mean": round(float(np.mean(timings)), 2),
                       "median": round(float(np.median(timings)), 2),
                       "max": round(float(np.max(timings)), 2)}
        if timings else None,
        "lattice_points": len(lattice),
        "lattice_complete_26_days": complete_all,
        "places": {name: {str(n): window(p, n) for n in (7, 14, 26, 30)}
                   for p, (name, _la, _lo) in enumerate(PLACES)},
    }
    with open(os.path.join(args.out, "opera_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
