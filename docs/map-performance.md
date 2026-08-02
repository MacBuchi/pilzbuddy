# Karte, Speicher und ANRs — was gemessen ist und was noch nicht

Die Karte ist der einzige Teil der App, der sie umbringen kann. Diese Seite
sammelt, welche Stellschrauben es gibt, welche Zahl hinter ihrem heutigen Wert
steht, und wie die eine Messung geht, die noch fehlt. Sie existiert, weil in
#157 ein Vorschlag gemacht wurde, der genau die Einstellung zurückgedreht
hätte, die #142 nach einer Messung gesetzt hat — und weil das ohne diese Seite
wieder passiert.

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

## Was noch nicht gemessen ist — und die eine offene Messung

Der ANR-Thread-Dump aus #151 zeigt den Haupt-Thread in
`dart::MarkingVisitor::ProcessOldMarkingStack` — in einer
Garbage-Collection-Markierungsphase des Dart-Heaps. Alle Messungen bisher
gingen auf GL/mtrack, also auf **GPU-Texturen**. Der Dart-Heap ist ein
anderer Speicherbereich und wurde nie angesehen.

Zu übersetzen ist der Dump mit `tool/symbolize_anr.py` (siehe CLAUDE.md).

### Die Frage

Wächst der Dart-Heap (Old Space) mit der Zahl berührter Kacheln, und wie lange
dauert eine einzelne Markierungsphase?

Eine ANR entsteht nicht aus Dauerlast: 15 s CPU über 90 s Gestik sind ~17 %
Auslastung. Sie entsteht aus **einer** Operation, die 5 s am Stück blockiert.
Gesucht ist also die längste einzelne GC-Pause, nicht die Summe.

### Vorhersage, an der sich das widerlegen lässt

Trifft die Vermutung zu, wächst Old Space beim Pannen und Zoomen in die
Hunderte MB und die längste Markierungspause wächst mit. Bleibt Old Space
klein und flach, während die App trotzdem hängt, **ist die Vermutung falsch**
und der Grund steckt woanders in der Engine.

### Ablauf

1. `flutter run --profile` auf dem Gerät, mit installierter Regionskarte und
   eingeschalteter Offline-Karte.
2. DevTools → **Memory**: „Dart Heap" beobachten, nicht RSS. Vor der Gestik
   einen Schnappschuss nehmen.
3. DevTools → **Performance**: Die GC-Spur zeigt einzelne Ereignisse mit
   Dauer. Das ist die Zahl, um die es geht.
4. Gestik: vier Runden aus Pannen **und** durchgehendem Zoomen in beide
   Richtungen.
5. Nach jeder Runde Old Space und die längste GC-Pause notieren.

**Zur Gestik, weil daran schon zwei Messungen gescheitert sind (#151):**
`adb input tap; input swipe` liest `flutter_map` als Doppeltipp-und-Ziehen und
fährt bis an die Zoomgrenze — danach tut jeder weitere Versuch nichts, und
MapLibre liest dieselbe Geste gar nicht als Zoom. Vor jeder Auswertung
prüfen, dass sich die Maßstabsleiste tatsächlich bewegt hat.

### Wenn die Vorhersage zutrifft

Dann sind `memoryTileDataCacheMaxSize` und `textCacheMaxSize` die ersten
Kandidaten — aber die Richtung ist **nicht** offensichtlich: Ein kleinerer
Cache hält weniger Zeiger am Leben (kürzere Markierung), erzeugt dafür mehr
Neuparsen, also mehr Müll und mehr Beförderungen ins Old Space. Beide
Richtungen können schaden. Deshalb: eine Änderung, ein Lauf, dieselbe Gestik.

## Offene Rückfrage zu #157

„Je nach Zoomstufe erscheinen oder verschwinden Bereiche der Karte" — es fehlt
die Angabe, ob online oder mit eingeschalteter Offline-Karte. Das entscheidet
alles, denn es sind zwei verschiedene Layer:

- **Online** (Standard): `TileLayer` mit `keepBuffer: 2` / `panBuffer: 1`. Der
  Wechsel von 3/2 auf 2/1 in #142 ist genau der Grund, warum die Karte beim
  Nachladen kurz blass ist — bewusst in Kauf genommen („eine Karte, die nach
  zehn Minuten die App abwürgt, ist schlechter als eine, die beim Nachladen
  kurz blass ist").
- **Offline**: die beiden Vektor-Layer mit
  `maximumTileSubstitutionDifference: 1`.

In beiden Fällen ist der naheliegende Griff eine Rücknahme von #142. Solange
#151 offen ist, heißt das: nicht anfassen.
