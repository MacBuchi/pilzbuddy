# PilzBuddy — Arbeitsregeln für `lib/features/offline_areas/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Gespeicherte Kartenbereiche** (#630 Stufe 2, seit 1.215.0,
  `lib/features/offline_areas/`, übernommen aus TrailBuddy ohne dessen
  Orte): Ein Bereich ist EIN PMTiles-Archiv (Zoom 8 bis zum Zoom des
  Hosts), geschrieben auf dem Gerät von `pmtiles_writer.dart` aus
  Kacheln, die per Range aus dem Archiv der Neuen Karte kommen (Bytes
  unverändert, dieselbe Kompression). Der eigene Schreiber ist hier
  erlaubt, weil auf dem Gerät kein `pmtiles extract` läuft; jedes Archiv
  wird sofort mit dem Leser beider Engines zurückgelesen (Zählung plus
  Stichprobe), sonst kommt es nie in den Index. Auf Android Dateien unter
  `offline_maps/areas/` (in beiden Backup-Ausschlüssen), im Browser
  IndexedDB (`kAreaIndexStore`/`kAreaArchiveStore`, `kBrowserDbVersion`
  3). Fünf Dinge, die man wissen muss:
  - **Auf ALLEN Plattformen**, anders als die Regionskarten — das war
    der Anlass von #630. Die Regionskarten bleiben bis Stufe 4 daneben.
  - **Gespeichert wird nur mit der Neuen Karte** (Schalter, s. o.): Die
    Kacheln kommen vom selben Host, und solange der Vorschau ist, gehört
    das Speichern dazu. Liegende Bereiche zeichnet die Karte immer, und
    der Profileintrag bleibt, solange einer liegt — Löschen muss gehen.
  - **Bereiche liegen ZUOBERST, immer** — über OSM, der Neuen Karte und
    den Regionen, mit und ohne Empfang (TrailBuddy #82: im Funkloch mit
    einem Balken kommen Online-Kacheln nie, eine Regel „nur ohne
    Empfang" greift dort nicht). In MapLibre heißt das `topSources` im
    Composer, NACH dem Raster; sonst deckte OSM sie zu. Über OSM stehen
    damit zwei Kartenstile nebeneinander (#137) — bewusst hingenommen,
    denn wer Bereiche speichert, hat die Neue Karte ohnehin an.
  - **Zwei Formen**: der Kartenausschnitt (`RectShape`, aus
    `mapIdleBoundsProvider`) und die Umgebung der eigenen Spots
    (`AreaShape.aroundPoints`, 2 km je Spot, Kachelmenge statt Rechteck —
    verstreute Spots wären sonst vor allem Land dazwischen). Obergrenze
    40 000 Kacheln je Bereich.
  - **Größe vorher ist eine Messung**: Das Verzeichnis des Archivs nennt
    die Bytes jeder Kachel; der Dialog zeigt die Summe, bevor ein Byte
    fließt. Beim ersten gespeicherten Bereich bittet die App einmal um
    `navigator.storage.persist()` (Muster Ausgangskorb).
  **Zeichnen und Radieren** (Stufe 2b, seit 1.216.0,
  `area_draw.dart`, `area_trim.dart`, `area_edit_fill.dart`,
  `area_tool_rail.dart`): „Auf der Karte bearbeiten" öffnet eine Leiste
  anstelle der Knopfspalte. Der Entwurf bearbeitet den GANZEN Bestand
  in Kacheln bei Zoom 13 — dazu nur, was nicht liegt, weg nur, was
  liegt; gespeichert wird erst das Herausschreiben (ohne Netz, derselbe
  Schreiber, gegengelesen VOR dem Ersetzen), dann der Download des
  Neuen. Vier Dinge, die man wissen muss:
  - **Maske und Entwurf sind EIN Bild**, nicht Polygone wie in
    TrailBuddy: Die Fassade kann keine Polygone, und der Weg von Wald-
    und Fundorte-Fläche (Isolate, `overlayPng`, `writeFill`) trägt
    beide Engines schon. In MapLibre gehört es ZUOBERST — jede andere
    Fläche wird angehängt (beim Verschieben planen Wald und Fundorte ihr
    Fenster neu), deshalb legt `_raiseAreaEdit` es danach wieder
    obenauf. Die Revision des Inhalts steht im Dateinamen, sonst tauscht
    MapLibre das Bild nicht.
  - **Die Zeichenfläche liegt nur, solange ein Werkzeug scharf ist**,
    und fängt dann jede Berührung ab. Nur deshalb stimmt die Umrechnung
    `unprojectFromBounds` aus `mapIdleBoundsProvider` und der Größe der
    Fläche: Die Karte steht still. Nach dem Strich ist das Werkzeug weg.
  - **Die Zurück-Taste schließt die Leiste** (Muster der
    Hinweis-Maschine, `ChildBackButtonDispatcher` mit Vorrang) — die
    Karte ist die Wurzel ihres Reiters, Zurück hieße sonst „App raus".
    Mit Entwurf fragt sie nach.
  - **Dazunehmen braucht die Neue Karte, Wegnehmen nicht** — dieselbe
    Linie wie beim Speichern: Liegendes muss man immer loswerden können.
  **Der Weg liegt auf der Karte** (seit 1.217.0, Feldrückmeldung: „man
  arbeitet in der Karte, erreicht es aber nur über das Profil" und „nicht
  zu verschachtelt"): ein eigener Knopf in der Leiste rechts
  (`MapCoach.areas`, nur mit Neuer Karte oder liegenden Bereichen) öffnet
  die Werkzeugleiste direkt, die ihrerseits zur Liste führt. Unter
  „Ebenen" steht zusätzlich die Zeile
  „Kartenbereiche" öffnet die Seite, ihr Stift die Leiste
  (`MapLayerDetail.areas`/`areaTools`). Sie steht IMMER da, auch ohne
  Neue Karte — die Seite sagt dann, warum nichts geht.
  **Regionen und Bereiche laufen parallel, abschaltbar** (seit 1.219.0,
  Betreiber: „erstmal parallel laufen, dass man es in der App umstellen
  kann" — Stufe 4 wird erst im Feld erprobt, nicht gelöscht):
  `regionMapsEnabledProvider` (ab Werk AN, Schalter
  `RegionMapsSwitch` auf beiden Seiten). Aus heißt, die Regionen zählen
  wie keine — `offlineMapStyleProvider`, der MapLibre-Style,
  `outdatedMapsProvider` und die Zeile im Ebenen-Blatt fragen denselben
  Provider; die Dateien bleiben liegen. Der Umkreis um die Spots ist
  wählbar (1–10 km, `areaSpotRadiusProvider`, gemerkt).
  **Veraltete Bereiche lädt die App nach** (seit 1.217.0,
  `area_auto_update.dart`): Veraltet heißt `build` älter als
  `sourceBuild` des Manifests der Online-Karte (kein eigener Abruf). Von
  selbst nur im freien Netz und im Vordergrund, mit denselben zwei
  Ausgängen wie #332 — starten UND den eigenen Download anhalten, wenn
  das freie Netz geht; eigener Schalter `areaAutoUpdateEnabled`, ab Werk
  AN (ein Bereich ist klein, der Host baut monatlich). Im Browser gibt es
  keine Kostenauskunft, dort nur „Aktualisieren" auf der Seite.

