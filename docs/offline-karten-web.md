# Offline-Karten im Browser

**Stand:** 2026-09-21 · **Issue:** #496 · **Werkzeug:** `tool/map_tiles.py`,
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

## Was offen ist: die Messung

Ob ein Gebiet unter 100 MB passt, ist keine Schätzung. `map-data.yml` hat
deshalb zwei Modi, und `plan` ist die Vorgabe:

- **`plan`** lädt keine Kacheln, sondern nur Header und die
  Verzeichnisse, die das Gebiet überhaupt berühren, und schreibt Bytes je
  Zoom und je Gebiet in die Run-Summary. Veröffentlicht nichts.
  **Wie viel das ist, sagt der Lauf selbst** — die letzte Zeile jeder
  Messung ist `read N bytes in M requests`. Gegen die mitgelieferte
  Übersicht sind es 371 Bytes in 2 Anfragen; gegen den PLANETEN bei z14
  wird es deutlich mehr, denn die Hilbert-Kurve zerlegt ein Rechteck wie
  DACH in viele getrennte Abschnitte, und jeder davon zieht eigene
  Leaf-Verzeichnisse nach sich. Hier stand zuerst „wenige hundert KB" —
  das war für den Planeten geraten und ist damit genau die Sorte Zahl,
  gegen die dieses Werkzeug gebaut ist. Die echte Zahl steht nach dem
  ersten Lauf in der Run-Summary und gehört dann hierher.
- **`publish`** schneidet die Auszüge mit dem offiziellen `pmtiles`,
  prüft jeden gegen seine Quelle und spiegelt sie auf
  `map-data-mirror`.

`tool/map_areas.json` steht bewusst auf **einem** Gebiet (DACH). Achtzehn
Bundesland-Bboxen von Hand einzutragen, bevor die Messung vorliegt, hieße
zweimal raten: beim Zuschnitt UND bei den Zahlen, die ihn entscheiden. Eine
falsche Bbox ist schlimmer als keine — sie veröffentlicht eine Karte, die
genau dort leer ist, wo jemand läuft.

**Nächster Schritt:** `Map Data` im Modus `plan` starten. Das Ergebnis sagt,
ob DACH bei z12/z13/z14 in eine Datei passt oder in wie viele.

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
Zusätzlich läuft `info` dort gegen die **echte** mitgelieferte Übersicht:
Ein synthetisches Fixture prüft nur, ob unser Leser zu unserem eigenen
Test-Schreiber passt — beide könnten dieselbe falsche Annahme tragen.
