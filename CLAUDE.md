# PilzBuddy — Arbeitsregeln

Flutter-App (Android + Web): Pilz-Spots auf OpenStreetMap-Karte, Supabase-Backend
(Auth + PostgreSQL, Freigabe-Regeln komplett über RLS in `supabase/schema.sql`),
Riverpod ohne Codegen, go_router, deutsche UI-Strings direkt im Code.

Projektübergreifende Guidelines (Architektur, State, Testing, CI, Signing,
In-App-Update/-Feedback) liegen im DocuHub des Betreibers; der lokale
Pfad steht in `CLAUDE.local.md` (nicht eingecheckt). Diese Datei
beschreibt nur, was für PilzBuddy davon abweicht oder zusätzlich gilt.

**Nichts Privates in dieses Repo — es ist öffentlich** (Betreiber,
2026-09-25: „dafür haben wir den DocuHub"). Keine absoluten Pfade auf
dem Rechner des Betreibers (`/Users/…`, `/Volumes/…`), kein
Schlüsselordner, keine privaten Mailadressen, keine
Namen von Sync-Ordnern, keine Hosts oder IPs der eigenen Infrastruktur;
Testdaten mit `example.org`. Das gehört in den DocuHub, hier steht ein
Verweis darauf. Ausnahme ist nur, was öffentlich sein MUSS (der
Verantwortliche in Datenschutzerklärung und Impressum).
`test/private_info_test.dart` prüft jede eingecheckte Datei auf absolute
Pfade, den Schlüsselordner, den Sync-Ordner und private Mail-Domains.
Anlass war `AGENTS.md`: eine zweite Kopie dieser Regeln, seit #485
veraltet, die beides weiter nannte — entfernt. Eine Kopie von Regeln
veraltet still, und mit ihr, was nicht mehr darin stehen soll.

**`AGENTS.md` ist seither ein Symlink auf diese Datei** (Codex liest
`AGENTS.md`, Claude `CLAUDE.md`; eine Quelle, nichts kann veralten). CI
prüft das im Job „Analyze & Test" — der Claude-Import der Codex-App legt
sie sonst als umgeschriebene Kopie an („Claude" → „Codex", auch in
Pfaden). Was für Claude in `CLAUDE.local.md` steht, gehört für Codex in
die persönliche `~/.codex/AGENTS.md`, nie ins Repo. `.codex/config.toml`
trägt nur die MCP-Server (iNaturalist) und ist vom Version Guard
ausgenommen.

## Workflow

- Kein direkter Push auf `main` (Branch ist geschützt): Feature-Branch
  (`feat/<thema>` / `fix/<thema>`) → PR → CI grün → Squash-Merge.
- Commit-/PR-Titel: Conventional Commits (`feat:`, `fix:`, `chore:`, `ci:`, …).
- Sprache: Auf GitHub wird Englisch gesprochen — Commit-Messages, PR-Titel und
  -Beschreibungen, Issues und Kommentare auf Englisch. Deutsch bleibt für
  UI-Strings, Nutzer-Doku (README) und die Kommunikation mit dem Betreiber.
- **Zwei Release-Kanäle, ein Branch** (#262, seit 1.77.0): Ein
  Versions-Bump in `pubspec.yaml` auf `main` (beide Teile erhöhen, z. B.
  `1.0.1+2`) taggt weiterhin `v<version>` und baut die signierte APK —
  aber als **Prerelease**. Für die Nutzer ist der Stand damit unsichtbar:
  `update_check.dart` fragt `/releases/latest`, und GitHub liefert dort
  grundsätzlich keine Prereleases. Kein Bump = kein Build.
  **Freigegeben wird von Hand:** `promote.yml` (workflow_dispatch, ohne
  Eingabe = jüngstes Prerelease) nimmt die Markierung weg, setzt „latest",
  sammelt die Release-Notizen aus ALLEN Changelog-Blöcken seit dem letzten
  stabilen Stand (`tool/release_notes.py` — unser Changelog ist nach
  Themen gegliedert, ein Zeilenschnitt wie im Nachbarrepo reicht dafür
  nicht) und deployt **erst dann** Web auf GitHub Pages, gebaut aus dem
  beförderten Tag (https://macbuchi.github.io/pilzbuddy/). Das Web hat
  eine Adresse: Deployte jeder Merge, gälte die Trennung nur für Android.
  Rhythmus: **höchstens wöchentlich, gern seltener** (Betreiber,
  2026-08-17 — vorher „nach Änderungsgrad"; fünf Update-Hinweise in
  einer Woche sind für normale Nutzer zu viel).
  Das AAB entsteht weiter je Bump als Workflow-Artefakt `android-aab`,
  seit 1.87.1 aus dem `play`-Flavor und damit einreichbar.
  Drei Folgen, die man wissen muss:
  - **`minimum_supported_version` darf nie über den STABILEN Stand
    steigen.** Migrationen spielen beim Merge ein, der Client kommt erst
    mit der Beförderung — der Abstand ist jetzt Wochen statt Minuten.
    `tool/schema_check.sh` misst deshalb gegen das letzte stabile Release
    (Rückfall auf `pubspec.yaml`, wenn die GitHub-API schweigt).
  - **Brechende Schema-Änderungen brauchen erweitern → ausliefern →
    entfernen** (DocuHub `datenhaltung.md`), sonst erzwingen sie sofort
    eine Beförderung und die Bündelung ist hinfällig.
  - Der In-App-Weg führt **standardmäßig** nur zu stabilen Ständen. Seit
    1.81.0 (#269) gibt es dafür einen Schalter im Profil unter „Über
    PilzBuddy": „Vorabversionen erhalten", Vorgabe AUS, gerätelokal. Er
    ändert genau EINS — die Adresse, die `update_check.dart` abfragt
    (`/releases` statt `/releases/latest`, davon der erste nicht-Entwurf).
    Versionsvergleich, APK-Suche und Dialog sind für beide Kanäle
    dieselben; zwei Fassungen wären zwei Antworten auf „ist das ein
    Update". Der Riegel „nur wo der Update-Weg läuft" steht im Provider
    (`updateChecksApply`), nicht nur in der Oberfläche — sonst ließe er
    sich im Play-Build umlegen, ohne dass je etwas passiert.
  Die Riegel sind je ein Wort YAML — `test/release_workflow_test.dart`
  wacht über beide, über den fehlenden Pages-Deploy in `release.yml` und
  über die Aussperr-Grenze.
- Nutzer-Changelog (`CHANGELOG.md`, Issue #113): Jede Version, die etwas
  Sichtbares ändert, bekommt hier einen Eintrag — in Alltagssprache und nach
  Themen gegliedert statt nach Versionsnummern (68 Releases in neun Tagen
  wären als Liste wertlos, deshalb nennt jeder Block seine Versionen in einer
  Metazeile). Die Datei wird als Asset ausgeliefert und im Profil unter
  „Was ist neu" angezeigt (`lib/features/changelog/`), ist also ohne Empfang
  lesbar. Drei Folgen daraus:
  - `test/changelog_test.dart` verlangt, dass die Version aus `pubspec.yaml`
    in der Datei vorkommt — als neuer Block oder indem der oberste Block
    seine Versionszeile erweitert. Ein Bump ohne Changelog-Eintrag macht
    `flutter test` rot; das ist der Mechanismus, der die Datei am Leben hält.
  - Der Version Guard nimmt `*.md` aus, `CHANGELOG.md` aber ausdrücklich
    nicht — sie liegt im Binary, eine Änderung an ihr braucht denselben
    Versions-Bump wie Code.
  - Erlaubte Auszeichnung: `##`-Überschrift, kursive Metazeile mit Datum und
    Versionen, Absätze, `-`-Aufzählungen, `**fett**`. Mehr rendert
    `changelog_parser.dart` nicht (bewusst kein Markdown-Paket für eine
    Datei, die wir selbst schreiben). Markdown-Links gehören nicht hinein —
    nackte URL schreiben, ein Test wacht darüber.
- Version Guard in CI: Code-Änderung ohne Versions-Bump blockiert den Merge
  (Pflicht-Check schlägt fehl); nur `*.md` (außer `CHANGELOG.md`, siehe
  oben), `.github/`, `store/`, `tool/`, `.codex/`, `.claude/`
  und `supabase/` sind ausgenommen — nichts davon landet je in einem Binary
  (Store-Grafiken stecken in keiner Asset-Liste, siehe `store/README.md`;
  die Skripte in `tool/` laufen nur in CI; SQL und Stack-Config aus
  `supabase/` laufen in der Datenbank — ein Patch, dessen Schema die App
  nutzt, ändert `lib/` mit und bumpt darüber).
- Gemergte Branches löscht GitHub automatisch (delete_branch_on_merge).

## Externe Datenquellen — was lokal läuft und was nicht

Die Frage „gibt es das lokal?" soll hier in zehn Sekunden beantwortet
sein. Sie kam am 2026-09-16 auf und kostete zehn Suchen, weil die
Antwort über drei Orte verteilt lag — einer davon in einem fremden
Ordner (`~/pilzbuddy-ampel2000/COWORK.md`).

| Quelle | Wofür | Lokal? |
|---|---|---|
| **Open-Meteo** | historisches Wetter für die Ampel-Validierung | **JA, eigene Instanz** — `docs/pilzampel-openmeteo-lokal.md` |
| **GBIF** | Saisonkurven, Fund-Stichproben, Artenfenster | **JA, als Download** — `tool/gbif_download.py`, seit 2026-09-16 |
| **DWD** (WCS/GeoServer) | Regengitter | NEIN — `tool/rain_grid.py`, läuft nur in CI |
| **GeoSphere, MeteoSchweiz, DPC** | gemessener Regen Alpenraum, an den Grenzen gemischt (#646) | NEIN — `tool/alps_rain.py`, läuft nur in CI; Begründung `docs/regendaten-alpenraum.md` |
| **Copernicus / DLR** | Wald-, Höhen-, Baumartengitter | NEIN — eigene Workflows, `workflow_dispatch` |
| **Supabase** | Datenbank, Auth | **JA für Tests** — `supabase start`, siehe Schema Dry Run |

**Open-Meteo und GBIF werden verwechselt**, und das ist naheliegend:
Beides sind externe Datenquellen der Ampel, und genau eine davon hat
seit #460/#461 eine eigene Instanz. Es ist **Open-Meteo** —
`ghcr.io/open-meteo/open-meteo`, `127.0.0.1:8080`, per docker compose.
Der Anlass war das Cloud-Kontingent, das eine registrierte Messung auf
Tage streckte; der eigentliche Gewinn ist, dass die Instanz den
Datensatz pinnt.

**GBIF hat keine Instanz, sondern einen Bestand.** Eine eigene Instanz
wäre auch gar nicht zu betreiben — GBIF ist ein Index über 2,5 Mrd
Datensätze. Stattdessen liegt der Pilzbestand für DACH und den
Alpenraum **als Ganzes** lokal:

    ~/pilzbuddy-gbif/dach_fungi.sqlite    3 924 247 Zeilen, 923 MB
    ~/pilzbuddy-gbif/CITATION.txt         der DOI dazu

Gebaut von `tool/gbif_download.py` (`request` → `status` → `fetch` →
`build`), Stand vom 2026-09-25 ist `10.15468/dl.7d8pd8` (davor
`10.15468/dl.dwbsuf` vom 2026-09-16, nur DACH). **Seit #612 mehr als
DACH:** Liechtenstein ganz (2 199 Zeilen) und Italien NUR in der
Alpenbox 6,6–13,9° O, 45,6–47,2° N (138 962 Zeilen, Südtirol bis
Aostatal; `ALPINE_ITALY` im Werkzeug). Ganz Italien wären 471 000
Meldungen aus dem Mittelmeerklima. Zwei Folgen: `countryCode = 'IT'` im
Bestand HEISST Alpenraum, und der Hold-out-Bericht sagt das
(`holdout_region_notes`); die Saisonkurven bleiben DACH
(`gbif_local.WHERE_CURVES`, Parität zum Netzweg), die Fundorte-Ebene
nimmt dagegen alles. Eine
Regionsabfrage dauert damit **6 ms** statt Minuten; ganz DACH auf einmal
auszuwerten (2 Mio Sichtungen) dauert Sekunden und war über die API
schlicht nicht machbar.

Vier Dinge, die man wissen muss:

- **Der DOI ist der eigentliche Gewinn, nicht das Tempo.** Er nagelt den
  Stand fest — und das ist nötig, weil **GBIF täglich wächst**: Zwei
  Läufe derselben Art lieferten im Abstand von zwei Stunden 2259 gegen
  2253 Meldungen und damit eine andere Stichprobe. Genau dafür gibt es
  `fetch_finds(cache_dir=…)` in `tool/ampel_validate.py`; der DOI leistet
  dasselbe, nur zitierfähig, und erledigt zugleich die
  CC-BY-Namensnennung über alle Quell-Datasets.
- **Der Download ist bewusst UNGEFILTERT** — alle Pilze mit Koordinate in
  DACH, Liechtenstein und der italienischen Alpenbox, ohne Lizenz-,
  Genauigkeits- oder `basisOfRecord`-Schranke. Die
  stehen als Spalten bereit und werden lokal gesetzt. Enger zu ziehen
  spart einmalig Platz und kostet bei der nächsten Frage einen neuen
  Download; der Effort-Nenner (#467) braucht ohnehin auch die
  Bodenproben, die kein Sammler je sieht.
- **Tiefes Blättern über die Such-API scheitert nicht, es kriecht.** Ab
  `offset` ~10 000 braucht dieselbe Seite **341 s statt 0,3 s** und
  liefert danach ihre 300 Treffer — von außen ununterscheidbar von einem
  Hänger, und mit gesetztem Timeout ein Abbruch ohne erkennbaren Grund.
  Wer doch über die API geht, kachelt (`tool/gbif_effort.py`).
- **Zugangsdaten liegen im Schlüsselordner des Betreibers**; wo genau, steht im DocuHub `guidelines/signing-und-secrets.md`
  und bewusst nicht hier — dieses Repo ist öffentlich. Die Werkzeuge
  finden sie über `KEYS_DIR` bzw. `GBIF_ACCOUNT` aus der Umgebung. Ein dort
  abgelegtes Passwort kann **Markdown-Escapes** tragen, die nicht dazu
  gehören (`\*` statt `*`) — daran ist die erste Anmeldung gescheitert,
  und die Fehlersuche war teuer, weil GBIF einen erfundenen Benutzernamen
  wortgleich beantwortet wie einen echten mit falschem Passwort (kein
  Benutzernamen-Orakel). Der Loader dreht die Escapes zurück.

Daraus folgt die Arbeitsregel: **Wer Hunderte Einzelabfragen
hintereinander braucht, stellt die falsche Frage.** Ein Download trägt
Zähler und Nenner zugleich; die Auswertung passiert danach lokal.

## Technik-Notizen — Index

Die Technik-Notizen liegen seit dem 2026-10-06 NEBEN DEM CODE, je Ordner
eine `CLAUDE.md` (vorher 211 KB in dieser Datei, in jeder Sitzung ganz
geladen). Claude Code lädt eine Teildatei von selbst, sobald eine Datei in
ihrem Ordner gelesen wird. **Wer an einem Thema arbeitet, dessen Ordner er
noch nicht geöffnet hat — und Codex immer —, liest die Teildatei vorher.**
`tool/agent_docs.py` (CI, „Analyze & Test“) hält Index und Dateien zusammen und diese Datei
unter ihrer Größengrenze. Neues Wissen gehört in die Teildatei des Ordners,
in dem der Code liegt — nicht wieder hierher.

| Datei | Themen |
|---|---|
| `android/CLAUDE.md` | Signing · Benachrichtigungskanal (#277) · Statusleisten-Symbol (#331) · Play Store: offene Blocker, Paketname, App Signing |
| `web/CLAUDE.md` | Pages-Build (base-href, 404.html) · Web-Push über eigenen Worker · Eigener Service Worker (#387) · Roboto von fonts.gstatic.com |
| `supabase/CLAUDE.md` | Datenbank-Änderungen, Schema Check, Schema Dry Run · Edge Functions deployen (#277) · Patch-Buchführung: eingespielte Patches nie anfassen · Breaking-Migration, minimum_supported_version (#80) · Neue DB-Funktionen: Sichtbarkeit, Grants, Advisor · Auth-Härtung im Dashboard · Leaked Password Protection (nicht vorhanden) · Free-Plan: Pausieren, Grenzen |
| `lib/core/CLAUDE.md` | SnackBar im Vordergrund (PushListener) · Supabase-Keys öffentlich · Update-Hinweis, APK-Installer, Flavors (#161) · Fehlerberichte, ErrorSink |
| `.github/CLAUDE.md` | Web-Vorschau (#388) · Flutter-Version in CI (sieben Stellen) · Issue-Triage · Feedback-Bot, Fehlerbericht-Digest · Backup |
| `lib/features/auth/CLAUDE.md` | Passwort ändern (#127) · Passwort-Reset, Mail-Vorlagen, E-Mail ändern, Bestätigung |
| `lib/features/offline_maps/CLAUDE.md` | Warum Offline-Karten nur Android (#496) · Offline-Karten, Kartenschichten (#118/#119/#137) · Auto-Nachlauf der Karten (#332) |
| `lib/features/map/CLAUDE.md` | Neue Karte vom eigenen Kartenhost (#630, #659) · GBIF-Fundorte als Kartenebene (#467) · Schutzgebiete (#580) · Kontextmenü beim langen Tipp (#483) · Höhenlinien · Karten-Engine MapLibre/flutter_map (#433) · alignment in beiden Engines (#409) · Linienzüge in der Fassade · Karten-Stellschrauben nur mit Messung · Zeichen-Isolate, boundedCompute, gunzip (#641) · Kamera-Wächter (#141, #151) · TileProvider-Lebenszyklus (#157) · Regen auf der Karte (#156) |
| `lib/features/offline_areas/CLAUDE.md` | Gespeicherte Kartenbereiche (#630) |
| `lib/data/CLAUDE.md` | Zwischenspeicher/Ausgangskorb in IndexedDB (#385, #386) · Beendigungsgründe, Tombstones (#147, #394) · Ausgangskorb (#267) |
| `lib/features/tour/CLAUDE.md` | Pilztour und Leergänge (#338, #342, #340) |
| `lib/features/ampel/CLAUDE.md` | Ampel-Banner, Klassen, Saison-Tor, Schwellen · Höhengitter & Temperaturkorrektur (#279) |
| `lib/features/coach/CLAUDE.md` | Erklär-Tour, Kontexthilfe, Reiter-Touren (#350, #596) |
| `lib/features/highlights/CLAUDE.md` | Neuheiten und „Entdecken“ (#596) |
| `lib/features/species/CLAUDE.md` | Reiter „Pilze“, Artseite, Einstufung, Partner, Bilder |
| `lib/features/spots/CLAUDE.md` | Reiter „Spots“ (#509) · Vormerkung (#499) · Fundfotos, Kudos, Feedback-Bilder (#532, #525) · Fundstellen weit vom Spot (#475) · Spot an Navi-App übergeben (#367) |
| `lib/features/inat/CLAUDE.md` | Melden an iNaturalist/GBIF (#553) |
| `lib/features/friends/CLAUDE.md` | Nachrichten zwischen Buddys (#564) · Aliase für Buddys (#567) |
| `test/CLAUDE.md` | Gegenprobe und ihre drei Lügen · Widget-Test-Fallen (Bildschirmgröße, echte Hülle, pumpApp-Neustart, Plattform-Kanäle, TabBarView) · analysis_options.yaml |
| `tool/CLAUDE.md` | Erzeugte Assets (#226) · Baumarten-Gitter DLR/ForestPaths/WSL (#227, #624) · Release-Anhänge nicht im Browser, rain-data-mirror (#365) · Modellgitter Alpenraum (#612) · Gemessener Alpenstapel (#646) · Regen-Wertegitter (DWD WCS) |

## Code-Konventionen

- Business-Logik in Repositories/Services, nicht in Providern oder Widgets.
- Mutations-Muster: Repo-Call, dann **`await reloadAfterWrite('…')`**
  (`lib/core/read_after_write.dart`, Mixin auf `AsyncNotifier`) —
  Read-after-write statt optimistischem Update.
  **Nicht mehr `ref.invalidateSelf(); await future;` von Hand** (#371):
  So geschrieben fällt ein Fehler des ABRUFS in denselben `catch` wie
  einer des SCHREIBENS. Der Nutzer las dann „Internet verfügbar?" über
  einen Spot, der längst auf dem Server lag — und trug ihn noch einmal
  ein. Mit frischer `client_id` ist das ein echter Doppel-Spot; Patch 016
  sichert den Wiederholversuch DESSELBEN Auftrags, nicht die Handeingabe.
  Zwei Dinge, die man wissen muss:
  - **Der Helfer schluckt NUR den Abruf.** Ein Schreibfehler wirft
    weiter — sonst würde ein kaputtes Deployment zur stillen
    Erfolgsmeldung, dieselbe Grenze wie bei `looksOffline` und dem
    Zwischenspeicher (#80). `test/flows/read_after_write_flow_test.dart`
    prüft beide Richtungen.
  - **Sein Rückgabewert ist die Auskunft an die Oberfläche**: `false`
    heißt „geschrieben, aber die Liste ist noch alt". Wer eine
    Erfolgsmeldung zeigt, hängt `staleAfterWriteHint` an — sonst steht
    „gespeichert" über einer Liste, in der nichts Neues erscheint, und
    das sieht wieder nach Misserfolg aus. `addSpot`/`addFinds` geben ihn
    deshalb durch.
- **Fund ≠ Eintrag** (seit 1.58.0, #211): `finds` trägt neben Funden auch
  Leergänge (`blank`, „Nichts gefunden"). Über `Spot` gibt es deshalb zwei
  Familien von Zugängen, und die Wahl entscheidet über die Richtigkeit:
  `findsSorted`/`ownFinds`/`lastFind`/`lastOwnFind` sind **leergangsfrei**
  (Statistik, Marker-Icon, Art-Filter, Art-Vorschläge, Buddy-Banner),
  `entriesSorted`/`ownEntries` enthalten **alles** (Fundliste im Blatt,
  GPX-Export). Direkt auf `spot.finds` zuzugreifen ist fast immer der
  Fehler — die Rohliste gehört dem Cache. Ein Leergang trägt weder Art
  noch Anzahl; der Constraint `finds_blank_leer` hält das fest, der Fake
  spiegelt ihn.
- `mounted`/`context.mounted` nach jedem `await` prüfen.
- `catch (_) {}` nur mit Begründungskommentar und nie im Kernpfad. Optionale
  Features (Offline-Karte, Update-Check, GPS) dürfen still degradieren.
- Die eigene Nutzer-id kommt aus `_client.requireUid` (`lib/data/session.dart`),
  nie aus `auth.currentUser!.id`. Das `!` warf beim Abmelden und beim
  Token-Ablauf ein nichtssagendes „Null check operator used on a null value";
  `requireUid` wirft stattdessen `NotSignedInException`, und Hintergrund-
  schleifen (Standort-Poll, Positions-Tick) hören daraufhin still auf.
  Merksatz aus Issue #124: **Nicht jeder gefangene Fehler gehört in
  `error_reports`.** Ein normaler Vorgang, der dort landet, ersäuft im
  Wochendigest die echten Funde — 37 Berichte in einer Woche für ein
  Abmelden, 193 für abgebrochene Kachel-Aufträge (#136). Die globalen
  Handler in `main()` sieben deshalb über `worthReporting`
  (`lib/core/errors.dart`) aus: `CancellationException` aus `executor_lib`
  (der Kartenrenderer bricht Kacheln ab, sobald sie aus dem Bild wandern)
  und `NotSignedInException`. `executor_lib` ist genau dafür eine direkte
  Abhängigkeit, damit die Prüfung typisiert bleibt. Ein `logError` mit
  eigenem Kontext meldet weiterhin alles — dort hat sich der Aufrufer
  bewusst für das Melden entschieden.
- Bekannte Schuld: Farben sind als Hex-Literale über viele Dateien verstreut.
  Neuen Code nicht so schreiben — die Marken-Töne stehen in
  `lib/core/app_colors.dart` (Issue #53 hat die Datei angelegt, der Umbau ist
  aber nicht überall durch); bei Berührung schrittweise umstellen. Abstände
  haben noch gar keine Konstanten.
- Formular-Bausteine liegen in `lib/core/widgets/`: `PasswordField` (mit
  Auge-Toggle, `minPasswordLength`), `FormNotice` (Erfolg/Fehler
  unterscheidbar) und `ResendButton` (startet gesperrt und zählt 60 s
  herunter — GoTrue lehnt die zweite Mail an dieselbe Adresse so lange ab,
  ein immer aktiver Knopf würde einen Versand bestätigen, den es nie gab). Neue Passwortfelder und Formular-Rückmeldungen darüber
  bauen, nicht wieder per Hand — vorher gab es vier Kopien mit
  `obscureText: true` und ein nacktes `Text` als Rückmeldung (Issue #131).
  Ein `inputDecorationTheme` gibt es weiterhin nicht; die 19 inline
  gebauten `InputDecoration` sind ein eigener PR wert, kein Nebeneffekt.
- **Die Artensuche bleibt lokal und ohne Abhängigkeit** (#395, seit
  1.118.0): `foldSpeciesName` in `lib/core/mushroom_species.dart` faltet
  Artnamen auf einen Schlüssel (klein, ohne Umlaut-Schreibweise, ohne
  Binde- und Leerzeichen), `species_suggestions.dart` vergleicht darüber
  und rät bei leerem Ergebnis über einen Editierabstand. Vier Dinge, die
  man wissen muss:
  - **Ein Suchdienst kommt nicht in Frage** (Typesense, Meilisearch,
    Algolia geprüft am 2026-09-06). Alle drei sind Server, und die App
    wird im Funkloch benutzt — der Rundlauf wäre tot, wo er gebraucht
    wird. Dazu: neues Netzziel ⇒ Datenschutzerklärung, `play-console.md`
    und Data Safety; Typesense ist GPL-3 und steht damit auf der
    Ablehnungsliste in `tool/license_config.yaml`; Algolias Offline-SDK
    ist nativ für Android/iOS, ohne Flutter-Bindung und ohne Web. Und es
    geht um **110 konstante Namen** in einem `const`-Array.
  - **Ein Fuzzy-Paket löst nur die kleinere Hälfte.** Der gemeldete
    Fehler war eine SCHREIBWEISE, kein Tippfehler; dass „ä" und „ae"
    dasselbe sind, ist die Telefonbuch-Sortierung nach DIN 5007
    Variante 2, für die es auf pub.dev kein Paket gibt (`diacritic` macht
    ä→a und ist blind für „Staeubling"). Unsere Faltung geht bewusst
    darüber hinaus und führt ä UND ae auf „a" — zum Sortieren falsch, zum
    Suchen richtig. `fuzzywuzzy` trägt auf pub.dev zudem eine unbekannte
    Lizenz und liegt zwei Jahre still.
  - **Die Fehlerrichtung ist „lieber ein Vorschlag zu viel".** Eine
    überflüssige Zeile tippt man nicht an; eine leere Liste dagegen liest
    sich als „die Art fehlt" — und genau daraus ist #395 entstanden. Ein
    Vorschlag kann keine falschen Daten erzeugen, er wirkt erst beim
    Antippen. Ein erster Entwurf hatte die Schwelle gegen „Unsinn muss
    schweigen" gemessen und damit gegen den harmlosen Fehler optimiert
    (Betreiber, 2026-09-06).
  - **Die Zusage, an der alles hängt: keine zwei Arten fallen beim Falten
    zusammen.** `_entryFor` schlägt über den gefalteten Namen nach, auch
    auf dem SCHREIBweg (`canonicalSpecies` in `SpotRepository.addFind`).
    Eine Kollision lieferte still den falschen Pilz;
    `test/species_test.dart` rechnet sie über die ganze Liste nach.
- Fehlermeldungen differenzieren; „Internet verfügbar?" ist nicht für jeden
  Fehlerfall der richtige Text (Issue #59).

## Tests

- `flutter analyze` + `flutter test` nach jeder Änderung. **Kein `dart format .`**
  — die CI prüft die Formatierung nicht, und der Formatter aus Flutter 3.41
  bricht 68 Dateien anders um (2264+/1582−). Der Aufruf schreibt sofort in die
  Dateien; ein versehentliches `dart format` ist mit `git checkout -- lib test`
  rückgängig zu machen. Umstellen wäre ein eigener PR, kein Nebeneffekt.
- **Sparsam mit dem Kontext** (2026-10-06, nach der Prüfung von caveman,
  rtk und Graphify — keins passte, der Hebel war diese Datei selbst):
  Während der Arbeit nur die betroffenen Testdateien laufen lassen, mit
  `--reporter failures-only` (grüne Tests schreiben dann nichts); die
  ganze Suite einmal am Ende, ebenfalls so. Breite Suchen über viele
  Ordner an einen Explore-Subagenten geben, der nur das Ergebnis
  zurückbringt. Große Dateien gezielt in Ausschnitten lesen.
- Harness: `test/fakes/test_app.dart` (`pumpApp`) startet die echte App gegen
  die Fakes in `test/fakes/fake_backend.dart` (spiegeln auch die RLS-Regeln).
  Neue Repository-Methoden dort mit abbilden.
- Widget-/Flow-Tests sind der Schwerpunkt — Layout, Zustände und Breakpoints
  pixelfrei prüfen statt per Screenshot. `pumpAndSettle` funktioniert wegen
  der Endlos-Animationen nicht; die `settle()`-Helfer mit festen Frames nutzen.
- **Genau EIN Test läuft auf dart2js** (`test/spot_cache_idb_test.dart`,
  seit #385; in CI als eigener Schritt „Web-Test auf dart2js"). Für alle
  anderen gilt: `flutter test` fährt die Dart-VM, dort ist `kIsWeb` immer
  falsch — jeder Web-Zweig ist damit ungeprüft, auch wenn ein
  Testkommentar das Gegenteil behauptet (genau so in #383 passiert).
  `flutter test --platform chrome` ist der Weg, hat aber eine harte
  Grenze: Der Runner liefert **keine Assets**, ein `rootBundle.load`
  endet dort im Timeout (nicht einmal in einem 404). Für assetfreien Code
  funktioniert es — deshalb kommt der Zwischenspeicher dafür in Frage und
  die Kartenladewege nicht.
  **Ein grüner Chrome-Lauf allein beweist nichts:** Fiele der Zugang
  still auf die Speicher-Fassung zurück, sähe er genauso aus. Der Test
  prüft deshalb ausdrücklich `persistent` des Zugangs — wer eine zweite
  dart2js-Datei baut, braucht denselben Nachweis, dass der Web-Weg
  wirklich lief.
- Kein Netzwerk in Tests (Update-Check ist im Harness auf `null` überschrieben,
  Kartenkacheln werden durch eine transparente 1×1-PNG ersetzt).
- Die Fakes ersetzen keinen echten RLS-Test — das leistet der Schema Check.

- **Datenschutz-Nachweise** (`docs/datenschutz-nachweise.md`, #110): Was
  die Erklärung BEHAUPTET, steht dort belegt — plus Auskunftsverfahren
  (Art. 15) und Verarbeitungsverzeichnis (Art. 30). Der Wächter
  `test/privacy_policy_test.dart` prüft seit #110 auch `web/`; vorher nur
  Dart, und genau daran ist ihm `www.gstatic.com` im Push-Service-Worker
  entgangen. Vier Kategorien statt drei: `fetched`, **`afterConsent`**
  (erst nach dem Einschalten abgerufen — muss trotzdem in der Erklärung
  stehen), `onTapOnly`, `textOnly`. Zwei Punkte sind aus dem Code NICHT
  belegbar und stehen dort als offen: der Supabase-Serverstandort
  (Dashboard) und die Impressumsfrage.

## Compact instructions

Kontext und Sitzungen (2026-10-06). `/compact` und `/clear` kann nur der
Betreiber auslösen; `tool/context_nudge.py` sagt ihm, wann es sich lohnt
(Kontext ab 200k je 100k-Stufe, nach über 60 min Pause, nach
`gh pr create`). Der Agent wiederholt den Rat am Ende einer Antwort, wenn
die Aufgabe damit abgeschlossen ist. Faustregel: **Aufgabe fertig →
`/rename`, dann `/clear`** (kostet nichts; Ordner-CLAUDE.md und Lagebild
bringen den Kontext neu mit). **Gleiche Aufgabe, Kontext zu groß →
`/compact`** (liest selbst den ganzen Verlauf, ist also nicht gratis).

Beim Zusammenfassen BEHALTEN: Issue- und PR-Nummern, Branch, jede
Entscheidung und Vorgabe des Betreibers im Wortlaut, offene Punkte und
Zusagen („melde mich, wenn …"), geänderte Dateien, welche Tests und
Gegenproben gelaufen sind und mit welchem Ergebnis, Messwerte.
WEGLASSEN: Dateiinhalte und Tool-Ausgaben, die sich neu lesen lassen,
verworfene Suchwege, Inhalte der Ordner-CLAUDE.md (laden neu).
