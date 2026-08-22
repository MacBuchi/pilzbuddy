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

| Datei | Stand | Zeigt |
|---|---|---|
| `01-karte-spots.png` | 1.99.1 | Karte bei 100 m mit sechs Spots, je eine andere Artengruppe — Röhrling, Leistling, Schirmling, Stachelpilz, Wulstling, Bovist |
| `02-karte-pilzwetter.png` | 1.96.0 | Karwendel bei 10 km, Wald + Pilzwetter mit Legende |
| `03-spot-detail.png` | 1.96.0 | Spot-Detail mit Fundhistorie, Pilzwetter, Saisonkurve, Wald und Bäumen |
| `04-freunde.png` | 1.26.0 | Freundesliste mit vier Buddies |
| `05-statistik.png` | 1.99.1 | Spots/Funde/Mehrfach besucht, „Funde pro Jahr", Top-Arten |
| `06-live-standort.png` | 1.99.1 | Live-Standort teilen (1/2/4 Stunden) |

`04-freunde.png` steht bewusst noch auf 1.26.0: Die Freundesliste lässt
sich nur mit echten Buddy-Konten zeigen, und die Wegwerf-Konten von damals
sind gelöscht. Neue anzulegen hieße vier Registrierungen samt Bestätigungs-
mails — gegen ein Limit von 3/h, und die Codes liegen in Postfächern, auf
die niemand hier Zugriff hat. Der Bildschirm selbst hat sich seit 1.26.0
nicht verändert; das Bild ist also alt, aber nicht falsch.

**Die Spalte „Stand" ist nicht Zierde.** `tool/screenshot_stand.py` liest sie
und schreibt beim Befördern eines Releases in die Run-Summary, wie alt das
älteste Bild ist — an der einen Stelle, an der ohnehin jemand hinsieht. Ein
Tor ist es bewusst nicht: Ein Bild kann drei Versionen alt und trotzdem
richtig sein. Wer einen Screenshot erneuert, trägt hier die Version ein, mit
der er aufgenommen wurde.

**Der erste zeigt Spots mit Arten, und das ist kein Zufall.** Bis dahin
stand die Pilzwetter-Ebene vorn — ein schönes Bild, das aber nicht sagt,
wofür die App da ist: Fundorte festhalten. In der Play-Suche entscheiden
die ersten beiden Bilder, und ein Datenteppich ohne einen einzigen Pilz
darauf beantwortet dort die falsche Frage. Play nimmt bis zu acht
Telefon-Screenshots; es ist also kein Entweder-oder.

Play verlangt mindestens zwei, 16:9 oder 9:16, Kante 320–3840 px.

### Wie sie entstanden sind

Alle mit **Testkonten in einer erfundenen Gegend im Schwarzwald** — nie mit
einem echten Konto, sonst stehen die eigenen Fundorte im Store. Die ersten
Bilder entstanden mit Wegwerf-Konten (`*.shots@example.com`, `example.com`
ist von der IANA reserviert), die danach über `delete_own_account()` wieder
gelöscht wurden; seit #321 dient das gesäte Testkonto als Kulisse.

Zwei Werkzeuge nehmen den mechanischen Teil ab:

```bash
tool/store_screenshots.sh prepare          # 1080x1920, Dichte 420, saubere Statusleiste
PB_EMAIL=… PB_PASSWORD=… python3 tool/seed_screenshot_data.py --seed
tool/store_screenshots.sh restart          # App neu starten, damit sie die Spots holt
tool/store_screenshots.sh goto 8.1275 47.9025
tool/store_screenshots.sh zoom out 1
tool/store_screenshots.sh shot 01-karte-spots
tool/store_screenshots.sh reset            # Auflösung und Demo-Modus zurück
```

Die Zugangsdaten des Testkontos stehen im Austauschordner, nicht im Repo.

**Was die Werkzeuge bewusst NICHT tun: sich durch die App klicken.** Ein
Navigationsskript hängt an Bildschirmkoordinaten und bricht bei jeder
UI-Änderung — die FAB-Spalte etwa steckt seit dem neunten Knopf in einem
`FittedBox(scaleDown)`, ein zehnter skalierte also jede Koordinate neu.
Und die Bildwahl ist ohnehin Urteilssache: welcher Ausschnitt, welche
Ebene, was gerade nicht ins Bild soll. Für `01-karte-spots.png` hieß das
etwa, den Golfplatz samt „Driving Range" aus dem Rahmen zu halten.

Aus demselben Grund gibt es **keinen CI-Job**, der die Bilder nachzieht:
Pilzwetter und Regen rechnen sich täglich neu, die OSM-Kacheln ändern
sich unter uns. Jeder Lauf brächte einen Diff, und ein Alarm, der immer
angeht, wird nach dem dritten Mal weggeklickt. Statt Nachziehen also
Sichtbarmachen — die Spalte „Stand" oben und `tool/screenshot_stand.py`.

Drei Dinge, die im Skript stecken und die man sonst wieder herausfinden muss:

- **Saubere Statusleiste** über SystemUIs Demo-Modus. Ohne ihn steht dort
  die Uhrzeit der Aufnahme und ein halb geladener Akku — im Store fällt
  beides sofort auf.
- **Zoom ohne Finger.** `adb shell input` kann kein Multitouch, eine
  Pinch-Geste fällt also aus. MapLibres Quick-Zoom kann es einhändig:
  tippen, sofort ein zweites Mal aufsetzen und ziehen — **nach unten
  zoomt hinein, nach oben heraus**, rund 300 px je Stufe. Der Aufsetzpunkt
  bleibt stehen; tippt man die Bildmitte an, verschiebt sich die Karte
  beim Zoomen nicht.
- **Neu starten statt „Aktualisieren" tippen.** Holt die Spots genauso
  frisch, hängt aber an keiner Koordinate.

**Wo die Marker landen, wird gerechnet, nicht geschoben.** Aus zwei im
Bild ausgemessenen Markern bestimmt `seed_screenshot_data.py --place` die
Abbildung Pixel↔Grad, kehrt sie um und setzt jeden Spot auf seine
Ziel-Pixelposition:

```bash
python3 tool/seed_screenshot_data.py --place \
    --ref 47.9040,8.1245=175,612 --ref 47.9015,8.1300=845,1065
```

Nur so bleiben die Icons zuverlässig weg von der FAB-Spalte, dem
„Neuer Spot"-Knopf und dem Hinweisband — von Hand tippend trifft man das
nicht reproduzierbar, und beim nächsten Mal schon gar nicht wieder. Ein
falsch abgelesener Bezugspunkt meldet sich dabei selbst: In Mercator
kostet ein Grad Breite um `1/cos(Breite)` mehr Pixel als ein Grad Länge,
und das rechnet das Werkzeug gegen.

Seit #321 entstehen Bilder auch auf dem **echten Pixel XL** (nativ 9:16,
1440 × 2560 → 1080 × 1920 skaliert). Beide Wege sind in Ordnung und liegen
nebeneinander im Store-Eintrag; die Bildqualität unterscheidet sich nicht
sichtbar. Hinterher `--cleanup` nicht vergessen, sonst stehen erfundene
Fundorte im Testkonto — und weil es seine Spots mit Freunden teilt, sähen
sie auch andere.

Ein Screenshot ist übrigens die beste Bug-Suche: Issue #97 (zugelaufene
Y-Achse) und ein doppeltes Label an der Achsenspitze sind erst hier
aufgefallen, nicht im Test.
