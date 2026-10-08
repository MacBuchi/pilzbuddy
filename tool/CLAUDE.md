# PilzBuddy — Arbeitsregeln für `tool/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Erzeugte Assets** (`tool/generated_assets.py` + `.json`, #226, im Job
  „Analyze & Test"): Vier Dateien unter `assets/` sind ERZEUGT, nicht
  geschrieben — Kartenstil, DACH-Übersicht, Waldgitter und dessen
  Manifest. Bis hierher stand nur in dieser Datei, dass man sie nicht von
  Hand editiert; eine Handänderung bestand jeden Check, wurde ausgeliefert
  und war beim nächsten Erzeugen kommentarlos weg. Jetzt prüft CI je Asset
  die Prüfsumme, und wo es etwas Schärferes gibt, zusätzlich:
  - Der **Kartenstil muss ein Fixpunkt** von `transform_map_style.py`
    sein. Das fängt, was eine Prüfsumme nicht sieht: neu generiert und
    den Umbau vergessen. Die Folge wäre lautlos — der Renderer lässt
    Ebenen, deren Ausdrücke er nicht versteht, einfach weg (graue
    Landflächen, keine Beschriftung).
  - Das **Waldgitter wird gegen `forest_manifest.json` geprüft**, das
    seine Prüfsumme und Größe längst selbst notiert — geschrieben vom
    Erzeuger, bis dahin von niemandem nachgerechnet.
  Nach einem echten Neu-Erzeugen: `--update`, und der geänderte Manifest
  gehört in denselben Commit; genau diese Zeile im Diff ist die Aussage
  „das war Absicht". **Bewusst NICHT geprüft wird der Hash des
  Erzeugers**: Er würde bei jedem Kommentar in `forest_grid.py` rot und
  ein 5,6-MB-Gitter neu verlangen — nach dem dritten Fehlalarm ruft man
  `--update` blind auf, und dann prüft der Wächter nichts mehr.
  `assets/map_glyphs/` fehlt bewusst: Der Erzeugungsbefehl steht nirgends
  im Repo, und eine geratene Anleitung in der Fehlermeldung wäre
  schlimmer als keine.

- **Baumarten am Spot** (`tool/forest_species.py` + `forest-species.yml`,
  #227, seit 1.86.0): Zweite Zeile im Spot-Blatt („Bäume: Fichte und
  Buche"), **keine Kartenebene** — die Karte bleibt bei den drei Klassen.
  Quelle ist die DLR-Karte „Tree Species Germany" 2022 (10 m, CC BY 4.0,
  offener HTTP-Download ohne Konto); die Nennung steht im Wald-Blatt
  neben der Copernicus-Zeile, zusammen mit der Abdeckung — **nur
  Deutschland**. Außerhalb sprechen seit 1.213.0 bzw. 1.221.0 die
  beiden Gitter weiter unten (ForestPaths, WSL); jede Quelle nennt im
  Blatt ihre eigene Abdeckung.
  Vier Dinge, die man wissen muss:
  - **Dasselbe Hex-Gitter wie das Waldgitter**, Zelle für Zelle: gleiche
    Box, gleiche Warp-Größe, gleicher Zellfaktor. Die App schlägt beide
    mit EINEM `hexNearestCell` nach. Ein Deutschland-enger Zuschnitt wäre
    kleiner gewesen, aber eine zweite Geometrie — zwei Wege zur Zelle,
    die auseinanderlaufen können. Werkzeug und Test pinnen die Maße auf
    3038 × 4470.
  - **Kein Zeilen-Delta**, anders als bei Wald und Regen. Gemessen: 1,98
    gegen 2,42 MB. Klassen haben kein Gefälle, das Delta zerstört die
    Wiederholungen, von denen gzip lebt. Das Manifest sagt
    `"encoding": "gzip"`, und der Dart-Leser lehnt alles andere ab.
  - **Ein Byte, zwei Halbbytes** (führende Laub- und Nadelart) statt der
    häufigsten Art allein: Letzteres verschluckte in **17,6 %** der
    Waldzellen den Mischpartner — gemessen an der ganzen Karte. Der
    Aufpreis sind 0,56 MB. `0xFE` (nur Kronenverlust) ist reserviert und
    wird noch NICHT angezeigt.
  - **Der Bau ist vom DLT-Weg unabhängig** (eigener Workflow, kein
    Secret), teilt sich aber dessen Geometrie-Code. Er läuft jährlich —
    `workflow_dispatch` verlangt den Workflow auf `main`, ein neues
    Gitter braucht also erst dessen Merge und dann einen Lauf.
  - **Außerhalb Deutschlands springt ein Rückfall-Gitter ein** (#624,
    `tool/forest_species_eu.py` + `forest-species-eu.yml`, nur von
    Hand): die ForestPaths-Gattungskarte (Zenodo 13341104, Vorab-Fassung,
    CC BY 4.0), gemessen gegen die DLR-Karte. Genannt werden NUR Fichte,
    Kiefer und Buche — Lärche erkennt sie praktisch nie (1,5 %), Eiche
    kaum. Die führende Gattung wird trotzdem über ALLE Klassen bestimmt
    und fällt erst danach weg; sonst wäre ein Lärchenbestand mit drei
    Fichten eine „Fichte". Jede Wabe, zu der das DLR-Gitter etwas sagt,
    ist dort 0xFF (Prüfsumme als `mask_sha256`). Eigene Datei, weil die
    Zeile je Wabe sagen muss, woher sie stammt und dass Lärche darin
    nicht vorkommen kann. Eine neuere ForestPaths-Fassung meldet der
    Lauf nur; übernommen wird sie erst nach derselben Messung.
    **In der App** (seit 1.213.0) steht die Vorrangregel an EINER Stelle,
    `forestSpeciesReadingAt`: DLR gewinnt, sobald es irgendetwas sagt —
    auch „Bäume ohne nennbare Art" (0x00) und Kronenverlust; nur bei
    0xFF fragt die Zeile die Schätzung, und auch dann nur nach
    `estimatedBroadleaves`/`estimatedConifers` (der Leser verlässt sich
    nicht darauf, dass das Asset die Zusage hält). Die Zeile lautet dann
    „Bäume: Fichte · Satellitenschätzung, Lärche nicht erkennbar · Stand
    2020". **Die Zeile wartet auf das DLR-Gitter**, bevor sie das zweite
    anfasst — während es lädt, sähe es wie „schweigt" aus, und jeder
    deutsche Spot packte das Rückfall-Gitter mit aus (im Test gefunden).
    Die iNaturalist-Vorauswahl der Bäume bleibt bewusst beim DLR-Gitter:
    Dort wird eine Schätzung zu einer Angabe in einer fremden Datenbank.
    **Falle beim lokalen Prüfen:** `_fake_tiff_u8` schreibt die Breite
    als SHORT — ab 65 536 Pixeln (das volle Raster hat 81 600) läuft sie
    über, und `verify` meldet Abweichungen, die es nicht gibt.
  - **In der Schweiz spricht seit 1.221.0 die WSL-Karte** („Tree species
    map of Switzerland", Koch et al. 2024, 10 m, Stand 2020,
    `tool/forest_species_ch.py` + `forest-species-ch.yml`), zwischen DLR
    und ForestPaths: `treeSpeciesLineAt` ist die EINE Vorrangregel über
    alle drei Gitter. Fünf Dinge, die man wissen muss:
    - **Alle Arten je Wabe, nicht nur die führende** (Betreiber,
      2026-10-01): jede mit ≥ 10 % der benannten Pixel, nach Anteil
      sortiert, sechs Halbbytes in drei Bytes. 5 % wäre bei 76 %
      Pixel-Trefferquote Rauschen, 20 % schnitte Mischbestände ab
      (gemessen: bei 10 % 1–6 Arten je Wabe, 0,19 MB). Erreicht keine
      Art 10 %, steht die führende trotzdem da — eine leere Liste wäre 0,
      und 0 heißt „keine Aussage", dann spräche ForestPaths.
    - **CC BY-SA, deshalb eine eigene Datei** — das Gitter ist ein
      abgeleitetes Werk (Auskunft der Autorin) und steht unter derselben
      Lizenz; die Lizenzseite sagt es. Nie mit DLR- oder
      ForestPaths-Werten in eine Datei mischen.
    - **Die Quelle ist nicht öffentlich**: Zugang auf Anfrage, der
      Freigabelink liegt nur im Secret `CH_TREE_SPECIES_URL`, sein Token
      wird im Workflow vor der ersten Anfrage maskiert. Auf einem
      Feature-Branch committet der Workflow das Gitter selbst (Artefakte
      sind aus der Cloud-Umgebung nicht abrufbar), auf `main` lädt er es
      als Artefakt hoch. **Neu bauen** (neue Kartenfassung): Branch
      `feat/ch-tree-species` von `main` anlegen und das Werkzeug
      anfassen — nur auf diesen Namen hört der Push-Auslöser —, dann
      PR mit Versions-Bump.
    - **Nur das Rechteck um die Schweiz** liegt im Asset (`x0`/`y0`/
      `width`/`height`); gefunden wird die Wabe über das GANZE Raster
      (`hexNearestCell` mit `grid_width`/`grid_height`), dann
      verschoben. `test/forest_species_ch_asset_test.dart` hält das Raster
      gegen das DLR-Gitter fest.
    - **Lärche fehlt in der Karte**, die Zeile sagt „Lärche nicht
      erfasst". Die Namen folgen dem DLR-Gitter, wo es dieselbe Art meint
      (Tanne, Kiefer, Birke).
    **Falle beim Bau** (2026-10-01): Die erste Messung hing stundenlang,
    weil `summarize` je Wabe `min()` über alle 700 000 Waben neu rechnete
    — quadratisch. Gefunden mit `faulthandler.dump_traceback_later` an
    einem gleich großen künstlichen Raster (`gdal_create`), nicht am
    Warp, den alle zuerst verdächtigt hatten.

- **Release-Anhänge sind aus dem Browser NICHT abrufbar** (#365/#366, seit
  1.111.0): `github.com/…/releases/download/…` schickt keinen
  `access-control-allow-origin`-Header, und der naheliegende Umweg über die
  API hilft nicht — deren 302 trägt CORS, das Ziel
  `release-assets.githubusercontent.com` nicht, und der Browser prüft am
  ENDE der Weiterleitung (gemessen 2026-09-02). Die PWA bekam damit weder
  Regengitter noch Stationstabelle.
  **Und es sah nach nichts aus:** Ohne Gitter fällt `rainPaintProvider` auf
  `RainPaint.dwd` zurück — die Karte zeichnet dann das absichtlich hart
  gerasterte DWD-Bild, und die Ampel schweigt. Der Fehler kam als zwei
  getrennte Meldungen an („Ampel ohne Regendaten", „Regenkarte nicht
  weich"), war aber eine Ursache. Wer im Web etwas nicht findet, prüfe
  daher zuerst CORS und nicht die Fachlogik.
  `rain-data.yml` spiegelt den Release-Stand deshalb nach jedem Lauf in den
  Branch `rain-data-mirror`, den `raw.githubusercontent.com` mit `*`
  ausliefert — ein Wurzel-Commit, force gepusht, damit die Historie nicht
  um mehrmals täglich 2 MB wächst. **Der Branch heißt bewusst nicht wie der
  Tag:** In einer raw-URL steht nur ein Name, und bei Gleichheit entschiede
  der Dienst, welchen er nimmt.
  Zwei Dinge, die man wissen muss:
  - **Es waren ZWEI Sperren hintereinander**, und eine allein zu lösen
    hätte nichts geändert: hinter CORS lag `path_provider`, das es auf Web
    nicht gibt. `RainGridRepository` cacht dort nichts mehr
    (`cachesToDisk`, per Konstruktor überschreibbar — sonst wäre der
    Web-Weg die einzige Strecke ohne Test, denn `kIsWeb` ist auf der
    Test-VM immer falsch).
  - **`forest-data` hat dasselbe Problem und ist NICHT gelöst.** Die feinen
    Waldblöcke sind ein Opt-in auf der Offline-Karten-Seite und damit
    Android-Sache; wer sie je im Web anbietet, braucht denselben Spiegel.

- **Das Modellgitter des Alpenraums** (`tool/model_weather.py`, im
  selben `rain-data.yml`, #612, seit 1.212.0): Wo Radar und
  DWD-Stationen enden, kommen Regen und Temperatur aus dem Wettermodell
  — Open-Meteo, `models=icon_d2` (ICON-D2, 2,2 km; seit dem 2026-09-26
  gepinnt statt `icon_seamless`, das in der Box dieselben Werte lieferte,
  ohne D2-Daten aber still auf ICON-EU zurückfiele), auf einem festen
  12-km-Raster in EPSG:3857 über der Box
  5,9–17,2° O / 45,6–49,1° N MINUS Deutschland (Polygon
  `DE_POLYGON`: West- und Südgrenze; 3 943 Punkte). Acht Dinge, die man
  wissen muss:
  - **Deutschland ist ein Polygon, keine Breite je Länge** (#664, seit
    2026-10-07). Vorher war es nur die Südgrenze, gelesen als „nördlich
    davon ist Deutschland“ — und sie begann mit einer Waagerechten bei
    47,56° N westlich von Basel. Elsass, Vogesen und Südlothringen
    hatten damit keinen Punkt; die Temperatur kam aus 55 km Entfernung
    bei Belfort. Nebenbei falsch war ein Streifen Innviertel östlich der
    Salzach (die Grenze läuft dort nach Westen zurück, das verträgt
    „Breite je Länge“ nicht). Der Selbsttest prüft jetzt Orte auf BEIDEN
    Seiten von Rhein und Salzach, und dass ein einzelner Tag ins Budget
    passt (`active <= BUDGET_CALLS`) — sonst käme nicht einmal gestern.
    **Neue Punkte füllen sich von selbst:** Ältere Tagesdateien tragen
    dort 255, nachgeholt wird nichts (`missing_dates` zählt Tage, nicht
    Punkte). Die virtuelle Station tritt nach 10 Tagen an, der
    Modellregen trägt die Ampel nach 26 Tagen; bis dahin bleibt es dort,
    wie es war.
  - **Die App fragt Open-Meteo nie.** CI holt feste Rasterpunkte —
    nichts über einen Nutzer —, die App lädt weiter nur vom eigenen
    Spiegel. Kein neues Netzziel, keine Änderung an Datenschutzerklärung
    oder `docs/play-console.md`; die Lizenzseite nennt Open-Meteo (CC BY
    4.0), `open-meteo.com` steht deshalb als `textOnly` im
    Datenschutz-Wächter.
  - **Modellregen ist das validierte Instrument, nicht das Radar.** Die
    Ampel wurde auf Open-Meteo-Archivdaten gemessen (IFS HRES 9 km,
    ERA5 davor); RADOLAN in der App ist die Abweichung davon. Das
    Modellgitter ist also kein Abstieg, und das Modell selbst bleibt
    Zahl für Zahl unverändert.
  - **Der Regen ist ein ZWEITER Stapel** (`model.rain` im Manifest,
    `model_rain_*`, gleiche Kodierung wie `rain_day_*`), und der
    Vorrang ist EINE Regel: `rainCoursesFromStacks` (seit 1.222.0
    Alpenstapel, Radar, Modell; je Tag und Punkt der erste Wert) für Blatt und Nachlauf, `AmpelLevels`
    (je Wabe die erste Aussage) für die Fläche. Beide lesen
    `rainStacksProvider`. Ein Umrastern auf ein Gitter wäre eine dritte
    Antwort auf „wie viel Regen hier". `RainDay.source` und
    `RainCourse.modelDays` tragen die Herkunft, das Blatt zählt sie
    („2 von 14 Tagen aus Modellwerten").
  - **Die Temperatur kommt als VIRTUELLE STATIONEN** in
    `weather_stations.json.gz` (`src: "openmeteo"`, id ab 900000,
    Höhe = Open-Meteos eigene Downscaling-Höhe, Name „Modell 46,50° N
    11,35° O"). Nachbarsuche, Höhenkorrektur und Ampel-Fläche bleiben
    unverändert; nur `AirStation.model` und der Satz im Blatt („kein
    Messwert") kommen dazu. Nebengewinn: Österreich und die Schweiz haben
    damit einen Punkt in wenigen Kilometern statt einer deutschen
    Station in 100 km. Austernseitling & Co. rechnet seit #676 ohne
    Bodenfeuchte und damit überall mit. Herbsttrompete & Co. braucht
    sie, und die gibt es bisher nur von DWD-Stationen: im Landesinneren
    von AT/CH grau, an der Grenze bis 30 km mit einer deutschen Station
    (#665). Eine Feuchte fürs Ausland (ERA5-Land) ist #676.
  - **Die Tagesdateien SIND der Zustand.** Rain, tmax, tmin (0,5-°C-
    Schritte) je Tag plus `model_elevation.bin.gz` liegen im Release
    `rain-data` wie die Radar-Tage; jeder Lauf holt nur fehlende Tage,
    neueste zuerst, innerhalb `BUDGET_CALLS` (4 500 je Lauf — Open-Meteo
    Free: 600/min, 5 000/h, 10 000/Tag; ein Ort für ≤ 7 Tage ist ein
    Call, vier Wochen drei). Lücken kommen über die
    Historical-Forecast-API mit festen Daten, der jüngste Block über
    `past_days`. Beide liefern die archivierten ersten Stunden derselben
    Modellläufe.
    **Ein Lauf holt genau EIN Fenster** (3 943 Punkte fressen das Budget
    schon mit einem Tag), und im täglichen Lauf ist das immer gestern.
    Eine ältere Lücke kam deshalb nie dran: Vom 2026-09-26 bis 30 stand
    der Stapel bei 12 von 28 Tagen, und die Ampel war außerhalb
    Deutschlands grau (26 Regentage nötig). Seither läuft `model` ein
    zweites Mal am Tag (`41 18`), findet gestern schon vor und holt die
    jüngsten sieben Tage der Lücke (bis #664 acht); ohne Lücke fragt er nichts. Zwei
    holende Läufe müssen eine Stunde auseinander liegen (5 000/h) —
    `MIN_FETCH_GAP` über `last_fetch` im Manifest, weil der Cron von
    GitHub Stunden zu spät kommen kann. Der Selbsttest rechnet den
    Stillstand mit dem ECHTEN Verhältnis von Punkten zu Budget nach;
    der alte mit 150 Punkten hatte Platz für drei Wochen und sah ihn nie.
  - **Der Stapel hält 30 Tage** (`STACK_DAYS`, seit 1.220.0), nicht
    mehr 28: Die Ampel braucht 26 Regentage, die Stationstabelle 28
    Temperaturtage, die Regen-Ebene „30 Tage" im Alpenraum alle 30. Die
    virtuellen Stationen nehmen weiter nur die 28 Tage der Tabelle.
  - **Reihenfolge im Workflow: `daily weather model`.** Das Werkzeug
    hängt seine Punkte an die Stationstabelle DIESES Laufs und korrigiert
    `weather.bytes` (der Cache-Schlüssel der App). Ein Handlauf nur mit
    `model` holt die Tabelle vorher aus dem Release. **Jeder Lauf holt
    vorher die `model_*`-Dateien des Release**: Die virtuellen Stationen
    tragen 28 Tage, das Werkzeug liest also jeden Tag des Manifests, nicht
    nur die neu geholten. Der erste Lauf hatte keine Vortage und ging
    durch, der erste Folgelauf (2026-09-26) scheiterte an den fehlenden
    Dateien; `test/release_workflow_test.dart` hält den Schritt fest. Eigene
    Aufräumliste `model_keep.txt`, eigener Lösch-Schritt für `model_*`.
    `--verify` fragt sechs zufällige Punkte einzeln nach — die eine
    Prüfung, die ein verschobenes Raster oder vertauschte Max/Min sieht.
  - **Die Messbasis dazu** (`docs/pilzampel-pruefachsen.md` #12–#15):
    Mit CC0/CC BY war die italienische Alpenbox zu dünn (Pfifferling 29
    Paare, Kontrolle verzerrt). Mit CC BY-NC — **nur für Messungen**,
    Betreiber 2026-09-25, `--include-nc`, nie für DE, nie für ein Asset —
    besteht das Pfifferling-Fenster dort (+0,183 [+0,055, +0,328], 142
    Paare). Für `herbst` ist der Klassen-Hold-out leer (Fenster =
    Referenz, fünfter Ausgang „leer" seit #616); beschreibend trennt
    13 °C dort mit AUC 0,63–0,78.

- **Der gemessene Alpenstapel** (`tool/alps_rain.py`, im selben
  `rain-data.yml`, #646, Daten seit #650, App seit 1.222.0): GeoSphere
  INCA (AT), MeteoSchweiz RprelimD (CH+LI) und Radar-DPC (IT), in CI zu
  EINEM Stapel `alps_rain_*` gemischt — samt Radar und Modell im
  Grenzband. Herleitung und Messung stehen in
  `docs/regendaten-alpenraum.md`. Sechs Dinge, die man wissen muss:
  - **Gemischt wird in CI, nie in der App.** Die Länderzuordnung wird
    weichgezeichnet (~30 km), die Gewichte summieren je Zelle exakt zu
    1; der Selbsttest prüft das an der ECHTEN Grenze (gleiches Feld rein
    ⇒ gleiches Feld raus). Eine zweite Mischstelle in der App wäre eine
    zweite Antwort auf „wie viel Regen hier".
  - **Vorrang Alpenstapel > Radar > Modell**, an EINER Stelle
    (`rainStacksProvider`, Test `rain_stacks_order_test.dart`). Im
    deutschen Landesinneren ist der Stapel leer (255), dort antwortet
    das Radar mit demselben Wert. Die Ampel liest dieselbe Liste.
  - **Die Fläche**: `alpineFillGrid` — gemessen, wo der Stapel etwas
    sagt, sonst Modell (bilinear in 1 km), aber nur, wo auch Radar/W4
    schweigen; die Radarfläche spart den Stapel ihrerseits aus. Jede
    Zelle genau einmal (Test). Die MapLibre-Quelle heißt weiter
    `regen-modell`.
  - **CC BY-SA als Ganzes** (Betreiber, 2026-10-01): Radar-DPC steht
    unter BY-SA, also die Mischung auch. Sie liegt als eigene Datei im
    Release, nie im Binary; Lizenzseite und Regen-Blatt nennen es.
  - **Ein Tag wird unter GLEICHEM Namen neu gemischt**, sobald eine
    Landesquelle nachliefert (GeoSphere/DPC nach zwei, MeteoSchweiz nach
    drei Tagen). Der Zwischenspeicher der App trägt deshalb die
    Prüfsumme im Namen (`RainStackDay.cacheName`) — NUR beim
    Alpenstapel, obwohl auch Radar- und Modelltage eine im Manifest
    tragen: Sonst lüde jedes Gerät nach dem Update beide Stapel neu.
  - **Die Herkunftsbits** (`alps_origin_*`, `AlpsOrigin`) sagen dem
    Spot-Blatt, wer gemessen hat. Sie kosten fast so viel wie die Werte;
    der Ampel-Nachlauf lässt sie weg (`withOrigin: false`, Messung in
    `docs/map-performance.md`). Bits und Werkzeug hält ein Test
    zusammen.

- **Regen-Wertegitter** (`tool/rain_grid.py` + `.github/workflows/rain-data.yml`):
  Damit die Summen in **unseren** Farben liegen und die Regenmenge am Spot
  beantwortbar wird, ohne dass eine Koordinate das Gerät verlässt, holt CI
  die Rohwerte über WCS und legt sie als Wertegitter (1 Byte je km²,
  Zeilen-Delta + gzip, ~216 KB) samt `rain_manifest.json` auf den **festen
  Tag `rain-data`** — kein Versions-Bump, deshalb kein Konflikt mit dem
  Version Guard, und für die App kein neues Netzziel (GitHub-Releases
  stehen längst in der Datenschutzerklärung). Nur Standardbibliothek, wie
  `feedback_bot.py`; der GeoTIFF-Leser akzeptiert ausdrücklich nur
  unkomprimierte 64-Bit-Floats mit einem Band und bricht sonst ab, statt
  Zahlen zu raten.
  **Die Falle, und sie ist still:** Eine `GetCoverage`-Anfrage **ohne**
  `subset=time(…)` schlägt nicht fehl — GeoServer verschmilzt alle
  Granulate des Mosaiks und liefert etwa doppelte Werte, in einem Gitter
  richtiger Größe mit plausiblem Median. Mit der Zeitangabe stimmen die
  Werte auf die Nachkommastelle mit `GetFeatureInfo` überein. Deshalb
  läuft nach jedem Bau `--verify`: 24 zufällige Punkte gegen den Dienst,
  und der Lauf bricht ab, wenn zu viele außerhalb der 3×3-Nachbarschaft
  ihrer Zelle liegen (mit Zeitangabe 23/24 drin, ohne 7/24 — gemessen).
  Zwei weitere Eigenheiten des Dienstes: der native `outputCrs` scheitert
  („Unable to map projection Stereographic_North_Pole"), es muss
  `EPSG:3857` mitgegeben werden; und Nichtdaten kommen sowohl als `-1.0`
  als auch als `NaN`.
  `--self-test` läuft netzfrei im Job „Analyze & Test" mit.
  **Nicht** `GetFeatureInfo` je Spot benutzen, so verlockend es ist: Das
  wäre die geheime Fundstelle, an den DWD geschickt. Genau dafür liegt das
  Gitter auf dem Gerät.

