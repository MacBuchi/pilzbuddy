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
  Kein Migrations-PR — **so stand es hier bis zur Autopsie**: Beide
  K.-o.-Befunde waren Spike-Bugs (leere Kacheln = Style-Race vor geladener
  Regionsliste; −28 % = ungecullte Marker pro Frame auf dem UI-Isolate).
  Die echte Migration lief danach in Stufen (PR #174–#179); das Ergebnis
  steht unten unter „Der Engine-Direktvergleich".

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
Genau das fängt 1.38.2 ab.

Der zweite Verdächtige ist ebenfalls seit 1.38.2 behoben: Beim
Auto-Offline-Wechsel (Empfangsverlust bei installierten Regionen) hängt die
Karte den Online-`TileLayer` aus, und flutter_map entsorgt dabei dessen
TileProvider **samt HTTP-Client**. Die früher screen-weit festgehaltene
Instanz (`late final`) war danach eine Leiche: Frische Kacheln scheiterten
bis zum App-Neustart, nur der Platten-Cache lieferte noch — Bereiche
erschienen und verschwanden je nach Zoomstufe und Gegend. Seit 1.38.2
bekommt jeder Online-Einbau eine frische Instanz
(`test/online_tile_provider_swap_test.dart` nagelt das fest).

Deshalb: **erst mit 1.38.2 erneut testen**, dann weitersehen.

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

## Der Engine-Direktvergleich (Migrationsstufe 7, gemessen am 2026-08-03)

Aufbau: Pixel 7 Pro (LTPO-Panel bis 120 Hz), Profile-Build 1.42.0 mit
Release-Signatur, Offline-Modus mit vier installierten Regionen —
darunter Bayern mit 1,79 GB, also die Leaf-Directory-Klasse, die das
H2-Gate isoliert bewiesen hatte. Gleiches Gerät, gleiches Konto,
gleicher Spot-Bestand; der Engine-Wechsel ist nur der Beta-Schalter im
Profil, jeder Schaltzustand vor der Messung per Screenshot verifiziert.

Werkzeuge: `tool/measure_map.sh` (Perfetto-Trace, deterministische
Gesten-Choreographie, Speicher-Verlauf) und `tool/analyze_map_trace.py`
(Auswertung). Gemessen wird mit SurfaceFlingers **FrameTimeline
end-to-end pro präsentiertem Display-Frame**: Flutters Frame-Timings
und `gfxinfo` sehen den nativen GL-Thread der MapLibre-Engine nicht,
und App-eigene Surface-Frames existieren in der FrameTimeline für
BEIDE Engines nicht (weder Flutter noch die GL-Surface taggen ihre
Buffer mit Vsync-IDs — im Trace tut das nur die StatusBar, zwei
Frames). Während der Messläufe animiert nichts außer der Karte; die
Display-Kadenz ist also die Karten-Kadenz. Die reale Refresh-Rate wird
aus dem Trace gelesen, nicht angenommen.

Zwei deterministische Lasten, auf beiden Engines exakt gleich:

- **Kamerafahrt** (`CameraTourButton`, 15 harte Sprünge, ~55 s):
  misst die Nachlade-Bursts nach Sprüngen.
- **Gesten-Choreographie** (`tool/measure_map.sh gestures`, ~30 s bei
  München z14: zwölf Pans, vier Flings): misst das Wischen — den
  Moment, in dem Ruckeln spürbar ist.

### Frame-Abstände (präsentierte Frames, aktive Phasen < 250 ms)

| | flutter_map | MapLibre |
|---|---|---|
| **Gesten** p50/p95/p99 | 58,3 / 141,6 / 223,8 ms | 8,33 / 16,7 / 25,0 ms |
| präsentierte Frames in ~29 s | 322 | 1621 |
| Panel-Takt im Lauf | 40 Hz (heruntergetaktet) | 120 Hz durchgehend |
| SF-Jank-Frames / längster Burst | 102 / 9 | 0 / 0 |
| **Kamerafahrt** p50/p95/p99 | 8,3 / 124,1 / 204,7 ms | 8,3 / 25,0 / 33,3 ms |
| SF-Jank-Frames / längster Burst | 30 / 5 | 3 / 2 |

Lesart: Beim Wischen liefert die alte Engine im Median alle 58 ms ein
Bild (~17 fps) — das LTPO-Panel findet im gesamten Lauf keinen Grund,
über 40 Hz zu takten. Die neue liefert im Median jeden 120-Hz-Takt
(fünfmal so viele Frames in derselben Choreographie), und
SurfaceFlinger klassifiziert keinen einzigen Frame als Jank. Nach
Kamera-Sprüngen steht die alte Engine im p99 205 ms, die neue 33 ms.

### Kaltstart (Splash → Karte steht; screenrecord, kodierte Frames + pts)

| | Lauf 1 | Lauf 2 |
|---|---|---|
| flutter_map | 2,20 s | 2,22 s |
| MapLibre | 2,18 s | 2,23 s |

Identisch. Die ~2,2 s sind gemeinsamer App-Bootstrap
(Session-Wiederherstellung übers Netz, Provider, Splash); der
Engine-Anteil der neuen Karte ist ≈ 0 — die 2-GB-Region im Style
kostet beim Start nichts Messbares. Kalte Sprünge in Bayerns
Leaf-Directories hatte das H2-Gate bereits mit < 3 s belegt.

### Speicher (10-Minuten-Fenster, Kamerafahrt im Loop, dumpsys meminfo)

| | flutter_map | MapLibre |
|---|---|---|
| Total PSS unter Last | 0,61–1,54 GB, stark schwankend | 530–570 MB, stabil |
| Grafik-Spitze | 873 MB | 262 MB |
| nach Lastende | ~680 MB | ~450 MB, fallend |

Die alte Engine erreicht unter der Dauerlast Spitzen von 1,5 GB Total
PSS — die Gegend, aus der die ANR-Berichte in #142 kamen (1,7–1,9 GB).
Die neue hält ein Plateau bei gut einem Drittel davon, ohne monotones
Wachstum, und gibt nach Lastende Speicher zurück. (Transparenz: Im
MapLibre-Fenster liefen die ersten ~2 Minuten ohne Last, weil das
Display kurz dozte; Plateau- und Spitzenwerte stammen aus den ~8
Minuten unter Last. Der flutter_map-Lauf lief volle 10 Minuten unter
verifizierter Last.)

### Bewertung gegen die Wett-Kriterien aus dem Migrationsplan

- **p99 ≤ 1 Vsync der realen Refresh-Rate:** Wörtlich erfüllt keine
  Engine (1 Takt bei 120 Hz = 8,3 ms). MapLibre hält den **Median**
  exakt auf dem Takt, p95 im 60-Hz-Budget (16,7 ms), p99 bei 25 ms —
  und SurfaceFlinger zählt null Jank-Frames; das Kriterium war strenger
  formuliert als das, was der Compositor selbst als ruckelfrei wertet.
  flutter_map verfehlt es bereits im Median um Faktor 7.
- **Keine Jank-Bursts > 3 Frames:** MapLibre erfüllt (längster Burst
  2, in den Gesten 0). flutter_map verfehlt (Bursts von 5 und 9).
- **Kaltstart 2-GB-Region < 2 s:** Der Engine-Anteil ist ≈ 0; die
  gemessenen 2,2 s sind App-Bootstrap und für beide Engines identisch.
- **Speicher nach 10 min gedeckelt:** MapLibre erfüllt (Plateau,
  danach fallend). flutter_map schwankt bis 1,5 GB.

Die Rohdaten (Traces, CSVs) entstehen unter `build/map_traces/`; die
Prozedur ist mit `tool/measure_map.sh` wiederholbar — womit die
Grundregel oben („keine Stellschraube ohne Messung") erstmals ein
wiederholbares Werkzeug hat. Was die Zahlen nicht entscheiden können,
entscheidet der Betreiber im Alltag: der Beta-Schalter bleibt, bis der
Direktvergleich mit dem Daumen gesprochen hat; erst dann dreht ein
eigener PR den Default.

## Nachtrag 2026-08-09: Die Waldfläche malt nur noch das Sichtfenster (#249)

Die Waldtypen-Fläche (#213) entstand bis 1.68.x als EIN Bild über ganz
DACH, ein Pixel je 250-m-Zelle: 3264 × 4160 → **52 MB RGBA-Puffer je
Einfärbung** — der größte Einzelpuffer der App, bei jedem Klassenwechsel
neu gerechnet. Zwei beschlossene Ausbauten sprengen dieses Modell
unabhängig voneinander (gerechnet, nicht geraten):

| Variante | Bildgröße | RGBA-Puffer |
|---|---|---|
| 250 m, ganz DACH (bis 1.68.x) | 3264 × 4160 | 52 MB |
| 100 m, ganz DACH (Gitter gemessen: 27,2 MB) | 8160 × 10400 | 324 MB |
| 250-m-Sechsecke à 4 px, ganz DACH | 13056 × 16640 | 829 MB |

Seit 1.69.0 plant `forest_fill_window.dart` einen AUSSCHNITT: Sichtfenster
plus 50 % Rand, aufs Gitter beschnitten, längste Kante 1536 px ⇒
**höchstens ~9,4 MB Puffer**, unabhängig von Gitterauflösung und
Zellform. Neu gemalt wird nur, wenn das Sichtfenster den gerenderten
Kasten verlässt oder tief hineinzoomt (Faktor 3,5 — bewusst nicht 3,0,
sonst malte jede Zoom-Raste neu, weil der Rand genau Faktor 3 ergibt);
kleines Schieben behält dieselbe Bild-Instanz. Beim Hineinzoomen wird die
Fläche damit erstmals SCHÄRFER statt hochskaliert. Die Zeilen bleiben
Mercator-verteilt (#247) — der Fenster-Renderer verallgemeinert genau
diese Korrektur.
