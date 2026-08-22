# Store-Grafiken

Assets für den Play-Store-Eintrag (#91). Nichts davon landet im Build — die
Dateien sind in keiner `pubspec.yaml`-Asset-Liste und deshalb vom Version Guard
ausgenommen (`.github/workflows/ci.yml`): ein neuer Screenshot soll kein Release
auslösen.

Die Antworten für das Data-Safety-Formular und die Listing-Texte stehen in
[`../docs/play-console.md`](../docs/play-console.md).

| Datei | Format | Play-Feld |
|---|---|---|
| `icon-512.png` | 512 × 512, 32-Bit PNG | App-Symbol |
| `feature-graphic.png` | 1024 × 500 PNG | Feature-Grafik |
| `feature-graphic.svg` | Quelle | — |
| `screenshots/01…06` | 1080 × 1920 (9:16) PNG | Telefon-Screenshots |

## Neu erzeugen

```bash
rsvg-convert -w 1024 -h 500 store/feature-graphic.svg -o store/feature-graphic.png

# App-Symbol aus derselben Quelle wie das Launcher-Icon
rsvg-convert -w 512 -h 512 assets/icon/icon.svg -o store/icon-512.png
ffmpeg -y -i store/icon-512.png -pix_fmt rgba store/icon-512.png
```

Die zweite Zeile beim Symbol ist kein Schnörkel: `icon.svg` ist deckend, deshalb
schreibt `rsvg-convert` ein 24-Bit-PNG — die Konsole verlangt 32 Bit. Und wie im
Design-Regelwerk beschrieben: **kein `qlmanage`**, das flacht Alpha auf Weiß ab.

Die Buddies in `feature-graphic.svg` sind unverändert aus
`assets/icon/icon_fg.svg` übernommen. Ändert sich das Icon, muss die
Feature-Grafik mit — im Store stehen beide nebeneinander.

## Screenshots

| Datei | Zeigt |
|---|---|
| `01-karte-spots.png` | Karte bei 100 m mit sechs Spots, je eine andere Artengruppe — Röhrling, Leistling, Schirmling, Stachelpilz, Wulstling, Bovist |
| `02-karte-pilzwetter.png` | Karwendel bei 10 km, Wald + Pilzwetter mit Legende |
| `03-spot-detail.png` | Spot-Detail mit Fundhistorie, Pilzwetter, Saisonkurve, Wald und Bäumen |
| `04-freunde.png` | Freundesliste mit vier Buddies |
| `05-statistik.png` | Spots/Funde/Mehrfach besucht, „Funde pro Jahr", Top-Arten |
| `06-live-standort.png` | Live-Standort teilen (1/2/4 Stunden) |

**Der erste zeigt Spots mit Arten, und das ist kein Zufall.** Bis dahin
stand die Pilzwetter-Ebene vorn — ein schönes Bild, das aber nicht sagt,
wofür die App da ist: Fundorte festhalten. In der Play-Suche entscheiden
die ersten beiden Bilder, und ein Datenteppich ohne einen einzigen Pilz
darauf beantwortet dort die falsche Frage. Play nimmt bis zu acht
Telefon-Screenshots; es ist also kein Entweder-oder.

Play verlangt mindestens zwei, 16:9 oder 9:16, Kante 320–3840 px.

### Wie sie entstanden sind

Alle mit **Wegwerf-Konten in einer erfundenen Gegend im Schwarzwald** — nie mit
einem echten Konto, sonst stehen die eigenen Fundorte im Store. Die Konten
(`*.shots@example.com`, `example.com` ist von der IANA reserviert) und ihre
Spots wurden danach über `delete_own_account()` wieder gelöscht.

```bash
# Emulator auf 9:16 zwingen — Pixel 7 Pro liefert sonst 1440x3120,
# und das ist kein von Play akzeptiertes Seitenverhältnis.
adb -s emulator-5554 shell wm size 1080x1920
adb -s emulator-5554 shell wm density 420
# Play-Build, damit der Update-Banner fehlt (den gibt es im Play-Build nicht)
flutter build apk --release --dart-define=PLAY_BUILD=true
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-release.apk
adb -s emulator-5554 emu geo fix 8.1305 47.9052   # Standort für „auf mich zentrieren"
adb -s emulator-5554 exec-out screencap -p > store/screenshots/xx.png
adb -s emulator-5554 shell wm size reset          # hinterher aufräumen
```

Seit #321 entstehen die Bilder auch auf dem **echten Pixel XL** (nativ
9:16, 1440 × 2560 → 1080 × 1920 skaliert). Beide Wege sind in Ordnung und
liegen nebeneinander im Store-Eintrag; die Bildqualität unterscheidet
sich nicht sichtbar.

**Saubere Statusleiste** — für beide Wege derselbe Griff, sonst steht dort
die Uhrzeit der Aufnahme und ein halb geladener Akku:

```bash
adb shell settings put global sysui_demo_allowed 1
D() { adb shell am broadcast -a com.android.systemui.demo "$@"; }
D -e command enter
D -e command clock -e hhmm 0930
D -e command battery -e level 100 -e plugged false
D -e command network -e wifi show -e level 4 -e mobile hide
D -e command status -e location hide -e alarm hide -e bluetooth hide
D -e command notifications -e visible false
# hinterher: D -e command exit
```

**Zoom ohne Finger.** `adb shell input` kann kein Multitouch, eine
Pinch-Geste fällt also aus. MapLibres Quick-Zoom kann es dafür einhändig:
tippen, dann sofort ein zweites Mal aufsetzen und ziehen — **nach unten
zoomt hinein, nach oben heraus**, rund 300 px je Zoomstufe. Der Punkt, an
dem der Finger aufsetzt, bleibt stehen; tippt man also die Bildmitte an,
verschiebt sich die Karte beim Zoomen nicht:

```bash
adb shell 'input tap 540 810; input swipe 540 810 540 510 300'   # eine Stufe heraus
```

**Wo die Marker landen, wird gerechnet, nicht geschoben.** Für
`01-karte-spots.png` sind die sechs Spots im Testkonto über die
REST-API angelegt und danach auf Ziel-Pixelpositionen umgesetzt worden
(Skript in der Sitzung, nicht im Repo): Aus zwei sichtbaren Markern lässt
sich die Abbildung Pixel↔Grad messen und umkehren. Nur so bleiben die
Icons zuverlässig weg von der FAB-Spalte, dem „Neuer Spot"-Knopf und dem
Hinweisband — von Hand tippend trifft man das nicht reproduzierbar.

Ein Screenshot ist übrigens die beste Bug-Suche: Issue #97 (zugelaufene
Y-Achse) und ein doppeltes Label an der Achsenspitze sind erst hier
aufgefallen, nicht im Test.
