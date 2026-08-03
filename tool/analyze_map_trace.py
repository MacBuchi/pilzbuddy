#!/usr/bin/env python3
"""Wertet einen Perfetto-Trace der Karten-Messläufe aus (FrameTimeline).

Aufruf:  python3 tool/analyze_map_trace.py build/map_traces/<label>.pftrace

Benötigt das PyPI-Paket `perfetto` (lädt beim ersten Lauf den passenden
trace_processor von get.perfetto.dev nach):  pip install perfetto

Gemessen werden die DISPLAY-Frames von SurfaceFlinger — was wirklich auf
dem Panel präsentiert wurde, end-to-end. Warum nicht die App-eigenen
Surface-Frames: Die gibt es in der FrameTimeline nur für Apps, die ihre
Buffer mit Vsync-IDs taggen (HWUI). Flutter tut das nicht, die GL-Surface
der MapLibre-Platform-View auch nicht — beide Engines sind dort
unsichtbar, die Display-Frames sehen dagegen jede präsentierte Änderung.
Während eines Messlaufs animiert nichts außer der Karte; die
Display-Kadenz IST also die Karten-Kadenz (Gegenprobe im Trace: die
einzigen getaggten Fremd-Frames kamen von der StatusBar, zwei Stück).

Kennzahlen:
- Vsync-Periode aus dem Trace selbst (Modus der Abstände erwarteter
  Präsentationszeiten) — die reale Refresh-Rate, keine Annahme.
- Präsentationsabstände in AKTIVEN Phasen (Abstand < 250 ms; größere
  Lücken sind Haltezeiten der Choreographie, kein Ruckeln): p50/p95/p99
  in ms und in Vsync-Einheiten. Das Wett-Kriterium »p99 <= 1 Vsync«
  heißt: Selbst am 99. Perzentil folgt der nächste Frame im Takt.
- Jank-Klassifikation von SurfaceFlinger pro Frame, plus die längste
  Folge aufeinanderfolgender Jank-Frames (»Burst«).
"""

import collections
import json
import statistics
import sys

ACTIVE_GAP_MS = 250.0


def percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    k = (len(ordered) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(ordered) - 1)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (k - lo)


def main(path):
    from perfetto.trace_processor import TraceProcessor

    tp = TraceProcessor(trace=path)
    # Display-Frames: surface_frame_token IS NULL. Erwartete und
    # tatsächliche Zeitleiste über das display_frame_token verbunden.
    rows = list(tp.query("""
        SELECT a.ts + a.dur AS actual_present,
               e.ts + e.dur AS expected_present,
               a.jank_type AS jank_type
        FROM actual_frame_timeline_slice a
        JOIN expected_frame_timeline_slice e
          ON a.display_frame_token = e.display_frame_token
         AND a.upid = e.upid
         AND e.surface_frame_token IS NULL
        WHERE a.surface_frame_token IS NULL
        ORDER BY actual_present
    """))
    if not rows:
        sys.exit('Keine Display-Frames im Trace — FrameTimeline-Quelle an?')

    expected = sorted(r.expected_present for r in rows)
    deltas = [round((b - a) / 1e5) / 10 for a, b in zip(expected, expected[1:])
              if 0 < (b - a) < 30e6]
    # Panel-Takt: Modus des SCHNELLEN Clusters (<= 13 ms, also 120/90 Hz).
    # Ein LTPO-Panel taktet herunter, wenn die App nicht liefert — der
    # Gesamt-Modus wäre dann der heruntergetaktete Verlegenheitswert, und
    # »p99 in Vsyncs« sähe besser aus, je schlechter die Engine liefert.
    fast = [d for d in deltas if d <= 13]
    if len(fast) >= 20:
        vsync_ms, vsync_source = (
            collections.Counter(fast).most_common(1)[0][0], 'fast-cluster')
    else:
        vsync_ms, vsync_source = (
            collections.Counter(deltas).most_common(1)[0][0], 'overall-mode')

    presents = [r.actual_present for r in rows]
    intervals = [(b - a) / 1e6 for a, b in zip(presents, presents[1:])
                 if 0 < (b - a) < ACTIVE_GAP_MS * 1e6]

    jank_counts = collections.Counter(
        r.jank_type for r in rows
        if r.jank_type not in (None, 'None', 'Non Animating'))
    burst = longest = 0
    for r in rows:
        janky = r.jank_type not in (None, 'None', 'Non Animating')
        burst = burst + 1 if janky else 0
        longest = max(longest, burst)

    span_s = (presents[-1] - presents[0]) / 1e9
    p = {k: percentile(intervals, k) for k in (50, 95, 99)}
    print(json.dumps({
        'trace': path,
        'vsync_ms': vsync_ms,
        'vsync_source': vsync_source,
        'span_s': round(span_s, 1),
        'frames_presented': len(rows),
        'active_intervals': len(intervals),
        'interval_ms': {
            'p50': round(p[50], 2),
            'p95': round(p[95], 2),
            'p99': round(p[99], 2),
            'max': round(max(intervals), 2),
            'mean': round(statistics.mean(intervals), 2),
        },
        'interval_vsyncs': {
            'p50': round(p[50] / vsync_ms, 2),
            'p95': round(p[95] / vsync_ms, 2),
            'p99': round(p[99] / vsync_ms, 2),
        },
        'jank_types': dict(jank_counts),
        'longest_jank_burst': longest,
    }, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
