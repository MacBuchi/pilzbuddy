# Offline-Karten im Browser

**Stand:** 2026-09-22 · **Issue:** #496 · **Werkzeug:** `tool/map_tiles.py`,
`.github/workflows/map-data.yml`

## Die Frage

Die PWA hat eine Offline-Karte, aber nur die mitgelieferte DACH-Übersicht,
und die endet bei z7. Darüber skaliert der Renderer hoch — im Wald sieht
man Autobahnen und Ortsnamen und sonst nichts. Wie kommt feine
Kartendarstellung (bis z14) ohne Empfang in den Browser?

## Was NICHT geht, und warum

**Die Android-Regionskarten.** Sie sind Release-Anhänge des fremden Repos
`whitespring/project-nomad-maps-europe` und scheitern im Browser an zwei
voneinander unabhängigen Wänden: kein `access-control-allow-origin`
(gemessen 2026-09-03, weder auf der 302 von `github.com` noch am Ziel
`release-assets.githubusercontent.com`), und 44 MB bis 2,01 GB je Datei.
Jede der beiden Hürden allein reichte aus.

**Eine feinere mitgelieferte Übersicht.** Gemessen am vorhandenen Asset
(`tool/map_tiles.py plan`, 2026-09-21):

| Zoom | Kacheln | Bytes | Schritt |
|---|---|---|---|
| z5 | 4 | 388,5 KB | 3,1x |
| z6 | 12 | 1,0 MB | 2,7x |
| z7 | 36 | 6,6 MB | **6,4x** |

z7 allein ist 77 % der Datei. **Bytes je Zoom wachsen nicht um 4x, sondern
um das, was die Datendichte tut** — wer „eine Stufe mehr, viermal so viel"
rechnet, unterschätzt genau die oberste Stufe, und die ist die ganze
Rechnung. z9 läge grob bei hundert MB, z10 bei mehreren hundert, in jedem
APK und jedem Web-Build.

**MapLibre GL JS.** Tauschte den Zeichner, nicht die Datenquelle. Das Web
rendert längst Vektorkacheln (flutter_map + vector_map_tiles, dieselbe
Strecke wie die Übersicht seit 1.114.2). Die Lücke sind die Daten.

## Der Weg: Range-Anfragen gegen ein gehostetes Archiv

`PmTilesArchive.fromUri` liest aus einem PMTiles-Archiv **nur die Kacheln,
die es braucht** — vorausgesetzt, der Host beantwortet Range-Anfragen und
schickt CORS. Die Dateigröße betrifft dann nur noch das Hosting, nicht den
Client.

Gemessen am 2026-09-21 gegen `raw.githubusercontent.com`
(Branch `rain-data-mirror`, den dieses Repo ohnehin betreibt):

```
HTTP/2 206
accept-ranges: bytes
content-range: bytes 0-99/10061
access-control-allow-origin: *
```

Genau das, was gebraucht wird. **Der Preis ist eine harte Grenze von
100 MB je Datei** — git nimmt keinen größeren Blob an, also kann raw
keinen ausliefern.

**Das ist der Host.** Ein Objektspeicher wie Cloudflare R2 könnte die
vollen Regionen tragen, kostet aber ein Konto, ein Secret und ab etwa
10 GB Geld; `docs/finanzierung-und-skalierung.md` hält fest, dass 0 €/Monat
eine bewusste Architekturentscheidung ist und keine Zufälligkeit. Der
Spiegel-Branch braucht nichts davon und folgt einem Muster, das seit
#365/#366 läuft.

## Die Messung — und was sie ergeben hat

Ob ein Gebiet unter 100 MB passt, ist keine Schätzung. `map-data.yml` hat
deshalb zwei Modi, und `plan` ist die Vorgabe:

- **`plan`** lädt keine Kacheln, sondern nur Header und die
  Verzeichnisse, die das Gebiet überhaupt berühren, und schreibt Bytes je
  Zoom und je Gebiet in die Run-Summary. Veröffentlicht nichts.
- **`publish`** schneidet die Auszüge mit dem offiziellen `pmtiles`,
  prüft jeden gegen seine Quelle und spiegelt sie auf
  `map-data-mirror`.

**Gemessen am 2026-09-22** gegen `build.protomaps.com/20260922.pmtiles`,
DACH als EIN Archiv (Läufe
[#1](https://github.com/MacBuchi/pilzbuddy/actions/runs/35758853942) und
[#2](https://github.com/MacBuchi/pilzbuddy/actions/runs/35763247618), Zahl
für Zahl gleich):

| bestellt | gemessen | geschätzte Datei | Messung kostete | Urteil |
|---|---|---|---|---|
| z8 | z0–z8 | **30,5 MB** | 144,5 KB in 3 Anfragen | passt (31 %) |
| z10 | z0–z10 | 260,4 MB | 374,1 KB in 5 | 2,6x über |
| z11 | z0–z11 | 610,0 MB | 648,4 KB in 7 | 6,1x über |
| z12 | z0–z12 | 1,39 GB | 922,3 KB in 9 | 14,3x über |
| z13 | z0–z13 | 2,87 GB | 1,4 MB in 13 | 29,4x über |
| z14 | z0–z14 | **5,54 GB** | 3,0 MB in 26 | 56,7x über |

**Als eine Datei auf raw passt nur z8.** Das Ziel dieses Dokuments ist
z14, und das sind 5,54 GB — bei 100 MB je Datei **mindestens 57 Dateien**,
in Wirklichkeit mehr, weil ein Schnitt Kachelgrenzen folgt und nicht
Bytes. Die Aufteilung ist damit keine Möglichkeit mehr, sondern eine
Bedingung, solange raw der Host ist.

Und sie widerlegt die Annahme, mit der #496 angetreten war: eine einzige
`dach.pmtiles` bei maxzoom 12 mit rund 73 MB. Gemessen sind es 1,39 GB,
Faktor 19. Die Zahl war nie gemessen — genau die Sorte Zahl, gegen die
dieses Werkzeug gebaut ist.

**Was die Messung selbst kostet, steht jetzt neben ihr.** Hier stand
zuerst „wenige hundert KB"; das war für den Planeten geraten. Für z8 bis
z12 lag die Schätzung grob richtig, für z13 und z14 zu niedrig — also
ausgerechnet dort, wo die Entscheidung fällt. Der Anstieg ist nicht die
Dateigröße, sondern die Hilbert-Kurve: Sie zerlegt ein Rechteck wie DACH
in immer mehr getrennte Abschnitte, und jeder zieht eigene
Leaf-Verzeichnisse nach sich — 3 Anfragen bei z8, 26 bei z14. Drei MB, um
5,54 GB zu vermessen, ohne sie zu laden.

`tool/map_areas.json` steht weiterhin auf **einem** Gebiet (DACH). Das war
richtig, solange die Messung fehlte, und wird erst dann falsch, wenn der
Host feststeht: Bei raw braucht es Dutzende Bboxen, bei einem
Objektspeicher ohne Größengrenze gar keine.

**Nächster Schritt ist keine Messung mehr, sondern eine Entscheidung** —
und sie hat drei Ausgänge:

1. **Aufteilen auf raw.** Dutzende Gebietsdateien plus ein Gebietsindex in
   der App, dazu die Frage, was mit einem Ausschnitt über einer
   Gebietsgrenze passiert. Kostet kein Geld, und die Komplexität landet
   genau in dem Teil, der ohne Empfang funktionieren muss.
2. **Zoomziel senken.** z8 in einer Datei ist heute machbar. Es löst aber
   nicht das Problem, aus dem dieses Dokument entstanden ist — „im Wald
   sieht man Autobahnen und Ortsnamen und sonst nichts".
3. **Ein Host ohne die 100-MB-Grenze** (Cloudflare R2). Der sauberste Weg
   für „Ausschnitt laden", und zwar aus einem Grund, der erst durch die
   Messung sichtbar wird: Der Mechanismus wollte nie vorgeschnittene
   Archive, er liest Bereiche aus EINER Datei. Die 100-MB-Grenze ist das
   Einzige, was den Schnitt erzwingt, und der Schnitt ist das Einzige, was
   den Gebietsindex erzwingt. Der Preis ist ein Konto, ein Secret und ab
   etwa 10 GB Geld.

## Was danach kommt (App-Seite)

Zwei Mechanismen, die sich ergänzen; beide brauchen dieselbe Quelle.

1. **„Ausschnitt laden"** — der Kartenausschnitt ist der Gebietswähler,
   nicht der Spot. Man schiebt die Karte dorthin, wo man hinwill, und
   tippt. **Die Größe steht vorher fest und ist exakt**: das
   PMTiles-Verzeichnis nennt die Bytezahl jeder Kachel. Das ist die
   Antwort auf „ich bin in einem neuen Gebiet und nicht am Spot" — wenige
   MB laden noch auf der Anfahrt, eine 900-MB-Region nicht.
2. **Alles Gesehene bleibt liegen** — sobald die Web-Onlinekarte
   Vektorkacheln vom eigenen Host liest, landet jede geholte Kachel in
   IndexedDB, mit Obergrenze und Verdrängung der ältesten.

Dabei gelten die Regeln, die für den Ausgangskorb schon stehen:
`navigator.storage.persist()` beim ersten Laden erfragen und nicht beim
Start, Speicher in `browser_db.dart` eintragen und `kBrowserDbVersion`
erhöhen, ohne IndexedDB ein `NoTileStore` wie `NoSpotCache`. Und: **ein
Browser darf ohne Vorwarnung räumen** (Safari nach 7 Tagen ohne Nutzung) —
die Karte muss es sagen, statt still wieder grob zu werden.

**OSM-Rasterkacheln kommen für beides nicht in Frage.** Die
Web-Onlinekarte holt heute `tile.openstreetmap.org`, und deren
Nutzungsbedingungen verbieten Massendownload und Vorladen. Der eigene
Vektor-Host ist damit Bedingung für beide Mechanismen, nicht nur für den
ersten.

## Das Werkzeug

`tool/map_tiles.py` liest PMTiles v3 mit der Standardbibliothek — `struct`,
`gzip`, eine Varint-Schleife — und hat drei Modi: `info`, `plan`, `check`.

**Es schreibt bewusst keine Produktionsarchive.** Schneiden ist
`pmtiles extract`, das offizielle Go-Werkzeug, das CLAUDE.md für die
Übersicht ohnehin nennt. Ein selbstgebauter Schreiber wäre eine zweite
Umsetzung eines Formats, das uns nicht gehört, und ein leicht kaputtes
Archiv scheitert im Browser, nicht in CI.

Zwei Fallen, gegen die `check` und `HttpSource` da sind:

- **Ein Auszug mit den falschen Kacheln ist ein gültiges Archiv.** Eine
  falsche Bbox oder eine veraltete Quelle erzeugt keine Fehlermeldung,
  sondern eine Karte, die stellenweise leer ist. `check` prüft deshalb
  **zwei Richtungen**, und nur eine davon ist die naheliegende:
  *Einschluss* — was im Auszug steht, ist Byte für Byte die Quelle;
  *Abdeckung* — was die Quelle INNERHALB der bestellten Bbox hat, steht
  auch im Auszug. Einschluss allein war die Falle: Er zieht die
  Stichprobe aus dem, was der Auszug enthält, und ein Auszug der falschen
  Region besteht ihn mit jeder einzelnen Probe. Genau der Fehler, den der
  Absatz verspricht zu fangen, war der, den er nicht sehen konnte.
  Bbox und Maxzoom sind deshalb Pflichtargumente und kommen aus dem, was
  BESTELLT war (`tool/map_areas.json`) — den Header des Auszugs zu
  befragen hieße, den Verdächtigen nach seinem Alibi zu fragen. Die
  Stichprobe hat ein festes Budget je Zoom und nimmt die vier Ecken
  zuerst: proportional gezogen sähe sie nur die oberste Stufe, und ein
  falscher Zuschnitt verliert zuerst seine Ränder.
- **Ein Server, der `Range` ignoriert, antwortet mit 200 und der ganzen
  Datei.** Das lokal zu zerschneiden sähe nach Erfolg aus, während ein
  Planet-Build durch die Leitung geht. `HttpSource` behandelt alles außer
  206 als harten Fehler.

Der Self-Test läuft netzfrei im Job „Analyze & Test" und fährt dafür einen
Loopback-HTTP-Server, der `Range` einmal beachtet und einmal ignoriert.
Zusätzlich laufen dort `info`, `plan` und `check` gegen die **echte**
mitgelieferte Übersicht: Ein synthetisches Fixture prüft nur, ob unser
Leser zu unserem eigenen Test-Schreiber passt — beide könnten dieselbe
falsche Annahme tragen.

**`info` allein reichte dafür nicht**, und das war eine eigene Lücke: Es
liest Header und Metadaten und fasst nie ein Verzeichnis an — also genau
den verwickelten Teil nicht (Varints, delta-kodierte `tile_id`,
`run_length`, Leaf-Rekursion, Hilbert-Kurve). `plan` läuft durch den
ganzen Baum, und `check` der Datei gegen SICH SELBST übt zusätzlich
`find()` und das Lesen echter Kachelbytes.
