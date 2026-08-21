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

## Nachtrag 2026-08-09 (2): Feine Wald-Blöcke ändern am Bildpuffer nichts (#253)

Die nachladbare 100-m-Stufe malt durch DENSELBEN Fenster-Renderer mit
demselben Pixelbudget — der Bildpuffer bleibt bei ≤ ~9,4 MB, egal wie
fein das Gitter ist (genau dafür wurde #249 vorgezogen). Neu ist nur der
Speicher der GITTER selbst: Ein ~2°-Block sind roh ~3 MB (Bytes je
Wabe); der Dekodier-Cache im `ForestBlockRepository` ist auf **8 Blöcke
(~25 MB Obergrenze)** gedeckelt, zuletzt benutzte überleben. Geladen
wird nur bei neuem Fenster-Plan — kleines Schieben löst über die
#249-Hysterese weder Malen noch Laden aus. Wer den Deckel anfasst,
misst vorher (`tool/measure_map.sh`); die Lehre aus #142 gilt auch für
diesen Cache.

## Nachtrag 2026-08-09 (3): Waben unter Pixelgröße — Deckung statt Füllung

Feldbericht des Betreibers: „relativ weit rausgezoomt entstehen Lücken,
dann Streifen, und in der Deutschland-Gesamtansicht ist gar nichts mehr
zu erkennen. Das war vorher viel besser." Stimmt, und die Ursache war
**nicht** das Pixelbudget aus #249, sondern der Sechseck-Zeichner aus
#251: Er malte vorwärts (Wabe → Pixelzeilen), und eine Wabe schmaler als
ein Pixel fiel beim Runden komplett heraus (`ceil(oben) > floor(unten)`).

Gemessen am **echten Asset** (3038 × 4470 Waben, 250 m), Fenster um
50 °N/10 °E, „Wahrheit" = Waldanteil der Waben im Ausschnitt, „gemalt" =
mittlere Deckkraft des PNGs:

| Sichtfenster | Wabe im Bild | Wahrheit | alt (Füllung) | neu (Deckung) |
|---|---|---|---|---|
| 852 km (DACH-Übersicht) | 0,39 px | 47,8 % | **0,0 %** | 43,5 % |
| 398 km | 0,54 px | 49,6 % | **5,0 %** | 49,2 % |
| 199 km | 1,04 px | 51,4 % | **31,3 %** | 54,1 % |
| 99 km | 2,08 px | 54,2 % | 48,0 % | 55,1 % |
| 50 km | 4,15 px | 53,4 % | 51,9 % | 53,6 % |
| 20 km | 10,4 px | 42,4 % | 42,1 % | 42,4 % |
| 5 km | 41,5 px | 30,6 % | 30,8 % | 30,8 % |

Der Bruch beginnt exakt unter **2 px Wabenbreite** — deshalb war unterhalb
von ~100 km Sichtfenster nie etwas zu sehen und darüber alles. Seit
1.74.0 trägt jede Wabe ihren Flächenanteil zu den Pixeln bei, die sie
berührt (`_HexCoverage` in `forest_fill.dart`); die Farbe ist die
deckungsstärkste Klasse, die Deckkraft die Gesamtdeckung. Das ist
Kantenglättung, keine Mittelung von Daten — und exakt die Aggregation,
die `tool/forest_grid.py` beim Bau eines gröberen Gitters ohnehin macht.
`test/forest_fill_test.dart` nagelt beide Enden fest (0,4 px und 1 px je
Wabe ⇒ ≥ 95 % Fläche; halber Wald ⇒ halbe Deckkraft, damit „einfach alles
vollmalen" nicht durchgeht).

**Kosten, je Phase gemessen** (1193 × 1536, Übersichtszoom, MacBook):

| Phase | vorher | nachher |
|---|---|---|
| Rasterarbeit | ~110 ms | ~110 ms |
| Deckung auflösen | — | ~60 ms |
| PNG-Kompression | 645 ms (zlib 6) | 222 ms (zlib 1) |

Zwei Erkenntnisse daraus, beide gegen die Intuition:

1. **Die Rasterarbeit war nie das Problem.** Der teuerste Schritt des
   Einfärbens ist die PNG-Kompression — und sie stand ohne Grund auf der
   zlib-Voreinstellung 6. Stufe 1 kostet 10 % mehr Bytes (2,2 statt
   2,0 MB) in einer Datei, die sofort wieder gelesen wird und nie durchs
   Netz geht. Gilt jetzt für Wald, Regen und Ampel (`overlay_png.dart`).
2. **Der alte Zeichner war im Übersichtszoom nur deshalb „schnell",
   weil er nichts malte** — ein leeres PNG komprimiert in Nullzeit. Wer
   künftig Zeiten vergleicht, prüft zuerst, ob überhaupt Fläche im Bild
   ist.

Neuer Puffer: drei `Uint16`-Deckungsbänder je Pixel, **14 MB beim
größten Fenster** (1536² × 3 × 2 B) zusätzlich zum RGBA-Raster von
9,4 MB — beides kurzlebig im `compute`-Isolat. Die Kombi-Ebene „Wald +
Pilzwetter" (1.76.0) hängt zwei Leuchtbänder an: fünf statt drei, also
**23 MB** — nur solange sie eingeschaltet ist. `Float32` wäre 28 MB und
brächte nichts: Selbst im Übersichtszoom, wo sieben Waben in einem Pixel
liegen, trägt jede noch ~130 der 1024 Einheiten bei.

### Und die feine Stufe lädt erst, wenn man sie sehen kann

Rückfrage des Betreibers zum selben Thema: „Die 100-m-Waben können ja
erst ab einer Zoomstufe kommen, die Sinn macht — wo eine Wabe mehrere
Pixel breit ist." Genau so war es NICHT: Das Nachladen (#253) hing allein
am Schnitt der Blöcke mit dem geplanten Fenster. **Am Emulator
nachgemessen** — nach einem Zoom auf die Deutschland-Übersicht mit
eingeschalteter Feinstufe lagen im App-Verzeichnis:

    31 Dateien, 26 MB   (= der GANZE Katalog, 30 Blöcke plus Katalogdatei)

Für ein Bild, in dem eine feine Wabe 0,06 px misst und in derselben
Deckung verschwindet, die das eingebaute 250-m-Asset ohnehin liefert.
Seit 1.74.0 lädt `forestBlockSetProvider` nur noch, wenn
`ForestBlockCatalog.paysOffIn(window)` gilt: mindestens **10 Bildpixel je
feiner Wabe** (≈ 20–30 Bildschirmpixel), erreicht ab etwa 4–5 km
Sichtfensterbreite hochkant (Maßstabsleiste um 1 km), quer ab ~8 km.
Die Schwelle ist bewusst NICHT die Sichtbarkeitsgrenze: Bei zwei Pixeln
je feiner Wabe steht daneben eine 250-m-Wabe mit fünf — dasselbe Bild,
nur mit Downloads davor (Betreiber-Entscheidung 2026-08-09: „das kannst
du locker auf 10 Pixel aufweiten"). Bei zehn Pixeln sieht man, was die
feine Stufe besser weiß: den Laubstreifen am Bach, den Fichtenriegel im
Buchenhang. Dieselbe Strecke, erneut gemessen:

    2 Dateien, 852 KB   (Katalog + der EINE Block unterm Nahzoom)
    → nach dem Rauszoomen: unverändert

Der Verlauf, am Emulator mitgeschrieben (Bildpixel je feiner Wabe und
Blöcke, die das Fenster geschnitten hätte):

| Fenster | px je Wabe | Blöcke im Fenster | geladen |
|---|---|---|---|
| 6,39° (Übersicht) | 0,19 | 16 (~14 MB) | nein |
| 3,22° | 0,38 | 6 | nein |
| 1,20° | 1,01 | 2 | nein |
| 0,49° | 2,50 | 2 | nein |
| 0,18° | 6,78 | 2 | nein |
| 0,10° | 12,70 | 1 | **ja, 852 KB** |

Der Katalog selbst darf weiterhin kommen — er ist die Antwort auf „lohnt
es sich?" und kostet ein paar Kilobyte.

**Was NICHT angefasst wurde:** Rand (50 %) und Zoom-Faktor (3,5) des
Fensterplaners. Beide bestimmen, wie scharf die Fläche zwischen zwei
Neuplanungen aussieht (bei Budget 1536 und 50 % Rand liegen ~768 Bildpixel
auf der Sichtfensterbreite, also ~1,9× hochskaliert auf einem
1440-px-Schirm). Das ist die nächste Schraube, wenn die Kanten beim Zoomen
weiter stören — aber sie wird gemessen, nicht gedreht, weil sie Speicher
gegen Nachladen tauscht (die Regel oben).

## Nachtrag 2026-08-17: Kombi-Ebene wertet die Glocke je Wabe aus

Seit dem Berchtesgaden-Befund leuchtet jede Waldwabe nach IHRER Höhe
(`AmpelLevelGrid.levelFor` mit Wabenhöhe aus dem Höhengitter), nicht
mehr nach einer je 1-km-Regenzelle fertig gerechneten Stufe — sonst
konnte die Wabenfarbe der Punkt-Ablesung des Blatts in steilem Gelände
nicht überall zustimmen (eine Regenzelle überspannt dort 500+
Höhenmeter).

Gemessen (Debug-VM, echtes Waldgitter, Übersichtszoom 800×600 px, alle
13,6 Mio. Waben mit gültiger Wetteraussage — der TEUERSTE Fall, nicht
der typische):

| Variante | Median aus 3 |
|---|---|
| ohne Höhenauswertung | 316 ms |
| mit Höhenauswertung je Wabe (Nachschlag + Glocke) | 733 ms |

Läuft im compute-Isolate, je Kamera-Stillstand einmal — kein Jank,
nur später sichtbares Leuchten. `test/perf_ampel_fill_measure.dart`
misst das nach und zieht bei mehr als dem Doppelten (+Puffer) die
Reißleine.

**Nächste Hebel, falls es je drückt** (gemessen wird vorher, Regel
oben): ein Ein-Schlitz-Memo je Wabenzeile auf (Regenspalte, Höhenbyte)
— im Flachland, wo die meisten Waben liegen, träfe es fast immer —
oder der Direktindex für das grobe Gitter, dessen Raster mit dem
Höhengitter identisch ist (`hexNearestCell` des eigenen Mittelpunkts
ist dort die Identität).

## Nachtrag 2026-08-20: Höhenlinien aus dem Höhengitter (1.98.0)

Die Ebene rechnet auf dem Gerät: Sichtfenster planen (`planFillWindow`,
dieselbe Hysterese wie die Waldfläche), Höhengitter darin abtasten,
3×3 mitteln, Marching Squares. Kein Netz, kein Bild, keine Kachel.

Gemessen (Debug-VM, echtes Höhengitter 3038×4470, Fenster wie ein
1080×1920-Schirm sie auslöst, `test/perf_elevation_contours_measure.dart`):

| Lage | Abtastung | Äquidistanz | Linien | Punkte | ms |
|---|---|---|---|---|---|
| Alpen z11 | 392×768 | 200 m | 839 | 42 126 | 260 |
| Mittelgebirge z12 | 196×394 | 50 m | 538 | 16 988 | 35 |
| Flachland z13 | 98×188 | 20 m | 67 | 1 750 | 5 |

Läuft im compute-Isolate, einmal je Kamera-Stillstand, der das Fenster
wirklich verlässt — wie bei der Waldfläche also kein Jank, sondern
später erscheinende Linien.

Drei Werte und woher sie kommen:

- **`contourSampleBudget = 768`** — höchstens 768 Proben je Kante, und
  ohnehin nie feiner als eine Probe je Wabe. Der Deckel greift erst ab
  etwa z11; darunter bestimmt die Wabenweite die Abtastung. Feiner
  abzutasten als das Gitter bläst jede Wabe zu einem Block gleicher
  Werte auf, und Marching Squares zeichnet daraufhin die Wabenkanten
  als Terrassen in die Linie.
- **`contourPointBudget = 60 000`** — die Zoomregel rechnet mit einem
  angenommenen Hang von 10 %; die Alpen sind das Drei- bis Fünffache.
  Reißt die Schranke, wird die Äquidistanz GENAU EINMAL verdoppelt und
  neu gezogen. Genau das ist im Alpenfall oben passiert (100 m → 200 m),
  und es ist auch der Grund für die 260 ms: Der Lauf steckt zweimal
  drin. Eine Schleife wäre teurer als der Nutzen — die nächste Stufe
  halbiert die Linienzahl bereits.
- **`contourMinLinePixels = 40`** — dieselbe Regel wie beim Regen („eine
  Linie unter 40 px sagt nichts"), hier in Bildschirmpixeln statt in
  Kilometern gerechnet. Sie bringt weniger, als man erwartet: 77 von
  916 Linien im Alpenfall. `minChainCells` fängt die kleinsten Fetzen
  schon vorher, und eine Abtastzelle ist dort ohnehin ~5,5 px groß. Sie
  bleibt, weil sie in Pixeln formuliert ist und damit eine Änderung der
  Abtastung überlebt.

**Nächster Hebel, falls es je drückt** (gemessen wird vorher, Regel
oben): Das Übergeben des `ElevationGrid` an `compute` kopiert dessen
13,6-MB-`Uint8List` je Lauf — dasselbe tut die Waldfläche längst. Wer
das los will, schneidet das Hex-Teilrechteck im Haupt-Isolate aus und
schickt ~1 MB.

## Nachtrag 2026-08-21: die Äquidistanz kommt aus dem Gelände (1.99.0)

Rückmeldung des Betreibers zu 1.98.0, am Emulator nachgesehen: In den
Alpen bei ~13 m je Pixel waren die Linien keine Höhenlinien mehr,
sondern eine Schraffur — lange parallele Bänder ohne eine einzige Zahl.

Zwei Ursachen, beide in der Rechnung:

**1. Die Zoomstufe bedeutet in den zwei Engines Verschiedenes.**
MapLibre zählt in 512-dp-Kacheln, flutter_map in 256ern. Die Regeln von
1.98.0 rechneten in der 256er-Zählung und bekamen von der Android-Karte
die 512er — durchweg eine Stufe daneben. **Nachgemessen am Gerät**
(Pixel 7 Pro, 1080 px bei Dichte 420, Fenster aus dem Log der App):
Sichtfenster 0,14125° Länge auf 1080 Pixel bei 49,62° Breite sind
9,43 m je physischem Pixel, also 24,8 m je dp — das ist 256er-Zoom 12,0
exakt, während `camera.zoom` 11 meldete.

Die Regeln rechnen deshalb nicht mehr in Zoomstufen, sondern in **Meter
Boden je logischem Pixel** (`groundResolution`, aus Sichtfenster und
Pixelbreite). Diese Größe ist in beiden Engines dieselbe.

**2. Der Hang war geraten.** `contourEquidistanceM` unterstellte 10 %;
die Alpen haben das Drei- bis Fünffache. Jetzt misst `reliefPerPixel`
das **75. Perzentil** der Höhenunterschiede zwischen Nachbarzellen im
abgetasteten Fenster — nicht den Median: Ein Fenster mit Talboden UND
Steilhang hat einen niedrigen Median, und die Linien lägen genau dort zu
dicht, wo man sie liest.

Die Regel ist damit ein Satz: **Äquidistanz ≥ 20 px · Relief-je-Pixel**,
und wenn selbst 200 m das nicht schaffen, wird gar nicht gezeichnet.

Gemessen (Debug-VM, echtes Höhengitter, Fenster wie ein 412-dp-Schirm
sie auslöst, `test/perf_elevation_contours_measure.dart`):

| Lage | m/px | Relief je px | Äquidistanz | Linien | Punkte | ms |
|---|---|---|---|---|---|---|
| Alpen (Innsbruck) | 2 | 0,63 m | 20 m | 49 | 98 | 8 |
| Alpen (Innsbruck) | 5 | 1,14 m | 50 m | 42 | 212 | 6 |
| Alpen (Innsbruck) | 10 | 2,43 m | 50 m | 99 | 1 194 | 9 |
| Alpen (Innsbruck) | 25 | 7,34 m | 200 m | 75 | 2 192 | 13 |
| Alpen (Innsbruck) | 50 | 14,33 m | — | 0 | 0 | 17 |
| Mittelgebirge (Sauerland) | 10 | 0,75 m | 20 m | 80 | 1 342 | 2 |
| Mittelgebirge (Sauerland) | 25 | 2,08 m | 50 m | 135 | 3 214 | 6 |
| Mittelgebirge (Sauerland) | 50 | 3,79 m | 100 m | 173 | 5 436 | 22 |
| Mittelgebirge (Sauerland) | 200 | 8,33 m | 200 m | 135 | 11 460 | 150 |
| Hochwald (Saarland) | 25 | 1,46 m | 50 m | 85 | 1 948 | 5 |
| Hochwald (Saarland) | 100 | 4,76 m | 100 m | 229 | 11 996 | 64 |
| Flachland (Heide) | 25 | 0,50 m | 20 m | 48 | 1 202 | 5 |
| Flachland (Heide) | 200 | 3,17 m | 100 m | 98 | 5 144 | 114 |

Ablesen lässt sich daran genau das, was die Regel verspricht: Dasselbe
Bildschirmmaß ergibt in den Alpen eine gröbere Stufe als im Sauerland,
und weit draußen im Steilgelände gar keine. Der Zeilenabstand liegt in
allen Fällen zwischen 20 und 33 Pixeln — vorher waren es im Alpenfall
gemessene 5 bis 7.

Teuerster Fall 150 ms im Isolate, je Kamera-Stillstand. Das ist die
Hälfte der 260 ms von 1.98.0, weil die Punktschranke nicht mehr
regelmäßig einen zweiten Durchgang auslöst.

Zwei Werte kamen dazu, einer bekam eine neue Begründung:

- **`contourMinLineSpacingPixels = 20`** — die EINE Stellschraube der
  Dichte. 12 waren es in 1.98.0, und 12 px Abstand sind auf dem Gerät
  eine Schraffur.
- **`contourMaxMetersPerPixel = 270`** — deckt ein Pixel mehr Boden ab
  als eine Wabe breit ist, bleibt die Ebene leer. Das ist eine Aussage
  über die Daten, keine über den Geschmack. Sie ersetzt das frühere
  „unter z10 gar nichts" und greift in der Praxis selten, weil die
  Reliefregel im bewegten Gelände schon vorher aufgibt.
- **`contourPointBudget = 60 000`** ist von der Hauptbremse zum Netz
  geworden: Es war die einzige Antwort auf zu steiles Gelände, jetzt ist
  es der Rest­fall.

**Die Zahlen an den Linien** (dieselbe Rückmeldung: „machen weniger Sinn
ohne entsprechende Beschriftung") sitzen auf den Hauptlinien, und die
kommen seither etwa alle 100 Höhenmeter statt „jede fünfte" — bei 100 m
Äquidistanz wäre jede fünfte alle 500 Höhenmeter, und in einem Talkessel
stünde keine einzige Zahl auf dem Schirm. Kosten tut es nichts
Messbares: MapLibre
setzt sie selbst (`symbol-placement: line` auf der Hauptlinien-Quelle,
Glyphen liegen ohnehin im App-Verzeichnis), flutter_map bekommt sie als
Marker aus `contourLabels` — ein paar Dutzend Punkte je Fenster,
gerechnet auf dem Haupt-Thread, weil der Sprung ins Isolate mehr kostete
als die Rechnung.
