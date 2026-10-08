#!/usr/bin/env python3
"""Does the self-hosted Open-Meteo answer the model grid like the public API? (#631)

    python3 tool/model_parity_check.py --local http://127.0.0.1:8080/v1/forecast

Asks BOTH services the exact requests `tool/model_weather.py` makes —
`fetch_window`, same lattice, same parameters — for a random sample of
lattice points over the whole stack: the newest week via `past_days`,
the older days via explicit dates (the historical-forecast path). Then
compares every daily value raw and as stored byte, and the elevations
(they become the height of the virtual stations).

This is the measurement that has to pass before the workflow builds the
grid from a container, and again before it moves to a new image: a new
image is a new instrument. 2026-10-08, image digest e1517a01…: 200
points × 30 days, 18 000 daily values plus the elevations, zero
differences on both paths.

Costs public quota: about `points × 4.3` calls (one per point for the
week, ~3.3 for the 23 older days). Keep `--points` under ~1 000 and run
it at least an hour away from the scheduled model fetch.
"""
import argparse
import datetime as dt
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import model_weather as mw  # noqa: E402


def compare(local, public):
    """(values, raw_diff, byte_diff, examples) over two fetch_window results."""
    values = raw_diff = byte_diff = 0
    examples = []
    for date in sorted(set(local) | set(public)):
        a_day, b_day = local.get(date, {}), public.get(date, {})
        for index in sorted(set(a_day) | set(b_day)):
            a, b = a_day.get(index), b_day.get(index)
            for k, encode in enumerate((mw.rain_byte, mw.temp_byte, mw.temp_byte)):
                va = a[k] if a else None
                vb = b[k] if b else None
                values += 1
                if va != vb:
                    raw_diff += 1
                    examples.append((date, index, mw.VARIABLES[k], va, vb))
                if (va is None or vb is None) and va != vb:
                    byte_diff += 1  # one side missing is a byte difference too
                elif va is not None and encode(va) != encode(vb):
                    byte_diff += 1
    return values, raw_diff, byte_diff, examples


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--local", required=True,
                        help="the self-hosted /v1/forecast endpoint")
    parser.add_argument("--points", type=int, default=200)
    parser.add_argument("--seed", type=int, default=631)
    args = parser.parse_args()

    _, centres = mw.lattice()
    active = [(i, lat, lon) for i, (lat, lon) in enumerate(centres)
              if not mw.in_germany(lat, lon)]
    sample = random.Random(args.seed).sample(active, min(args.points, len(active)))
    today = dt.datetime.now(dt.timezone.utc).date()
    paths = (
        ("past_days", today - dt.timedelta(days=7), today - dt.timedelta(days=1), True),
        ("history", today - dt.timedelta(days=mw.STACK_DAYS),
         today - dt.timedelta(days=8), False),
    )
    failed = False
    for name, start, end, via_past in paths:
        t0 = time.time()
        local, local_elev = mw.fetch_window(sample, start, end, via_past, today,
                                            sleep=lambda _: None, api=args.local)
        seconds = time.time() - t0
        public, public_elev = mw.fetch_window(sample, start, end, via_past, today)
        values, raw_diff, byte_diff, examples = compare(local, public)
        elevation_diff = sum(1 for i in public_elev if local_elev.get(i) != public_elev[i])
        days = f"{len(local)}/{len(public)}"
        print(f"{name:9} {start}…{end}: {values} values, {raw_diff} differ raw, "
              f"{byte_diff} as byte, {elevation_diff} elevations differ, "
              f"days local/public {days}, local {seconds:.0f} s")
        for example in examples[:10]:
            print("   ", example)
        failed = failed or raw_diff or elevation_diff or len(local) != len(public)
    if failed:
        raise SystemExit("NOT the same instrument — do not build the grid from it")
    print("parity: same instrument")


if __name__ == "__main__":
    main()
