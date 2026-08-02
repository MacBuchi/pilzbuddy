# Karte, Speicher und ANRs — was gemessen ist

Die Karte ist der einzige Teil der App, der sie umbringen kann. Diese Seite
sammelt, welche Stellschrauben es gibt, welche Zahl hinter ihrem heutigen Wert
steht — und wie die ANR-Frage (#151) am 2026-08-02 durch eine Live-Messung
aufgelöst wurde. Sie existiert, weil die Triage zu #157 einen Vorschlag
gemacht hat, der genau die Einstellung zurückgedreht hätte, die #142 nach
einer Messung gesetzt hat — und weil das ohne diese Seite wieder passiert.

## Die Grundregel

**Kein Wert in dieser Tabelle wird ohne vorherige Messung verändert.** Jeder
einzelne ist ein Tausch: weniger Speicher gegen mehr Nachladen, oder
umgekehrt. Wer einen davon anfasst, weil ein Symptom danach klingt, tauscht
ein sichtbares Problem gegen ein tödliches.

## Die Stellschrauben

Alle in `lib/features/map/map_screen.dart`.

| Wo | Wert | Woher |
|---|---|---|
| Online-OSM `keepBuffer` | 2 | #142. Vorher 3 (aus #130). |
| Online-OSM `panBuffer` | 1 | #142. Vorher 2 (aus #130). |
| Basiskarte `maximumTileSubstitutionDifference` | 1 | #142. Vorher 3 (aus #118). |
| Basiskarte `layerMode` | `raster` | #119. |
| Detailkarte `maximumTileSubstitutionDifference` | 1 | #142. |
| Detailkarte `layerMode` | `vector` | Schärfe; A/B in #151 bestätigt. |
| Detailkarte `maximumZoom` | 19 | Daten enden bei ~15, darüber skaliert. |
| alle `memoryTileCacheMaxSize` | 10 MB (Default) | nie gemessen |
| alle `memoryTileDataCacheMaxSize` | 20 Kacheln (Default) | nie gemessen |
| alle `textCacheMaxSize` | 100 (Default) | nie gemessen |
| alle `fileCacheMaximumSizeInBytes` | 50 MB (Default) | nie gemessen |
| `concurrency` | 4 (Default) | nie gemessen |

Die Zeilen mit „nie gemessen" sind Paket-Defaults, die wir nie angefasst
haben. Sie gelten **pro Layer**, und seit #118 laufen zwei `VectorTileLayer`
gleichzeitig — jede dieser Grenzen ist also faktisch verdoppelt.

Was dabei zu bedenken ist, bevor jemand den Datei-Cache abschaltet, weil er
bei einer lokalen PMTiles-Quelle nach Verdopplung aussieht: Der Renderer legt
dort die **entpackten** Kachelbytes ab. Ihn wegzunehmen spart Schreibzugriffe
und Platz, kostet aber bei jedem Treffer eine erneute gzip-Entpackung — und
die läuft synchron im Haupt-Isolate. Auch das ist ein Tausch, kein Aufräumen.

## Was schon gemessen ist

- **GPU-/Texturspeicher (#142/#143).** Beim Bedienen von 89 auf 257 MB
  gewachsen, in ANR-Berichten 1,7–1,9 GB. Ursache: gehaltene Kacheln sind
  GPU-Texturen, und `flutter_map` gibt sie beim Ausdünnen nicht frei.
  Die Puffer- und Substitutionswerte oben sind die Antwort darauf. Für die
  Basiskarte allein: Spitze 512 → 224 MB, GPU 188 → 37 MB.
- **Raster vs. Vektor für die Detailkarte (#151).** Kein Unterschied bei der
  CPU (15,3 s in beiden Läufen), aber 71 % mehr GPU-Speicher im Raster-Modus
  (322 statt 188 MB). Die Linie ist damit geschlossen.
- **MapLibre statt flutter_map (#151, Spike).** Gesamt-CPU identisch, die
  Arbeit wandert nur auf einen anderen Thread; Haupt-Thread −28 % statt der
  geforderten −50 %. Dazu lieferten die Regionsdateien gar keine Kacheln.
  Kein Migrations-PR.

## Die Auflösung der ANRs (#151, gemessen am 2026-08-02)

Der ANR-Thread-Dump aus #151 zeigte den Haupt-Thread in
`dart::MarkingVisitor::ProcessOldMarkingStack` (übersetzt mit
`tool/symbolize_anr.py`) — also im GC, nicht im Kartenrenderer. Die
Live-Messung auf dem Pixel 7 Pro (GC-Rekorder am VM-Service, zwei
Reproduktionen) fand dann die ganze Kette; Beweisstücke im Issue:
<https://github.com/MacBuchi/pilzbuddy/issues/151>

1. Ein Gesten-Grenzfall macht die flutter_map-Kamera **nicht-endlich**
   (NaN/Infinity in Zoom oder Center). Feldbeleg: Alle 61 „Infinity or NaN
   toInt"-Berichte aus KW30 (#141) tragen als obersten Frame `_floor` aus
   flutter_maps `tile_range.dart`.
2. Die Kachelschicht wirft dann nur eine Exception (sichtbar als graue
   Flächen, weil keine Kacheln mehr angefordert werden). Der **MarkerLayer**
   aber wiederholt jeden Marker über alle Weltkopien, und sein Abbruch-Test
   (`Rect.overlaps`) ist mit NaN per IEEE-Vergleich immer wahr: Die Schleife
   endet nie.
3. Gemessen: ~150 MB/s Allokationen (134 MB → 3,8 GB in 24 s), 31 Mio.
   `Positioned`-Widgets mit je 4 geboxten Doubles. Der GC kommt nie
   hinterher (was während der Markierung allokiert wird, gilt konservativ
   als lebendig), der Haupt-Thread assistiert dauernd — daher die
   MarkingVisitor-Frames. Ende durch ANR oder OOM (die Marker-Liste wollte
   auf 256 MB verdoppeln); danach kollabierte der Heap auf ~70 MB.
4. **Kein Leck.** Deshalb konnte der Dart-Heap am 2026-07-26 „flach bei
   42 MB" liegen UND die ANR-Berichte 1,7–1,9 GB zeigen: Der Heap ist
   gesund, außer während eines Sturms — und ein Sturm braucht nur einen
   kaputten Kamera-Frame.

Konsequenzen:

- **Der Fix** ist `FiniteCameraConstraint`
  (`lib/features/map/finite_camera_constraint.dart`, seit 1.38.2): Jede
  Kamerabewegung — auch aus Gesten — läuft durch
  `MapOptions.cameraConstraint.constrain()`; nicht-endliche Zustände werden
  verworfen, die Kamera bleibt auf dem letzten guten Stand. Drei Tests
  sichern Verhalten, Engstelle und Verdrahtung.
- **Die Stellschrauben unten waren die falsche Achse.** Raster vs. Vektor,
  MapLibre, Cache-Grenzen — alles zielte auf das Rendern; der Sturm saß in
  der Marker-Schicht. Dass an den gemessenen Werten nie „auf Verdacht"
  gedreht wurde, hat verhindert, dass ein Symptomtausch die Spur verwischt.
  Die Grundregel oben bleibt deshalb unverändert in Kraft.
- **Verifikation im Feld:** Die Gruppe „Infinity or NaN toInt" muss aus dem
  Wochendigest verschwinden; greift der Wächter, meldet er sich dort
  einmal pro App-Lauf als „Kamera-Bewegung verworfen".

## Rückfrage zu #157 — nach 1.38.2 neu bewerten

„Je nach Zoomstufe erscheinen oder verschwinden Bereiche der Karte" — das
passiert laut Betreiber teils auch **online**. Graue Flächen online haben
seit der Auflösung oben einen Hauptverdächtigen: eine nicht-endliche Kamera
lässt die Kachelberechnung werfen, bis die nächste Geste sie repariert.
Genau das fängt 1.38.2 ab. Deshalb: **erst mit 1.38.2 erneut testen**, dann
weitersehen.

Bleibt das Symptom, sind die Kandidaten die zwei Layer-Welten:

- **Online** (Standard): `TileLayer` mit `keepBuffer: 2` / `panBuffer: 1`.
  Der Wechsel von 3/2 auf 2/1 in #142 ist der Grund, warum die Karte beim
  Nachladen kurz blass ist — bewusst in Kauf genommen („eine Karte, die nach
  zehn Minuten die App abwürgt, ist schlechter als eine, die beim Nachladen
  kurz blass ist").
- **Offline**: die beiden Vektor-Layer mit
  `maximumTileSubstitutionDifference: 1`.

Der naheliegende Griff wäre in beiden Fällen eine Rücknahme von #142 —
und der bleibt an eine Messung gebunden (Grundregel oben).
