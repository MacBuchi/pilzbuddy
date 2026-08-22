#!/usr/bin/env bash
# Der MECHANISCHE Teil der Store-Screenshots — Emulator herrichten,
# Standort setzen, Zoom stellen, aufnehmen, hinterher aufräumen.
#
# Was dieses Skript bewusst NICHT tut: sich durch die App klicken. Ein
# Navigationsskript hängt an Bildschirmkoordinaten und bricht bei jeder
# UI-Änderung — die FAB-Spalte etwa steckt seit dem neunten Knopf in
# einem `FittedBox(scaleDown)`, ein zehnter skaliert also jede einzelne
# Koordinate neu. Das verschöbe den Wartungsaufwand, statt ihn zu senken.
# Auch die Bildwahl bleibt Handarbeit: welcher Ausschnitt, welche Ebene,
# was gerade NICHT ins Bild soll (Golfplatz, fremde Beschriftungen) —
# das ist Urteilssache, kein Ablauf.
#
# Aus demselben Grund gibt es keinen CI-Job dazu. Pilzwetter und Regen
# rechnen sich täglich neu, die OSM-Kacheln ändern sich unter uns: Ein
# nächtlicher Lauf lieferte jedes Mal einen Diff, und ein Alarm, der
# immer angeht, wird nach dem dritten Mal weggeklickt.
#
# Gegenstück: tool/seed_screenshot_data.py legt die Spots an und setzt
# sie auf Ziel-Pixelpositionen. Verfahren und Hintergrund: store/README.md.

set -euo pipefail

ADB=${ADB:-$(command -v adb || echo /opt/homebrew/share/android-commandlinetools/platform-tools/adb)}
[ -x "$ADB" ] || { echo "adb nicht gefunden — ADB=<pfad> setzen" >&2; exit 1; }
[ -n "${ANDROID_SERIAL:-}" ] && ADB="$ADB -s $ANDROID_SERIAL"

# Play verlangt 16:9 oder 9:16; ein Pixel 7 Pro liefert von sich aus
# 1440x3120 und damit ein Seitenverhältnis, das die Konsole ablehnt.
WIDTH=1080
HEIGHT=1920
DENSITY=420

# Der EINZIGE eingebaute Koordinatentipp: der Knopf „auf mich zentrieren",
# unterster der FAB-Spalte, gemessen bei 1080x1920/420 am 2026-08-22.
# Ändert sich die Spalte, ist das hier die Stelle, die nachzumessen ist
# (aufnehmen, im Bild nachsehen, Zahlen ersetzen).
LOCATE_X=975
LOCATE_Y=1363

PKG=de.mcbuchi.pilzbuddy
OUT_DIR=${OUT_DIR:-store/screenshots}

demo() { $ADB shell am broadcast -a com.android.systemui.demo "$@" >/dev/null; }

usage() {
  cat <<'USAGE'
Aufruf: tool/store_screenshots.sh <befehl> [argumente]

  prepare              Auflösung 1080x1920, Dichte 420, saubere Statusleiste
  install              Play-Build bauen und aufspielen (ohne Update-Banner)
  goto <lon> <lat>     Standort setzen und die Karte darauf zentrieren
  zoom in|out [stufen] Maßstab ändern (MapLibre-Quick-Zoom, ohne Multitouch)
  restart              App neu starten — lädt die Spots neu, ohne Tippen
  shot <name>          Aufnehmen nach store/screenshots/<name>.png
  reset                Demo-Modus aus, Auflösung und Dichte zurück

Typischer Ablauf:

  tool/store_screenshots.sh prepare
  PB_EMAIL=… PB_PASSWORD=… python3 tool/seed_screenshot_data.py --seed
  tool/store_screenshots.sh restart
  tool/store_screenshots.sh goto 8.1275 47.9025
  tool/store_screenshots.sh zoom out 1
  # → aufnehmen, Marker im Bild nachmessen, mit --place setzen, restart
  tool/store_screenshots.sh shot 01-karte-spots
  tool/store_screenshots.sh reset
USAGE
}

cmd_prepare() {
  $ADB shell wm size "${WIDTH}x${HEIGHT}"
  $ADB shell wm density "$DENSITY"
  # Ohne Demo-Modus steht in der Statusleiste die Uhrzeit der Aufnahme und
  # ein halb geladener Akku — im Store fällt beides sofort auf.
  $ADB shell settings put global sysui_demo_allowed 1
  demo -e command enter
  demo -e command clock -e hhmm 0930
  demo -e command battery -e level 100 -e plugged false
  demo -e command network -e wifi show -e level 4 -e mobile hide
  demo -e command status -e location hide -e alarm hide -e bluetooth hide
  demo -e command notifications -e visible false
  echo "Emulator steht auf ${WIDTH}x${HEIGHT}/${DENSITY}, Statusleiste ist aufgeräumt."
}

cmd_install() {
  # PLAY_BUILD=true nimmt den Update-Hinweis heraus (den gibt es im
  # Play-Build nicht), --flavor ist seit 1.87.1 Pflicht.
  flutter build apk --release --flavor play --dart-define=PLAY_BUILD=true
  $ADB install -r build/app/outputs/flutter-apk/app-play-release.apk
}

cmd_goto() {
  local lon=$1 lat=$2
  # Der erste Fix wird gern verschluckt; drei kosten nichts.
  for _ in 1 2 3; do $ADB emu geo fix "$lon" "$lat" >/dev/null; sleep 1; done
  sleep 2
  $ADB shell input tap "$LOCATE_X" "$LOCATE_Y"
  sleep 4
  echo "Karte steht auf $lat, $lon."
}

cmd_zoom() {
  local dir=$1 steps=${2:-1} from to
  # `adb shell input` kann kein Multitouch, eine Pinch-Geste fällt also
  # aus. MapLibres Quick-Zoom kann es einhändig: tippen, sofort wieder
  # aufsetzen, ziehen. Rund 300 px je Stufe; der Aufsetzpunkt bleibt
  # stehen, deshalb die Bildmitte — so verschiebt sich die Karte nicht.
  local mid_x=$((WIDTH / 2)) mid_y=$((HEIGHT / 2 - 150)) px=$((300 * steps))
  case "$dir" in
    in)  from=$mid_y; to=$((mid_y + px)) ;;
    out) from=$mid_y; to=$((mid_y - px)) ;;
    *)   echo "zoom in|out" >&2; exit 1 ;;
  esac
  $ADB shell "input tap $mid_x $from; input swipe $mid_x $from $mid_x $to 300"
  sleep 3
  echo "Maßstab um $steps Stufe(n) nach $dir."
}

cmd_restart() {
  # Neu starten statt den Aktualisieren-Knopf zu tippen: Das holt die
  # Spots genauso frisch, hängt aber an keiner Koordinate.
  $ADB shell am force-stop "$PKG"
  sleep 1
  $ADB shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 8
  echo "App neu gestartet."
}

cmd_shot() {
  local name=${1:?Name fehlt}
  mkdir -p "$OUT_DIR"
  $ADB exec-out screencap -p > "$OUT_DIR/$name.png"
  local size
  size=$(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print('x'.join(map(str,struct.unpack('>II',d[16:24]))))" "$OUT_DIR/$name.png")
  echo "$OUT_DIR/$name.png ($size)"
  [ "$size" = "${WIDTH}x${HEIGHT}" ] || echo "  ! erwartet ${WIDTH}x${HEIGHT} — lief 'prepare'?" >&2
}

cmd_reset() {
  demo -e command exit || true
  $ADB shell wm size reset
  $ADB shell wm density reset
  echo "Emulator ist zurückgestellt."
}

case "${1:-}" in
  prepare) cmd_prepare ;;
  install) cmd_install ;;
  goto)    shift; cmd_goto "$@" ;;
  zoom)    shift; cmd_zoom "$@" ;;
  restart) cmd_restart ;;
  shot)    shift; cmd_shot "$@" ;;
  reset)   cmd_reset ;;
  *)       usage; [ -n "${1:-}" ] && exit 1 || exit 0 ;;
esac
