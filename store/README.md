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

## Noch offen: Screenshots

Play verlangt mindestens zwei Telefon-Screenshots (16:9 oder 9:16, Kante
320–3840 px). Sinnvolle Auswahl:

1. Karte mit mehreren Spots (eigene grün, Freundes-Spots blau)
2. Spot-Detail mit Fundhistorie
3. Freundesliste oder geteilter Live-Standort
4. Statistik (Funde pro Jahr)

**Mit einem Wegwerf-Konto aufnehmen**, nicht mit dem eigenen — sonst stehen die
echten Fundorte im Store. Aus demselben Grund die Karte auf eine unverfängliche
Gegend schieben.
