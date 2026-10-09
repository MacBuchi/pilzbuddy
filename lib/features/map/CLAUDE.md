# PilzBuddy — Arbeitsregeln für `lib/features/map/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Die „Neue Karte" vom eigenen Kartenhost** (#630 Stufe 1, seit
  1.214.0, `lib/features/map/online_map.dart`): Die Online-Karte liest
  per Range-Anfrage DASSELBE DACH-Archiv, das TrailBuddy nutzt
  (`tiles.mcbuchi.de/trailbuddy/dach.json` → `dach-<build>.pmtiles`,
  Protomaps z0–13, Cloudflare R2). Geschnitten wird dort, in
  TrailBuddys `map-data.yml`; hier wird nur gelesen. Plan und Stufen
  stehen in #630. Fünf Dinge, die man wissen muss:
  - **Hinter einem Schalter, ab Werk AUS** (`newMapEnabledProvider`,
    Profil „Neue Karte (Vorschau)"). Aus heißt: keine einzige Anfrage an
    den Host — `test/online_map_test.dart` zählt es, und der
    Datenschutz-Wächter führt den Host deshalb als `afterConsent`.
  - **OSM ist der Rückfall, und die Regel steht an EINER Stelle**
    (`onlineMapProvider`): kein Schalter, kein Empfang, Manifest nicht da
    oder nicht lesbar, Archiv nicht zu öffnen ⇒ `null` ⇒ beide Engines
    zeichnen genau das, was sie ohne Schalter zeichnen. Regionen gehen
    weiter vor.
  - **Das Archiv wird auch für MapLibre geöffnet**, obwohl MapLibre es
    selbst liest (`pmtiles://https://…`). Nur so ist „erreichbar"
    geprüft: Ein Manifest, das kommt, während das Archiv mit 403
    antwortet (Cloudflares Bot-Abwehr, TrailBuddy #55), ließe MapLibre
    leere Kacheln zeichnen — ohne Rückfall. Beide Schritte tragen eine
    Grenze von 10 s, weil MapLibre mit dem Style auf die Antwort wartet.
  - **Das Manifest schreibt ein anderes Repo.** `MapManifest.fromJson`
    wirft bei allem, was nicht passt, und der Test hält TrailBuddys
    heutige Form fest. Ändert TrailBuddy sie, wird die Vorschau zur
    alten Karte statt zu einer kaputten.
  - **Die Übersicht liegt UNTER der Neuen Karte** (anders als unter
    OSM): Es ist derselbe Kartenstil, #137 betraf zwei verschiedene.
    `test/base_map_layer_test.dart` hält beide Fälle fest.
  - **Ohne Empfang kein OSM-Rückfall, wenn die Neue Karte gewählt ist**
    (`osmFallbackAllowedProvider`, seit 1.218.0; Feldbefund in der PWA:
    „die alte Online-Karte hat sich teils geladen"). Die Annahme aus
    #118, ohne Netz komme keine OSM-Kachel, stimmt nicht: Browser- und
    Platten-Cache geben einzelne alte heraus, ein Flickenteppich im
    fremden Stil. Mit Empfang bleibt OSM der Rückfall für einen
    unerreichbaren Host; wer die Neue Karte AUS hat, behält das alte
    Verhalten.
  - **MapLibre bekommt die Kacheln von der App, nicht vom Host**
    (#659, seit 1.222.4, `online_tile_server.dart`). `pmtiles://https://…`
    holte vor jeder Kachel den Header, jede Kachel 2- bis 3-mal und nach
    dem Neustart alles neu: 50 R2-Operationen je Start, gemessen über
    einen Zähl-Proxy (#630). Ein Server NUR auf Loopback liefert jetzt
    aus dem Archiv, das `onlineMapProvider` ohnehin öffnet; danach sind
    es 8 bzw. 2 im bekannten Gebiet. Vier Dinge:
    - **Klartext nur zu `127.0.0.1`** (`network_security_config.xml`);
      ohne die Ausnahme blockiert Android ab API 28 auch Loopback, und
      MapLibre zeichnet leer, ohne Fehler.
    - **Der Speicher liegt im Cache-Verzeichnis** (`getTemporaryDirectory`,
      64 MB): nie im Backup, vom System räumbar. Archivdateien tragen
      das Datum im Namen, abgelegte Kacheln brauchen nie eine Nachfrage.
    - **Ausgeliefert wird gzip, wie es im Archiv liegt** — kein
      Entpacken im Main-Isolate, kein weiteres Isolate (#641).
    - **Startet der Server nicht, bleibt `pmtiles://`.** Ob es überhaupt
      eine Neue Karte gibt, entscheidet weiter nur `onlineMapProvider`.
    Wer misst: Mess-Build mit `kMapTilesBase` auf `127.0.0.1:8099`,
    dort ein Proxy, der weiterleitet und je Anfrage eine Zeile schreibt,
    dazu `adb reverse tcp:8099 tcp:8099`. Zahlen in
    `docs/map-performance.md`.
  **Seit 1.217.0 ab Werk AN** (Stufe 3). Der Schalter bleibt als
  Ausweg („Neue Karte" im Profil, aus ⇒ keine Anfrage an den Host, der
  Test zählt es weiter); `FakeSettings` steht dagegen auf AUS, damit kein
  Bestandstest ein Manifest abruft. Datenschutz-Wächter: `fetched` statt
  `afterConsent`.
  **Gemessen am 2026-10-02** (#630, #659): Jede Anfrage an den Host ist
  eine R2-Class-B-Operation (`cf-cache-status: DYNAMIC`, das Archiv ist
  zu groß für den Edge-Cache). Seit dem Kachel-Server sind es etwa 8 je
  Erststart, 2 je weiterem Start und 1 je neuer Kachel; das
  Freikontingent (10 Mio./Monat, mit TrailBuddy geteilt) ist damit weit
  weg. Was der Host von TrailBuddy zählt, ist dort nicht gemessen.

- **Gemeldete Fundorte (GBIF) als Kartenebene** (#467, seit 1.154.0):
  je Meldung einer unserer Arten EINE Scheibe in der Größe ihrer
  Koordinaten-Unschärfe, gefärbt nach Ampel-Gruppe, gefiltert über
  `SpotFilter` (Art UND Gruppe, kein zweiter Wähler — die Gruppen-Chips
  stehen seit 1.155.0 als geteiltes `AmpelClassChips` auch im
  Fundorte-Blatt, und der Kartenfilter zeigt sie, sobald Ampel-Vorschau
  ODER Ebene an ist). Dazu „Im Umkreis
  von 5 km gemeldet" im „Was ist hier?"-Blatt. Fünf Dinge, die man
  wissen muss:
  - **Keine Heatmap, und zwar gemessen** (`docs/gbif-fundorte-messung.md`):
    In Sammler-Auflösung wäre eine Dichtekarte auf 91–98 % von DACH
    leer, und leer läse sich als „hier wächst nichts". Eine Scheibe
    behauptet nur „hier hat jemand gemeldet, auf so viel Meter genau".
    Wortlaut überall: „gemeldet", nie „wächst"; keine Scheibe heißt
    „keine Meldung", nicht „nichts da".
  - **Die drei Länder melden GRUNDVERSCHIEDEN**, und das sieht man auf
    der Karte: Deutschland scharfe Punkte (≤ 250 m, naturgucker und
    iNaturalist), die Schweiz 3535 m (SwissFungi meldet
    Kilometerquadrate — die halbe Diagonale von 5 km), Österreich
    Rasterpunkte OHNE Unschärfe-Angabe (ÖMG, 11 Meldungen je
    Koordinate). Unbekannt wird wie ein Quadrat gezeichnet — die
    größere Scheibe ist die harmlose Fehlerrichtung. Über 10 km fliegt
    raus.
  - **Aus dem lokalen Download gebaut, nie über die API**
    (`tool/gbif_finds.py build`, DOI im Manifest,
    `tool/generated_assets.py` wacht über die Prüfsumme). Gruppiert je
    (Art, Koordinate, Unschärfe) mit Zähler und jüngstem Jahr: 305 506
    Meldungen werden 147 734 Orte, 636 KB. **Keine Meldernamen im
    Asset** — `recordedBy` ist eine Person, das Asset liegt in jedem
    APK. Die Quell-Datensätze stehen im Manifest und kommen daraus auf
    die Lizenzseite (CC-BY-Nennung je Datensatz).
  - **Gezeichnet über die PNG-Overlay-Strecke** wie Wald und Regen,
    also auf beiden Engines gleich. Scharf und grob tragen verschiedene
    Deckkraft (130/48), die Summe ist bei 175 gedeckelt — auf einem
    Rasterpunkt mit dreißig Arten wäre die Karte sonst zu. Über dem
    Budget (24 M Pixeloperationen; 40 000 Schweizer Quadrate bei
    100 km Fensterbreite wären 360 M) werden die groben Scheiben in
    einem verkleinerten Puffer gemalt und bilinear hochgezogen; die
    scharfen bleiben immer in voller Auflösung.
  - **Beobachten ist laden** gilt auch hier: `gbifFindsProvider` hängt
    nur am eingeschalteten Schalter und am „Was ist hier?"-Blatt. Die
    Legende zählt seit 1.200.0 die Meldungen je Gruppe im 5-km-Umkreis
    (`legendGbifCountsProvider`), fragt aber ZUERST den Schalter — ist
    die Ebene an, hat die Fläche das Asset ohnehin gelesen. Gezählt wird
    mit DERSELBEN Auswahl wie gemalt (`gbifShown`, `gbifClassCountsFrom`
    in `gbif_fill.dart`), sonst zählte die Legende Scheiben, die niemand
    sieht. In der Schiene sind es dünne Balken als EIGENE Zone, nicht ein
    dritter Balken neben Regen und Wald: So lief die Reihe 11 px aus der
    40-px-Schiene, und nur ein Test mit ALLEN Ebenen zugleich sieht das
    (`test/flows/map_legend_flow_test.dart`). Der Filter-Schlüssel reist als
    zusammengefügte Zeichenkette (zwei gleiche Mengen sind für `==`
    verschieden) und steht im Dateinamen der Fläche, sonst tauscht
    MapLibre das Bild nicht.

- **Schutzgebiete** (#580, seit 1.201.0): Wo Pilze sammeln meist
  verboten ist, schraffiert die Wald- und Ampelfläche statt zu füllen,
  und „Neuer Spot"/„Fund eintragen" sagen es in einem Satz. Beides liest
  EIN Gitter (`lib/features/map/protected_areas.dart`, gebaut von
  `tool/protected_areas.py` aus OSM, Workflow `protected-areas.yml`).
  Sieben Dinge, die man wissen muss:
  - **Die Regel hat der Betreiber entschieden** (2026-09-23):
    Naturschutzgebiete, Nationalparks, Kernzonen — auch Flächen, die nur
    `leisure=nature_reserve` tragen. NICHT Landschaftsschutzgebiete,
    Natur-/Regionalparks, Natura 2000. Ein ausdrücklicher Schutztitel
    entscheidet vor dem Namen; der erste DACH-Lauf hatte es andersherum
    und verlor 48 echte Naturschutzgebiete („Vogelschutzgebiet
    Heisinger Bogen", „Bannwald Wehratal"). Messung und Fehlschläge
    stehen in #581.
  - **Nicht aus den Kartenkacheln.** Deren Flächen tragen nur `kind`,
    und Schweizer Regionalparks kommen dort als `nature_reserve` an —
    29 × 16 km, von einem Naturschutzgebiet nicht zu unterscheiden.
  - **Keine Bevormundung** (Betreiber): kein Schalter, keine Sperre,
    keine Rückfrage; das Ampel-Banner bleibt unverändert. Der Hinweis
    sagt „wahrscheinlich" und „meist" — die Waben sind 250 m, und was im
    Gebiet gilt, regelt dessen Verordnung, nicht die App.
  - **Schweigen heißt nicht „erlaubt".** Daten gibt es für DE, AT, CH
    und LI; die Nachbarländer im Raster sind leer. Deshalb steht nirgends
    „kein Schutzgebiet". Südtirol wartet auf die Auskunft der Provinz
    (#623 Teil B) — die Sammelregeln dort sind andere, und geraten wird
    nicht. Bis dahin steht beim Eintragen dort ein Satz, der sagt, WAS
    fehlt (`south_tyrol.dart`, Provinzumriss aus OSM, ~1 km; Betreiber
    2026-10-09). Kommen die Daten, fällt der Satz für Stellen MIT Gebiet
    von selbst weg — für die übrigen ist dann neu zu entscheiden.
  - **In Tirol amtliche Daten statt OSM** (#623, seit 1.224.4, Betreiber
    2026-10-08: „ersetzen"): Innerhalb der Landesgrenze verliert OSM
    jede Wabe, deren Mittelpunkt dort liegt; es zählen nur die 92
    Flächen des Landes (CC BY 4.0, eigener Eintrag auf der Lizenzseite).
    Warnen: NSG, SSG, Nationalpark-Kernzone; still: LSG, Ruhegebiet,
    GLT, Außenzone. Anlass war der Abgleich: OSM verfehlte 77 % der
    NSG-Fläche (Karwendel fast ganz) und warnte in der ganzen Außenzone
    Hohe Tauern. Sonderschutzgebiete stehen als `Naturschutzgebiet` im
    Gitter und tragen das Wort im Namen; `label` erkennt es. Weitere
    Länder: Eintrag in `OFFICIAL` (`tool/protected_areas.py`) samt
    Einordnung je Kategorie.
  - **Läufe je Zeile statt ein Wert je Zelle**: 0,6 statt 27 MB im
    Speicher, und das volle Gitter wird nie ausgepackt. Die Schraffur
    schlägt je Wabe am MITTELPUNKT nach (wie das Leuchten), erst ab
    `hatchMinHexPx` Wabenbreite — darunter wären die Streifen breiter als
    die Gebiete. Das Muster hängt an Kartenkoordinaten, sonst spränge es
    bei jedem Neuplanen des Fensters; `test/forest_fill_hatch_test.dart`
    hält das fest.
  - **`nsg` gehört in den Dateinamen der Fläche** (`forestFillVariant`):
    Die erste Fläche nach dem Start kann vor den Schutzgebieten fertig
    sein, und MapLibre tauscht ein Bild nur bei neuem Namen.
  Aktualisiert wird vierteljährlich: Workflow laufen lassen, Artefakt
  prüfen (`python3 tool/protected_areas.py lookup` an Stichproben), als
  Asset committen, `tool/generated_assets.py --update`.

- **Der lange Tipp öffnet ein Kontextmenü** (#483, seit 1.149.0):
  „Was ist hier?" (#245), „Navigation" (#367) und „Heranzoomen". Alle
  drei Ziele gab es schon; neu ist der Weg dorthin.
  **Damit konnte der Schalter entfallen.** Die Geste stand seit #210 ab
  Werk AUS, weil sie sofort die Kamera warf — „ein Fehlgriff aus der
  Übersicht warf einen woanders hin", und entschärfen ließ sie sich
  nicht, da keine der beiden Bibliotheken Haltedauer oder Toleranz
  einstellen lässt. Ein Menü IST die fehlende Entschärfung: Ein
  versehentliches Menü wischt man weg, ein versehentlicher Kamerasprung
  kostet die Orientierung. Der Sprung überlebt als dritter Eintrag und
  ist damit eine Wahl statt eines Unfalls. `map_gestures.dart` und der
  Prefs-Schlüssel `map_long_press_enabled` sind weg.
  Vier Dinge, die man wissen muss:
  - **Die Fassade reicht die Bildschirmposition mit durch**
    (`onLongPress(latLng, screenPoint)`). Beide Engines liefern sie im
    Ereignis; sie wegzuwerfen und aus `LatLng` zurückzurechnen wären
    zwei Wege für dieselbe Zahl. **MapLibre meldet sie LOKAL zur
    Kartenfläche**, flutter_map global — die MapLibre-Seite rechnet
    deshalb um, sonst säße das Menü um die Höhe der Statusleiste zu
    hoch.
  - **Die Geometrie ist rein** (`MapContextMenuLayout`) und deshalb
    prüfbar: Auf einer bildschirmfüllenden Karte ist der Rand der
    Normalfall, und ein Menü, das dort hinausragt, ist genau dann
    kaputt, wenn man es braucht. Richtung folgt dem Platz — nach oben,
    solange oben Platz ist, nach links, wenn rechts keiner ist.
  - **Vier Einträge seit 1.177.0, und „Neuer Spot" ist der erste**
    (#513, Feldwunsch). Er liegt am Finger, weil die Reihenfolge nach
    Nähe geht, und trägt als einziger eine Füllfarbe — genau einer,
    sonst hebt sich nichts mehr ab. Der Weg dahinter ist DIESELBE Naht
    wie beim Fadenkreuz (`_addSpotAt`); zwei Kopien wären zwei Stellen,
    an denen die Doppel-Spot-Warnung vergessen werden kann.
    **Name und Farbe kommen aus `new_spot_style.dart`**, für Knopf UND
    Eintrag (seit 1.192.1). Vorher hieß der Eintrag „Spot anlegen" und
    war fest `forestGreen`, der Knopf hellgrün aus dem Theme; der
    Kommentar behauptete eine Ableitung, die es nicht gab, und der Test
    prüfte die Konstante. Er vergleicht jetzt mit dem KNOPF.
  - **Der Fächer ist ein Bogen, aber ein flacher** (#513). Der
    seitliche Versatz folgt einem Viertelkreis, die STUFENHÖHE bleibt
    fest — sie verhindert das Überlappen, und ein Bogen, der auch
    senkrecht rundet, drängt die oberen Chips ineinander. Ein echter
    Fächer um den Punkt geht nicht, und das ist gerechnet: Bei 190 px
    breiten Pillen bräuchte ein Kreis rund 190 px Radius, damit sich
    zwei Chips vertikal nicht berühren — der unterste läge dann fast
    200 px seitlich plus eigene Breite, auf keinem Telefon im Bild.
    Der Test misst den Unterschied zur Geraden daran, dass der Zuwachs
    je Stufe KLEINER wird.
  - **44 px bleiben 44 px.** Ein aufgefächertes Menü darf von der
    Trefferfläche nichts abziehen, nur weil es hübsch aussieht; die
    Begründung steht an `_Tool` in `map_screen.dart`.
  - **Kein Dauerhinweis auf der Karte.** Bis 1.148.0 stand dort eine
    Erklärzeile, solange der Schalter an war. Mit einer Geste, die immer
    an ist, stünde sie auf jedem Bildschirm und kostete Platz über den
    Bannern — sie wohnt jetzt in `help_screen.dart`.

- **Höhenlinien auf der Karte** (seit 1.98.0): Dieselben Daten, eine
  zweite Verwendung — die Ebene rechnet Isolinien **auf dem Gerät**
  (`lib/features/map/elevation_contours.dart`) und baut dafür KEINE
  Verbindung auf: kein neues Netzziel, keine Änderung an
  Datenschutzerklärung oder `docs/play-console.md`. Höhendaten sind
  kein OSM-Inhalt; eine topografische Kachelquelle wäre ein fremder
  Freiwilligen-Server und ausgerechnet im Funkloch tot.
  Vier Dinge, die man wissen muss:
  - **Eine Isolinien-Maschine für zwei Ebenen** (`contours.dart`):
    Marching Squares, Douglas-Peucker und Chaikin lagen bis 1.97.0 in
    `rain_contours.dart`, obwohl an ihnen nichts regenhaft ist. Zwei
    Kopien hätten mit der Sattelpunkt-Auflösung und der Verkettung
    über Kantenkennungen genau zwei Stellen, an denen sie still
    auseinanderlaufen. `rain_contours.dart` ist seither die
    Regen-Hülle.
  - **Das 3×3-Glätten ist Pflicht, nicht Geschmack.** Es bricht die
    20-Meter-Entartung (eine Stufe genau auf einem Rohwert lässt die
    Linie als Treppe über die Zellmitten laufen) UND den
    Paritätsversatz des odd-r-Hexgitters (benachbarte Abtastzeilen
    holen aus Waben, die eine halbe Wabe versetzt liegen — auf einem
    10-%-Hang ±13 m im Wechsel, als Sägezahn sichtbar). Beide Fälle
    hält `test/elevation_contours_test.dart` fest.
  - **Die Äquidistanz fällt aus dem GELÄNDE** (seit 1.99.0), nicht aus
    einer Zoomtabelle: `reliefPerPixel` misst das 75. Perzentil der
    Höhenunterschiede zwischen Nachbarzellen, und daraus folgt
    „Äquidistanz ≥ 20 px · Relief-je-Pixel"; schafft selbst 200 m das
    nicht, wird gar nicht gezeichnet. Bis 1.98.0 stand dort ein
    UNTERSTELLTER Hang von 10 % — in den Alpen das Drei- bis Fünffache,
    und die Ebene wurde dort zur Schraffur (Betreiber, 2026-08-21).
    Die Punktschranke ist seither nur noch ein Netz. Gemessen in
    `docs/map-performance.md`.
  - **Jede Schwelle der Linien steht in BILDSCHIRMPIXELN, nie in
    Gitterzellen** (seit 1.99.1). Eine Zelle ist beim Herauszoomen ein
    Pixel und beim Hineinzoomen ein halber Schirm — eine feste Zahl in
    Zellen ist dort am schärfsten, wo sie am wenigsten darf. Gemessen
    am Gerät (2026-08-21, Alpen bei 300 m Maßstab): Wabe 55 px,
    Vereinfachung `toleranceCells = 2` also 110 px, bei 20–35 px
    Abstand zur Nachbarlinie. Die Linien kreuzten sich zwangsläufig und
    waren lange Geraden statt Kurven. Jetzt rechnet `contourLinesFor`
    Toleranz (`contourSimplifyPixels = 1.5`) und Mindestlänge aus
    `pixelsPerCell`; die Vorgaben der Maschine bleiben für den Regen
    stehen. `test/elevation_contours_test.dart` prüft an einem Kegel,
    dass sich zwei Nachbarstufen nie schneiden.
  - **Das Abtastraster hängt am GITTER, nicht am Fenster** (seit
    1.99.1, `contourSampleLattice`): ganzzahliges Vielfaches der
    Wabenweite, Ursprung auf das Gitter gerastet. Vorher wurde die
    Fensterspanne in `cols` gleiche Teile geteilt — beim Schieben plante
    `planFillWindow` ein neues Fenster, das Raster lag woanders, jeder
    Punkt traf eine andere Wabe, und die Linien würfelten sich neu.
    **Und der Ursprung liegt einen VIERTELSCHRITT daneben**
    (`_hexSampleOffset`): Ein odd-r-Hexgitter hat seine Mittelpunkte in
    geraden Zeilen bei `hx + 0,5`, in ungeraden bei `hx + 1,0` — eine
    Probe bei `i + 0,5` liegt dort also genau zwischen zwei Waben, und
    das letzte Bit entschied, welche gewinnt. Ohne den Versatz wichen
    69 von 495 Proben zweier versetzter Fenster voneinander ab, mit bis
    zu 180 m; mit ihm sind es 0. Wer ihn wegnimmt, holt das Zittern
    zurück, und der Test dazu sagt es sofort.
    Nebeneffekt: weit draußen ist es SCHNELLER (77 statt 150 ms), weil
    der ganzzahlige Faktor vergröbert, statt das Budget mit gestreckten
    Zellen vollzuschreiben. Und Chaikin rundet geschlossene Ringe
    seither zyklisch — sonst behält der Nahtpunkt als einziger seine
    Ecke.
  - **Die Regeln rechnen in Meter-je-Pixel, nie in Zoomstufen.**
    MapLibre zählt Zoom in 512-dp-Kacheln, flutter_map in 256ern —
    dieselbe Zahl bedeutet auf Android und Web zwei Maßstäbe, und
    1.98.0 lag auf Android damit durchweg eine Stufe daneben (am Gerät
    nachgemessen: Karte auf 12,0, Regel rechnete mit 11). Deshalb
    trägt `onCameraIdle` KEINE Zoomstufe mehr über die
    MapView-Fassade; `groundResolution(bounds, pixelbreite)` im
    Karten-Screen ist die eine eindeutige Größe. Wer das je zurückdreht,
    holt den Fehler zurück.
  - **Die Hauptlinien tragen ihre Höhe** — und zwar etwa alle 100
    Höhenmeter (`contourIndexStepM`), NICHT „jede fünfte": Bei 100 m
    Äquidistanz wäre jede fünfte alle 500 Höhenmeter, und in einem
    Talkessel stünde dann keine einzige Zahl auf dem Schirm. In MapLibre eine eigene
    Symbol-Ebene auf der Hauptlinien-Quelle (`symbol-placement: line`,
    `text-field: "{m}"` — die Token-Schreibweise, weil Ausdrücke bei
    `maplibre` 0.3.5 durch `toJObject()` gehen); auf der
    flutter_map-Strecke gedrehte Marker aus `contourLabels`, weil der
    Canvas-Renderer keine Beschriftung entlang einer Linie kann. Beide
    Engines sollen dasselbe sagen.
  - **Kein `ref.watch` aufs Gitter am FAB** — beobachten IST laden, und
    das hieße 3,4 MB bei jedem App-Start auszupacken. Das Blatt sagt
    stattdessen, wenn das Gitter fehlt („kein Fehler ohne
    Fehlermeldung"): ein Satz ist mehr als ein verschwundener Knopf.
    **Seit 1.99.4 gilt das auch für den Wald-Knopf**, der bis dahin die
    Regel „kein Knopf ohne Gitter" befolgte und dafür bei jedem Start
    13,3 MB auspackte (136 ms gemessen). Der Wächter half dort nichts:
    Ist das Gitter da, ist die Entscheidung längst gefallen, und falsch
    werden konnte die Prüfung nur bei einem beschädigten APK. Die alte
    Begründung („derselbe Provider, den die Karte ohnehin braucht")
    stimmte seit #249 nicht mehr — Fläche und Blöcke steigen bei
    ausgeschalteter Ebene aus, bevor sie das Gitter anfassen.
    `test/flows/forest_layer_flow_test.dart` hält beides fest: dass der
    Start nicht mehr lädt und dass das Blatt es sagt.
    Nebenbefund: Mit dem neunten Knopf lief die FAB-Spalte auf 520 px
    über; sie steckt seither in einem `FittedBox(scaleDown)`.

- **Karten-Engine:** Seit 1.43.0 rendert Android standardmäßig mit
  MapLibre (nativer Renderer, `maplibre` 0.3.5 exakt gepinnt) hinter der
  MapView-Fassade (`lib/features/map/map_view/`); Grundlage ist der
  nachgemessene Direktvergleich in `docs/map-performance.md`
  (Wiederholung: `tool/measure_map.sh`). Web rendert weiterhin
  flutter_map (bedingter Import, Web-Build sieht `package:maplibre`
  nie).
  **Seit 1.146.0 (#433) gibt es dazwischen keinen Schalter mehr.** Das
  Profil-Opt-out (`classicMapEnabled`) war als befristete Rückfalllinie
  gedacht, und die Frist ist um: zehn Wochendigests ohne einen einzigen
  Fund gegen MapLibre. Die Engine-Wahl ist jetzt `if (!kIsWeb)` in
  `mapViewBuilderProvider` — eine Kompilierzeit-Konstante, in jedem
  Build vorentschieden. Zwei Prefs-Schlüssel liegen auf
  Bestandsgeräten herum und werden nie wieder gelesen
  (`maplibre_enabled` aus der Beta, `classic_map_enabled` danach);
  `map_engine.dart` ist gelöscht.
  **Kleiner wird das APK dadurch NICHT**, und das ist die Korrektur an
  der Annahme im Issue: `maplibre_map_view.dart` fällt selbst auf
  `FlutterMapView` zurück, wenn der Style nicht baut — ohne Style lieber
  die alte Karte als gar keine. Dazu benutzt die Mini-Karte (#373)
  flutter_map ohnehin auf jeder Plattform. Gemessen am `github`-Flavor:
  130 396 207 Bytes vorher, 130 396 251 danach — **44 Bytes MEHR**, also
  Rauschen der ZIP-Kompression. Der Gewinn ist ein Zustand weniger,
  keine Größe. `test/map_engine_choice_test.dart`
  nagelt beide Seiten fest — dass Android MapLibre bekommt UND dass der
  Rückfall im Build bleibt.
  Die folgenden flutter_map-Notizen (Stellschrauben, Kamera-Wächter,
  TileProvider-Lebenszyklus) gelten für diesen Rückfall- und den
  Web-Pfad.
  **Seit 1.224.6 gibt es MapLibre auch im Browser — als VERSUCH** (#689,
  Hebel C): MapLibre GL JS statt flutter_map, nur mit `?maplibre=1` in der
  Adresse (gerätelokal gemerkt, `?maplibre=0` nimmt es zurück;
  `maplibre_web.dart`). Ab Werk ändert sich nichts. Der bedingte Import
  ist weg — den Web-Teil des Pakets hatte der Build über den
  Plugin-Registranten ohnehin. Sechs Dinge, die man wissen muss, alle am
  lokalen Prüfstand gefunden (eigene Einstiegsdatei mit nur der Fassade,
  Wasm-Build, Chromium):
  - **Die Bibliothek liegt in `web/maplibre/`, nie auf einem CDN**
    (Datenschutz, offline), und wird erst geladen, wenn die Ansicht baut
    (`mapLibreJsReadyProvider`). Lädt sie nicht ⇒ flutter_map.
  - **Klicks: Die Karte ist ein HTML-Element und nimmt sie zuerst.**
    Knöpfe darüber wären tot. Zwei Mittel: `MapOverlayGuard` (ein
    `PointerInterceptor`) um jedes feste Bedienelement — um das
    SICHTBARE Widget, nie um `Align`/`SafeArea`, sonst nimmt der Fänger
    der Karte jede Geste; und für Routen darüber (Blatt im Reiter-
    Navigator, Dialog im Wurzel-Navigator) schaltet die Ansicht nach
    jedem Bild `pointer-events` der Karte ab (`_syncCover`). Am Prüfstand
    nachgewiesen: Knopf, Dialog-OK, danach wieder Gesten.
  - **Der lange Tipp kommt als `contextmenu`** (`MapEventSecondaryClick`),
    nicht als `MapEventLongClick`.
  - **`installedMapsProvider` wirft im Browser** (`path_provider`). Der
    Style wurde damit zum Fehler, und die Ansicht fiel STILL auf
    flutter_map zurück — von außen sah der Versuch aus, als liefe er.
    Der Style-Provider fragt deshalb zuerst `offlineMapsSupportedProvider`.
  - **Bilder als `blob:`-URL** (`object_url.dart` in `writeFill`), je
    Ebene eine, die vorige wird freigegeben.
  - **Übersicht und Glyphen per URL aus den Assets** (Range-Anfragen auf
    Pages: 206, nachgemessen). Grenze: Der Service Worker legt
    Teilanfragen nicht ab — ohne Netz gibt es die Übersicht in diesem
    Weg nicht, anders als bei flutter_map (liest das Asset ganz).
  - **Was fehlt**: gespeicherte Kartenbereiche (liegen im Browser in
    IndexedDB, MapLibre bräuchte dafür ein `addProtocol`), und die Neue
    Karte geht ohne den Kachel-Server (#659) direkt per `pmtiles://` an
    den Host — die JS-Bibliothek hält Header und Verzeichnisse selbst im
    Speicher, gezählt ist das noch nicht.
  Gemessen in `docs/map-performance.md`; ob der Versuch zur Vorgabe wird,
  entscheidet der Betreiber nach Feldtest und Messung mit Konto (#689).

- **`alignment` bedeutet in den beiden Karten-Engines das GEGENTEIL**
  (#409, behoben in 1.123.0): Beide nehmen ein `Alignment` und rechnen
  daraus die Bildschirmposition — flutter_map als
  `top = punkt.y - (h - 0.5·h·(y+1))`, MapLibre als
  `top = punkt.y - 0.5·h·(y+1)`. Bei `topCenter` liegt der Punkt dort an
  der Unterkante (der Pilz steht darauf), hier an der Oberkante (der
  Marker hängt darunter). Die Fassade folgt flutter_map, deshalb spiegelt
  `mapLibreAlignment` (`* -1`) auf der MapLibre-Seite.
  **Bei `center` fällt der Unterschied weg** — und genau deshalb ist es
  von 1.43.0 bis 1.122.0 niemandem aufgefallen: So lange benutzte NUR der
  Spot-Marker etwas anderes als `center`, und ein Pilz 44 px unter seiner
  Fundstelle sieht bloß ungenau aus. Sichtbar wurde es erst an der Spitze
  der Standort-Tropfen (#403), die eine genaue Aussage macht.
  Wer eine dritte Engine einbaut: Diese Umrechnung gehört zu jeder Engine
  einzeln geprüft, sie ist keine Eigenschaft der Fassade.

- **Die Fassade kann seit 1.126.0 Linienzüge** (`MapViewPolyline`, #340
  Schritt 1). Die Farbe hängt an der LINIE, nicht am Layer — flutter_map
  kann mehrere Farben je Layer, MapLibre trägt sie am Layer und bekommt
  deshalb einen je Linie. Die Fassade folgt der freieren Form, sonst
  könnten zwei Buddy-Spuren nie verschiedene Farben haben.
  **MapLibre-Layer gehören in `layers:`, nicht in `children:`** — ein
  `PolylineLayer` ist dort ein `Layer`, kein Widget.
  Die Tourspur zeichnet ab Werk PUNKTE, nicht die Linie: Ihr Abstand
  trägt die Verweildauer, aus der `tourVisits` die Leergänge ableitet;
  eine Linie glättet das weg. Der Schalter steht im Profil.
  Und die eigene Spur ist **grün** — bis 1.125.1 stand dort `friendBlue`,
  also die Farbe für andere. Allein unterwegs fällt das nicht auf; neben
  einer Buddy-Spur sagt es das Gegenteil.

- **Karten-Stellschrauben werden nicht ohne Messung verändert**
  (`docs/map-performance.md`): Puffer, Substitutionsweite und Layer-Modus
  stehen auf Werten, die #142/#143/#119 *gemessen* haben — jede davon ist
  ein Tausch zwischen Speicher und Nachladen. Wer eine anfasst, weil ein
  Symptom danach klingt, tauscht ein sichtbares Problem gegen ein
  tödliches: Genau das schlug die Triage zu #157 vor
  (`maximumTileSubstitutionDifference` erhöhen), und genau dieser Wert war
  in #142 der Haupttreiber des Vektor-Speichers. Die Seite listet alle
  Werte samt Herkunft — und die Grenzen, die noch Paket-Defaults sind und
  nie gemessen wurden (`memoryTileDataCacheMaxSize` & Co., die seit #118
  für **zwei** gleichzeitige Layer gelten). Dort steht auch die Auflösung
  der Karten-ANRs (#151, Live-Messung 2026-08-02): Die Stellschrauben
  waren die falsche Achse, siehe Kamera-Wächter direkt hierunter.

- **Hintergrundrechnungen: ein Zeichen-Isolate und eine Grenze** (#641,
  seit 1.222.5, `lib/core/map_worker.dart`, `lib/core/bounded_compute.dart`).
  Bis 1.222.4 startete jede fensterabhängige Ebene (Wald/Ampel,
  Fundorte, Höhenlinien, Bereichs-Entwurf) je Kamera-Stillstand ein
  neues `compute`, nichts wurde abgebrochen, und jedes nahm seine Gitter
  mit — mit allen Ebenen rund 42 MB je Schwenk, kopiert AUF DEM
  HAUPTTHREAD. Auf dem Pixel XL lagen beim Schwenken im Mittel 2,4 Kerne
  unter Workern; der ANR stand in `IsolateGroup::IncreaseMutatorCount`.
  Fünf Dinge, die man wissen muss:
  - **Fensterabhängiges läuft über `runOnMapWorker`**: ein dauerhaftes
    Isolate, seriell, je Spur gewinnt der neueste Auftrag, ein
    verworfener Provider sagt seinen wartenden Auftrag ab. Gitter liegen
    dort in FÄCHERN und gehen nur bei neuem Objekt (`identical`) hinüber;
    gleicher Fachname heißt dasselbe Objekt (Wald und Höhenlinien teilen
    `elevation`). Fächer mit `#` sind eine Familie: Nennt ein Auftrag
    eines, werden die anderen freigegeben (feine Waldblöcke je Fenster).
  - **Alles andere über `boundedCompute`** (höchstens 2 zugleich).
    `test/bounded_compute_guard_test.dart` verbietet nacktes
    `compute`/`Isolate.run` in `lib/`.
  - **Auch unveränderliche Listen werden kopiert** —
    `asUnmodifiableView()` hilft nicht (nachgemessen, 200 MB ≈ 20 ms auf
    dem Mac). Teilen ohne Kopie gibt es zwischen Isolates nicht, nur
    Übergeben (`TransferableTypedData`, so kommen die PNGs zurück).
  - **Es fällt nie ganz aus**: Fehler trifft nur den Auftrag; stirbt das
    Isolate, startet das nächste und bekommt die Fächer neu; nach drei
    Toden oder ohne Isolate (Browser) rechnet der Rest über
    `boundedCompute`. `MapWorkerSuperseded` ist kein Befund
    (`worthReporting`).
  - **Im Widget-Test rechnet der Worker über `compute`, ohne Spuren**
    (`test/fakes/test_app.dart`), und die Grenze ist unter
    `FLUTTER_TEST` aus: Ein Isolate aus der FakeAsync-Zone meldet sich
    nie zurück und hielte Spur oder Platz für immer. Spur, Fächer und
    Neustart prüft `test/map_worker_test.dart` mit echten Isolates.
  - **Der Regenverlauf am Fadenkreuz hat einen eigenen Weg**
    (`legendRainCourseProvider`, `autoDispose`, Spur im Zeichen-Isolate,
    Stapel als Fach). Er war der größte Einzelposten: je Stillstand ein
    neuer Punkt, je Punkt rund 120 ausgepackte Tagesgitter (~85 MB
    Müll), 4–10 s auf dem Pixel XL, nie abgesagt. Das Spot-Blatt bleibt
    beim Einzelweg `rainCourseProvider`; gerechnet wird mit derselben
    Funktion. Flow-Tests, die die Legende prüfen, legen den Provider
    in `runAsync` an UND halten ihn (`container.listen`).
  - **Entpackt wird mit `gunzip`** (`lib/core/gunzip.dart`): nativ
    über `dart:io` (am Mac gut 4× schneller als `package:archive`, der
    Regenverlauf fiel damit auf 0,7–0,9 s), im Browser weiter
    `package:archive` — außer für die Asset-Gitter (Wald, Höhe,
    Schutzgebiete, Fundorte, Baumarten): Deren Lader rufen vor dem
    `boundedCompute` `preInflate`, das im Browser `DecompressionStream`
    auspacken lässt und das Ergebnis am gepackten Objekt bereitlegt
    (#689; live waren das gut 5 s des Start-Hängers). Neuer Asset-Lader:
    dieselbe Zeile davor, sonst packt der Browser wieder in Dart aus.
    Die Overlay-PNGs schreibt der Browser seit #689 UNGEPACKT
    (`zlib_deflate_web.dart`) — sie gehen dort nie durchs Netz. **Streng**: Beide Entpacker liefern bei einem
    abgeschnittenen Strom still den Teil bis zum Abbruch; `gunzip`
    vergleicht mit der Länge im gzip-Abspann und wirft. Nie wieder
    `GZipDecoder` direkt.
  - **Die Ruhe-PSS nach dem Ende des Isolates erst nach einem Bild
    messen.** Die Kopien der Fächer sind dann Müll, abgeräumt wird aber
    erst über `NotifyIdle` nach dem nächsten gezeichneten Bild; ein
    `send-trim-memory` räumt nicht ab. Ohne das sah es nach +50 MB aus
    (`docs/map-performance.md`).
  **Waldfläche MIT Ampel** (#662, 1.222.8): 5,7 → 2,1 s je Übersichtsbild
  auf dem Pixel XL. Höhe per Direktindex, wenn Höhen- und Waldgitter
  dasselbe Raster haben (`sharesLatticeWith`); Ampelstufe über ein
  Gedächtnis je Zeile (`AmpelRowLevels`), dessen Rechnung dieselbe
  Vorrangregel ist wie `levelForRows` (`_levelForCells`, eine Stelle);
  PNG über natives zlib (`zlibDeflate`). Lehre: Eine Fach-Tabelle je
  Regenzelle statt der Map war auf dem Gerät 1,6× langsamer, am Mac
  gleich schnell — über Tempo entscheidet nur das Gerät.
  **1.222.9: ~1,5 s, Folgebilder ~0,5 s.** Drei Dinge dazu: Zellkontext
  (`AmpelCellInputs`, Zutaten einmal je Zelle statt je Höhe); im
  Übersichtszoom (Wabe < 1 px) die Höhe in 100-m-Stufen
  (`ampelOverviewHeightStepM`, die eine Ausnahme von #279); und ein
  Byte je Wabe über Bilder hinweg (`AmpelHexMemo`, verworfen bei neuem
  Stufen-Gitter, anderer Auswahl nach Inhalt, anderem Höhengitter).
  **Keine Map mit Hunderttausenden Einträgen über ein Bild hinaus
  halten**: Sie machte das erste Bild 0,25 s langsamer
  (Speicherbereinigung), das Byte-Feld nicht. Messung in
  `docs/map-performance.md`.

- **Kamera-Wächter** (`FiniteCameraConstraint` in
  `lib/features/map/finite_camera_constraint.dart`, seit 1.38.2): verwirft
  NaN-/Infinity-Kamerazustände aus Gesten-Grenzfällen an der einzigen
  Engstelle (`MapOptions.cameraConstraint`; `null` macht die Bewegung zum
  No-op). Ohne ihn wirft die Kachelberechnung „Infinity or NaN toInt"
  (graue Flächen, 61 Feldberichte in KW30, #141) und flutter_maps
  MarkerLayer dreht seine Weltkopien-Schleife endlos, weil `Rect.overlaps`
  mit NaN per IEEE-Vergleich immer wahr ist — gemessen ~150 MB/s
  Allokationen, GC-Sturm, ANR (#151). Im Debug-Build fängt flutter_map
  nicht-endlichen Zoom selbst per Assert; im Release ist der Wächter das
  einzige Netz. Drei Tests sichern Verhalten, Engstelle und Verdrahtung
  (`test/finite_camera_constraint_test.dart`, `test/flows/map_view_test.dart`)
  — wer ihn aus den `MapOptions` entfernt, holt beide Fehler zurück.
  **Er hängt an JEDER `MapOptions`, nicht an „der Karte".** Seit 1.114.0
  gibt es eine zweite `flutter_map`-Instanz — die Mini-Karte im Fund-Blatt
  (`lib/features/map/widgets/mini_map.dart`, #373) —, und eine Kopie erbt
  keine Wächter: Dort steht er noch einmal, ebenso die
  Ein-TileProvider-Regel direkt hierunter. `test/mini_map_test.dart`
  nagelt beides fest. Wer eine dritte Karte baut, kopiert beide mit.
  Warum die Mini-Karte NICHT über die MapView-Fassade läuft: Die füllt aus
  `onCameraIdle` die globalen `mapIdle*`-Provider, an denen
  Höhenlinien-Äquidistanz, Wald-Bildausschnitt (#249) und Legende (#235)
  hängen — ein 180-dp-Ausschnitt überschriebe sie mit dem Maßstab einer
  Briefmarke, und die große Karte rechnete damit weiter. Sie ist außerdem
  IMMER flutter_map, nie MapLibre: Eine zweite native GL-Fläche in einem
  scrollenden Blatt ist teuer und im Widget-Test nicht renderbar.

- TileProvider-Lebenszyklus (`map_screen.dart`, seit 1.38.2): GENAU eine
  Instanz pro **eingehängtem** TileLayer. flutter_map schließt beim
  Aushängen den HTTP-Client des Providers — und ausgehängt wird bei jedem
  Auto-Offline-Wechsel (Empfangsverlust bei installierten Regionen). Die
  frühere screen-weite Instanz (`late final`) war danach tot: frische
  Online-Kacheln blieben bis zum Neustart grau, nur der Platten-Cache
  lieferte (#157). Pro Rebuild neu wäre das andere Extrem (HTTP-Client-Leak
  je Positions-Tick). `test/online_tile_provider_swap_test.dart` nagelt den
  Wechsel fest.

- **Regen auf der Karte** (#156, seit 1.45.0): vier Ebenen hinter einem
  eigenen FAB (`rain_layer.dart`, `widgets/rain_layer_sheet.dart`) — Radar
  jetzt und +1 h, dazu die Summen über 24 h (`dwd:SF-Produkt`) und 30 Tage
  (`dwd:RADOLAN-W4`). Bewusst ein **festes Bild** je Ebene, kein
  mitwandernder Ausschnitt: Die Produkte sind ein 1-km-Raster (20 km auf
  512 px = 20×20 Blöcke, gemessen), ein mitwanderndes Bild fügte also
  nichts hinzu — kostete aber eine Anfrage je Kartenverschiebung und
  schickte das Sichtfenster des Nutzers an den DWD. Deshalb auch
  `raster-resampling: nearest`: die Klötzchen sind die Daten.
  Die **Abdeckung ist punktweise nachgemessen**, nicht aus der Bounding
  Box gelesen — Salzburg, Innsbruck, Zürich, Bern und Chur liegen im
  Radar, Wien, Graz, Klagenfurt und Genf nicht; die Summen sind
  Deutschland allein. Das steht im Blatt, sonst sieht eine graue Fläche
  in Wien nach einem Fehler der App aus.
  `test/privacy_policy_test.dart` erzwingt seither die CLAUDE.md-Regel
  „neues Netzziel ⇒ Datenschutzerklärung im selben PR" als Wächter:
  Jeder Host, der in `lib/` auftaucht und dort nicht eingeordnet ist,
  macht CI rot.
  **Seit 1.220.0 Rückblick 7, 14 und 30 Tage, die 24 h sind weg**
  (Betreiber, 2026-10-01; Anlass: „30 Tage" war in Tirol leer, weil W4
  an der Grenze endet). Drei Dinge, die man wissen muss:
  - **7 und 14 Tage rechnet die App** (`rain_sum.dart`) aus den
    Tagesgittern, die ohnehin auf dem Gerät liegen: Radar-Stapel für
    Deutschland über `rainGridProvider` (damit laufen Bänder, Fläche,
    Datei und Legende unverändert), der Alpenraum als ZWEITE Fläche
    (`alpineRainFillProvider`, MapLibre-Quelle `regen-modell` unter
    `regen-flaeche`; seit 1.222.0 gemessen aus dem Alpenstapel, das
    Modell nur noch, wo keiner misst — siehe „Der gemessene
    Alpenstapel"). Bei 30 Tagen bleibt in Deutschland W4, nur die
    Alpenfläche kommt dazu. Die Flächen überdecken sich nicht. Eine Summe gibt
    es nur über LÜCKENLOSE Tage, eine Zelle mit fehlendem Tag bleibt
    leer — wie `sumOfLast` am Spot. Das Modell wird NICHT geglättet
    (12-km-Zellen, 3×3 wären 36 km).
  - **Die gewählte Ebene ist die Zustimmung** zum Laden der Stapel, wie
    bei W4. Deshalb gibt es `radarStackLoadedProvider` /
    `modelStackLoadedProvider` ohne Tor; `rainStackProvider` und
    `modelRainStackProvider` behalten das Tor des Spot-Dialogs und lesen
    daraus — einmal geladen für alle. Radar und „+1 h" laden nichts
    (Flow-Test zählt es).
  - **An der Kante der Radarabdeckung** (seit 1.220.1, Bildschirmfoto
    des Betreibers): Das Radar endet in Österreich an geraden Linien
    (≈ 47,2° N, ≈ 13,8–14° O — ein Rechteck in der Projektion des
    Verbunds), und die Karte zeigte dort eine scharfe Kante. Zwei
    Ursachen, zwei Mittel: **Beide Summen enden am selben Tag**
    (`rainSumEndProvider`, der ältere Stand; bei 30 Tagen der letzte
    volle Tag von W4) — der Versatz um EINEN Tag machte den größten
    Teil aus, weil am 16.09. ein kräftiger Regentag auf der einen Seite
    drin war und auf der anderen nicht (Kufstein 14 Tage: 47 gegen 14 mm
    mit Versatz, 47 gegen 42 ohne). Und **25 km Übergang**
    (`blendEdge`): je Radarzelle nach Abstand zur Abdeckungsgrenze
    zum Modell hin gemischt, NUR im Bild wie das Glätten; die Zahl am
    Spot bleibt roh. Die Fläche wartet dafür NICHT auf die Modellsumme
    (`valueOrNull`), sie rechnet neu, sobald die da ist — sonst hinge das
    W4-Bild ohne Empfang am Modell-Stapel. Folge für Tests: Die
    Modellsumme zuerst in `runAsync` lesen, sonst läuft der Neubau in
    der Test-Zone und das Warten kehrt nie zurück.
  - **Der `sf`-Bau in `rain-data.yml` bleibt vorerst**: Die stabilen
    Clients lesen `rain_sf.bin.gz` bis zur Beförderung weiter. Danach
    darf der Layer aus `tool/rain_grid.py` und dem Workflow raus. Eine
    gemerkte `last24h` wird beim Lesen zu `last30d`.

