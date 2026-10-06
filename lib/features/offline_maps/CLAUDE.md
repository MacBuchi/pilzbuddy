# PilzBuddy — Arbeitsregeln für `lib/features/offline_maps/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Warum Offline-Karten NUR Android sind — und was im Browser trotzdem
  geht** (gemessen 2026-09-03): Die Regionskarten sind Release-Anhänge des
  FREMDEN Repos `whitespring/project-nomad-maps-europe`, und die gibt ein
  Browser nicht heraus — kein `access-control-allow-origin`, weder auf der
  302 von `github.com` noch am Ziel `release-assets.githubusercontent.com`.
  Dieselbe Wand wie bei den Regendaten (#365/#366), aber der dortige
  Ausweg trägt hier nicht: Der Spiegel-Branch hielt 2 MB EIGENER Daten,
  hier sind es **36,1 GB fremder** — 38 Dateien von 44 MB (Bremen) bis
  2,01 GB (Österreich), ein typisches Bundesland 443 MB bis 1,37 GB. Jede
  der beiden Hürden allein reichte aus. Ein eigener Host mit CORS und
  Range-Unterstützung wäre technisch machbar (`PmTilesArchive.fromUri`
  kann das ganz ohne Download), ist aber eine Finanzierungsfrage —
  `docs/finanzierung-und-skalierung.md`.
  **Seit 2026-09-21 (#496) gibt es dafür einen gemessenen Weg, und er
  braucht kein Geld:** `raw.githubusercontent.com` beantwortet
  Range-Anfragen mit 206, `accept-ranges: bytes` und
  `access-control-allow-origin: *` — also genau das, was
  `PmTilesArchive.fromUri` verlangt, und es ist der Host, den
  `rain-data-mirror` seit #365/#366 ohnehin trägt. Der Preis ist eine
  harte Grenze von **100 MB je Datei** (git nimmt keinen größeren Blob
  an, also kann raw keinen ausliefern), und deshalb ist der Zuschnitt
  eine MESSUNG: `tool/map_tiles.py plan` liest nur Header und
  Verzeichnisse und sagt Bytes je Zoom, `.github/workflows/map-data.yml`
  fährt das in CI. Einzelheiten stehen in
  `docs/offline-karten-web.md`.
  **Die Messung liegt seit 2026-09-22 vor, und „braucht kein Geld" ist
  seither die halbe Wahrheit:** DACH passt als EINE Datei nur bis **z8**
  (30,5 MB). Das Ziel z14 sind **5,54 GB**, also mindestens 57 Dateien —
  und das angenommene z12 mit 73 MB sind in Wirklichkeit 1,39 GB, Faktor
  19. Damit ist die Aufteilung keine Option mehr, sondern eine
  Bedingung, solange raw der Host ist; sie kostet einen Gebietsindex in
  der App, also Komplexität genau dort, wo ohne Empfang gearbeitet wird.
  Die offene Frage ist deshalb keine Messung mehr, sondern die
  Host-Entscheidung (raw mit Aufteilung, niedrigeres Zoomziel, oder ein
  Objektspeicher ohne Größengrenze) — sie steht ausgeschrieben in
  `docs/offline-karten-web.md` und in #496.
  **Die Falle, gegen die das Werkzeug gebaut ist:** Bytes je Zoom wachsen
  nicht um 4x, sondern um das, was die Datendichte tut — in der
  Übersicht war z6 → z7 ein Faktor **6,4**, und z7 allein sind 77 % der
  Datei. Eine Hochrechnung „eine Stufe mehr, viermal so viel"
  unterschätzt genau die oberste Stufe, und die ist die ganze Rechnung.
  Geschnitten wird mit dem offiziellen `pmtiles extract`, nie mit einem
  eigenen Schreiber: Ein leicht kaputtes Archiv scheitert im Browser,
  nicht in CI.
  **Die Einschränkung liegt nie bei PMTiles.** Das Paket bietet
  `fromFile`, `fromBytes` und `fromUri`; nur `FileAt` wirft im Browser, und
  das Entpacken hat dort einen eigenen Zweig über `package:archive`.
  **Die mitgelieferte DACH-Übersicht läuft deshalb seit 1.114.2 auch im
  Web** (`_openBundledOverview` verzweigt): auf dem Telefon über die Platte
  (`FileAt` liest faul, die 8,6 MB bleiben aus dem RAM), im Browser über
  `fromBytes`. Davor lud der Browser das Asset **erfolgreich** und warf es
  eine Zeile später weg, weil `path_provider` dort fehlt — der `catch`
  schluckte es, und die PWA zeigte ohne Empfang den nackten
  Hintergrundton, obwohl die Karte längst über die Leitung gegangen war.
  Wirksam wird sie genau im Fall „Tab offen, Empfang weg"; beim NEUSTART
  ohne Netz hilft sie nicht — **die PWA startet ohne Netz gar nicht**:
  Flutters Service Worker ist die 783-Byte-Fassung, die sich selbst
  abmeldet — **war** sie: Seit 1.117.0 (#387) bringt die App ihren
  eigenen mit, und damit sind alle vier Stufen gegangen
  (Übersichtskarte #383, Spots in IndexedDB #385, Ausgangskorb #386,
  Service Worker #387).

- Offline-Karten (`lib/features/offline_maps/`, nur Android): Bundesland-
  PMTiles (Protomaps Basemap v4, ODbL) aus den GitHub-Releases von
  `whitespring/project-nomad-maps-europe`; Katalog entsteht dynamisch aus
  der Release-Asset-Liste (`<key>_<JJJJMMTT>.pmtiles`). Rendering über
  vector_map_tiles (exakt gepinnte Beta — nur Beta-Versionen können
  flutter_map 8; bewusst die 9er-Linie mit Canvas-Renderer, die 10er zieht
  den GPU-Stack samt CMake-Native-Builds nach sich). Style-Asset
  `assets/map_style/protomaps_light_de.json` ist generiert
  (npm `@protomaps/basemaps`, Flavor LIGHT, lang de) — nicht von Hand
  editieren, sondern neu generieren. **Das erzwingt jetzt ein Wächter**,
  siehe „Erzeugte Assets" weiter unten.
  **Seit 1.97.0 ENTFERNT `transform_map_style.py` nicht nur, es fügt
  auch hinzu** (`emphasize_paths`): Wanderwege, Forstwege und Steige
  bekommen eigene Ebenen, statt in `roads_other` neben Zufahrten und
  Bahnsteigen zu verschwinden (dort `#ebebeb` auf `#e2dfda`, 0,5 px bei
  z14 — die Wege waren immer da, nur unsichtbar gemacht). Der Schritt
  muss IDEMPOTENT bleiben, denn der Fixpunkt ist genau das, was
  `tool/generated_assets.py` prüft; ein `--self-test` sagt jetzt
  zusätzlich, WAS gebrochen ist.
  **Blinder Fleck, nachgemessen:** `vector_tile_renderer` 6.1.0 prüft
  `dashJson is List<num>`, `jsonDecode` liefert aber `List<dynamic>` —
  auf dem klassischen Renderer (Web und `classicMapEnabled`) fällt
  JEDES `line-dasharray` still weg, in MapLibre nicht. Die Aussage
  einer Ebene darf deshalb nie am Strich allein hängen; bei den Wegen
  tragen sie Farbe und Breite (Abstand Faktor ~1,8). Offline-Layer ist strikt optional:
  Fehler beim Laden ⇒ stiller Fallback auf Online-OSM.
  Die Karte hat drei Schichten (Issues #118/#119/#137): **unterste** die
  mitgelieferte DACH-Übersicht (`baseMapStyleProvider`, z0–7, ~9 MB im
  APK); **darüber** je nach Modus die Regionskarten oder OSM-Raster;
  **darüber** die Marker.
  Die Übersicht liegt **nicht** unter den Online-Kacheln (`showBaseMap` in
  `map_screen.dart`): Wo eine OSM-Kachel schon lag und die nächste fehlte,
  standen zwei verschiedene Kartenstile nebeneinander, und das sah kaputter
  aus als die leere Fläche, die sie verhindern sollte — Rückmeldung des
  Betreibers in #137, nachdem #118/#119 zunächst das Gegenteil verlangt
  hatten. Sie liegt drin, sobald die Offline-Karte aktiv ist ODER kein
  Empfang besteht: Dann kommt gar keine OSM-Kachel, es gibt also nichts,
  womit sie sich mischen könnte, und genau dieser Fall (Wald, kein Netz,
  noch keine Region geladen) war der Anlass für #118. Beide Richtungen
  hält `test/base_map_layer_test.dart` fest — wer eine davon aufgibt,
  bricht die andere.
  Zwei Dinge machen das erst möglich und dürfen nicht zurückgedreht
  werden: Die Übersicht ist eine **eigene** Quelle (in der gemeinsamen
  Quelle mit den Regionen galt deren `maximumZoom`, und sie wurde nach
  Kacheln gefragt, die es in ihr nie gab — genau daher kam das Grau), und
  der Detail-Layer rendert mit einem Theme **ohne** `background`-Ebene
  (`styleWithoutBackground`), weil die sonst mit deckendem `#cccccc`
  genau dort die Basis zudeckt, wo sie gebraucht wird. Über seine
  Datentiefe hinaus skaliert der Renderer selbst hoch
  (`SlippyMapTranslator`) — deshalb reicht z7 für jede Zoomstufe.
  Folge fürs Risiko: Der Beta-Vektor-Renderer läuft auch ohne installierte
  Region, sobald der Empfang wegfällt — nicht nur bei Offline-Nutzern.
  Abgesichert bleibt es durch dieselbe Regel: lädt die Übersicht nicht,
  fällt der Layer weg (dann Hintergrundton).
  Deshalb rendert die Übersicht seit 1.31.3 mit
  `VectorTileLayerMode.raster`, die Detailkarte weiter mit `vector`: Der
  Vektor-Modus rendert bei jeder Zwischen-Zoomstufe neu („can result in
  low frame rates", Paket-Doku) und bringt der Übersicht nichts, deren
  Daten bei z7 enden und ohnehin hochskaliert werden — bei der
  Detailkarte dagegen ist die Schärfe der Grund für den Modus.
  `test/base_map_layer_test.dart` nagelt beides fest (Issue #119).
  Die feinen Waldblöcke (#253) lassen sich seit #264 **am Stück
  vorladen** — ein Eintrag auf derselben Seite, kein Gebietswähler: Der
  ganze Katalog sind ~26 MB (DACH) gegen mehrere hundert je
  Regionskarte, eine Bbox-Wahl wäre mehr Oberfläche und mehr Erklärung
  als die Daten wert sind. Der Knopf IST zugleich die Zustimmung zum
  Nachladen (`forestFineEnabled`), wie der Schalter im Wald-Blatt. Die
  Kachel zählt über die **Dateigröße**, nicht über die Prüfsumme (die
  volle Prüfung wären 26 MB SHA-256 je Bildaufbau) — die Prüfsumme
  bleibt dort, wo die Daten benutzt werden.
  Der Download läuft im Main-Isolate und braucht deshalb einen
  Foreground-Service (`flutter_foreground_task`, Typ `dataSync`) —
  ohne den friert Android den Prozess beim App-Wechsel ein und der
  Download steht still. Seit #264 teilen sich Karten-Download und
  Wald-Vorlauf **einen** Service über den
  `DownloadKeepAliveCoordinator`: Vorher beendete das `stop()` des einen
  ihn dem anderen mitten im Lauf — also genau der eingefrorene Prozess,
  gegen den er da ist. Wer einen dritten Download baut, meldet ihn dort
  unter eigenem Schlüssel an. Eingebunden über `downloadKeepAliveProvider`
  mit bedingtem Import (`download_keep_alive_stub.dart` für Web, sonst
  `download_keep_alive_service.dart`), damit der Web-Build das
  Android-Paket nie sieht; Tests überschreiben den Provider.

- **Der Auto-Nachlauf der Karten misst NICHT „WLAN", sondern „kostet das
  etwas?"** (#332, seit 1.100.0): Ein Schalter auf der Offline-Karten-
  Seite (`mapAutoUpdateEnabled`, ab Werk AUS) lädt veraltete Regionen von
  selbst nach. Alles darunter war schon gebaut — Versionsvergleich,
  Banner und vor allem der Failsafe (`.part`, SHA-256, dann atomar
  umbenennen); dazugekommen ist nur der Auslöser.
  Drei Dinge, die man wissen muss:
  - **`connectivity_plus` kennt nur den Transportweg, und der beantwortet
    die Frage nicht.** Ein Handy-Hotspot ist für die Bibliothek WLAN und
    kostet trotzdem fremdes Datenvolumen — genau die Verbindung, die man
    unterwegs benutzt. Deshalb der dritte MethodChannel
    (`de.mcbuchi.pilzbuddy/network` → `isActiveNetworkMetered`, Konstante
    `networkMeteringChannel`). **Keine neue Berechtigung:**
    `ACCESS_NETWORK_STATE` bringt `connectivity_plus` ohnehin mit, es
    steht nur ein zweiter Zweck in `docs/play-console.md`. Antwortet der
    Kanal nicht, gilt „kostenpflichtig" — die harmlose Fehlerrichtung ist
    „lädt nicht", nicht „lädt auf fremde Rechnung".
  - **Ein selbst gestarteter Download muss auch von selbst anhalten.**
    `MapDownloadsNotifier` ist mit Absicht geduldig und setzt bei JEDER
    zurückkehrenden Verbindung fort, auch über Mobilfunk. Wer angetippt
    hat, will das; wer nichts angetippt hat, lädt sonst 1,7 GB aus seinem
    Tarif, weil er das Haus verlassen hat. `planAutoMapUpdate` hat
    deshalb zwei Ausgänge — starten UND anhalten —, und der Notifier
    merkt sich, welche Regionen ER gestartet hat. Von Hand gestartete
    rührt er nicht an.
  - **Der Auslöser hängt am Karten-Screen** (`ref.listen` auf
    `mapAutoUpdateInputsProvider`, plus ein Anstoß aus `initState`:
    `WidgetRef.listen` kennt kein `fireImmediately`). Die Zutaten stehen
    als Record mit zusammengefügten Regionsschlüsseln darin, nicht als
    Liste — zwei inhaltlich gleiche Listen sind für `==` verschieden, und
    der Nachlauf liefe bei jedem Neuaufbau erneut an.
  Eine in dieser Sitzung endgültig gescheiterte Region ruht bis zum
  nächsten Start; ein ANGEHALTENER Download zählt nicht als Fehlversuch.
  Alles davon steht in `test/flows/offline_update_flow_test.dart`.

