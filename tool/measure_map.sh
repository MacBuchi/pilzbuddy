#!/usr/bin/env bash
set -euo pipefail

# Frame- und Speicher-Messung der Karte am angeschlossenen Gerät —
# die Messprozedur des Engine-Direktvergleichs (docs/map-performance.md).
#
#   tool/measure_map.sh trace <label> [dauer_s]   # Perfetto FrameTimeline
#   tool/measure_map.sh mem   <label> [minuten]   # meminfo-Verlauf als CSV
#
# Ablauf eines Frame-Messlaufs:
#   1. Profile-Build der App öffnen (der Kamerafahrt-Knopf existiert nur
#      in Debug/Profile), Karte sichtbar, gewünschte Engine im Profil
#      gewählt.
#   2. `trace <label>` starten und SOFORT die Kamerafahrt antippen —
#      die Fahrt dauert ~55 s, die Voreinstellung (70 s) deckt sie ab.
#   3. Auswerten: python3 tool/analyze_map_trace.py build/map_traces/<label>.pftrace
#
# Warum Perfetto mit SurfaceFlinger FrameTimeline: Flutters Frame-Timings
# und `gfxinfo` sehen nur das Flutter-Rendering — der native GL-Thread
# der MapLibre-Engine ist für beide unsichtbar. FrameTimeline misst
# end-to-end pro PRÄSENTIERTEM Frame, für jede Ebene des App-Prozesses
# (Flutter-Surface UND die SurfaceView der Platform-View), und braucht
# weder Root noch eine debugfähige App.

ADB=${ADB:-$(command -v adb || true)}
if [[ -z "$ADB" ]]; then
  ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
fi
PKG=de.mcbuchi.pilzbuddy
OUT_DIR=build/map_traces
mkdir -p "$OUT_DIR"

case "${1:-}" in
  trace)
    label=${2:?Aufruf: tool/measure_map.sh trace <label> [dauer_s]}
    dur_s=${3:-70}
    device_path=/data/misc/perfetto-traces/map_"$label".pftrace
    # Konfig über stdin (-c -): kein Push nötig, und die Datei landet im
    # einzigen Verzeichnis, in das der traced-Dienst schreiben darf.
    "$ADB" shell perfetto -c - --txt -o "$device_path" <<EOF
buffers { size_kb: 65536 fill_policy: RING_BUFFER }
data_sources { config { name: "android.surfaceflinger.frametimeline" } }
duration_ms: $((dur_s * 1000))
EOF
    "$ADB" pull "$device_path" "$OUT_DIR/$label.pftrace"
    "$ADB" shell rm "$device_path"
    echo "Trace: $OUT_DIR/$label.pftrace"
    ;;
  gestures)
    # Deterministische Wisch-Choreographie (~32 s) für den Gesten-Trace:
    # sechs Pans in wechselnden Richtungen plus zwei Flings, zweimal.
    # Koordinaten für 1080×2340, mittlerer Bildbereich (keine FABs, keine
    # Navigationsleiste). Während eines Wischens muss die Karte jeden
    # Takt liefern — das ist der Moment, in dem Ruckeln spürbar ist.
    for _ in 1 2; do
      "$ADB" shell input swipe 700 1100 200 1100 800; sleep 0.4
      "$ADB" shell input swipe 200 1100 700 1100 800; sleep 0.4
      "$ADB" shell input swipe 450 1500 450 700 800;  sleep 0.4
      "$ADB" shell input swipe 450 700 450 1500 800;  sleep 0.4
      "$ADB" shell input swipe 300 800 700 1500 800;  sleep 0.4
      "$ADB" shell input swipe 700 1500 300 800 800;  sleep 0.4
      "$ADB" shell input swipe 700 1200 150 1200 120; sleep 1.5
      "$ADB" shell input swipe 150 1200 700 1200 120; sleep 1.5
    done
    echo "Gesten-Choreographie fertig"
    ;;
  mem)
    label=${2:?Aufruf: tool/measure_map.sh mem <label> [minuten]}
    minutes=${3:-10}
    out="$OUT_DIR/mem_$label.csv"
    echo "t_s,total_pss_kb,graphics_kb,native_heap_kb,java_heap_kb" > "$out"
    # Alle 30 s eine Stichprobe aus dem App Summary von dumpsys meminfo —
    # TOTAL PSS enthält auch den Grafikspeicher (die Achse, auf der die
    # ANR-Berichte aus #142 lagen).
    for ((i = 0; i <= minutes * 2; i++)); do
      "$ADB" shell dumpsys meminfo "$PKG" | awk -v t=$((i * 30)) '
        /Java Heap:/   { jh = $3 }
        /Native Heap:/ { nh = $3 }
        /Graphics:/    { g = $2 }
        /TOTAL PSS:/   { tot = $3 }
        END { printf "%d,%s,%s,%s,%s\n", t, tot, g, nh, jh }' >> "$out"
      ((i < minutes * 2)) && sleep 30
    done
    echo "Speicher-Verlauf: $out"
    ;;
  *)
    echo "Aufruf: tool/measure_map.sh trace|mem <label> [dauer_s|minuten]" >&2
    exit 1
    ;;
esac
