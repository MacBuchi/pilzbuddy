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
| `screenshots/01…05` | 1080 × 1920 (9:16) PNG | Telefon-Screenshots |

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
| `01-karte.png` | Karte mit Spots — eigene mit grüner, Freundes-Spots mit blauer Boden-Ellipse |
| `02-spot-detail.png` | Spot-Detail mit Fundhistorie über vier Jahre |
| `03-freunde.png` | Freundesliste mit vier Buddies |
| `04-statistik.png` | Spots/Funde/Mehrfach besucht, „Funde pro Jahr", Top-Arten |
| `05-live-standort.png` | Live-Standort teilen (1/2/4 Stunden) |

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

Ein Screenshot ist übrigens die beste Bug-Suche: Issue #97 (zugelaufene
Y-Achse) und ein doppeltes Label an der Achsenspitze sind erst hier
aufgefallen, nicht im Test.
