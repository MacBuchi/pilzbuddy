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
- **Web-Vorschau** (`.github/workflows/preview.yml`, #388, seit 1.114.5):
  Jeder Merge auf `main` deployt den Web-Build nach
  `MacBuchi/pilzbuddy-preview` → https://macbuchi.github.io/pilzbuddy-preview/.
  Das ist die Antwort darauf, dass Pages sonst NUR aus dem beförderten Tag
  gebaut wird und ein Web-Fix zeitweise ein Dutzend Versionen lang
  unprüfbar war. Vier Dinge, die man wissen muss:
  - **Eigenes Repo, nicht ein Unterordner.** `promote.yml` deployt mit
    `force_orphan: true` und legt den Pages-Branch bei jeder Beförderung
    neu an — ein `preview/`-Ordner wäre danach weg. Und gleicher Origin
    hieße geteilter `localStorage`: Dort liegen Session-Token und
    Einstellungen, die Vorschau würde sie also mitbenutzen UND verändern.
    Der eigene Origin ist der Grund, warum man sich dort neu anmelden muss.
  - **Zugang ist ein Deploy Key** (`PREVIEW_DEPLOY_KEY`, öffentlicher Teil
    im Vorschau-Repo mit Schreibrecht, privater im Schlüsselordner des Betreibers).
    Bewusst kein PAT wie beim Backup: Das braucht die GitHub-API, hier
    wird nur gepusht. Ein Deploy Key hängt an genau einem Repo, kann
    nichts außer pushen — und **läuft nicht ab**.
  - **`--dart-define=PREVIEW_BUILD=true` ist die tragende Zeile.** Sie
    schaltet `AppDistribution.isPreviewBuild` und darüber den Streifen
    „Entwicklungsstand — nicht freigegeben" sowie den umgedrehten
    Profil-Verweis. Fehlt sie, sieht die Vorschau aus wie die echte App,
    und ein Fehlerbericht daraus beträfe Code, den es nie gab. Ebenso
    tragend: `--base-href /pilzbuddy-preview/` — falsch gesetzt bleibt die
    Seite weiß, ohne Fehlermeldung. `test/release_workflow_test.dart`
    wacht über beide, dazu darüber, dass `promote.yml` weiter auf
    `/pilzbuddy/` zeigt.
  - **Geprüft wird über `webChannelProvider`**, nicht über `kIsWeb` oder
    die Konstante: Beide sind `const` und im Test nicht umschaltbar. Eine
    Zusage, die man nicht prüfen kann, ist keine.
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
  oben), `.github/`, `store/`, `tool/`
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
Datensätze. Stattdessen liegt der DACH-Pilzbestand **als Ganzes** lokal:

    ~/pilzbuddy-gbif/dach_fungi.sqlite    3 782 038 Zeilen, 889 MB
    ~/pilzbuddy-gbif/CITATION.txt         der DOI dazu

Gebaut von `tool/gbif_download.py` (`request` → `status` → `fetch` →
`build`), Stand vom 2026-09-16 ist `10.15468/dl.dwbsuf`. Eine
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
  DACH, ohne Lizenz-, Genauigkeits- oder `basisOfRecord`-Schranke. Die
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

## Technik-Notizen

- Signing: `android/key.properties` + `android/pilzbuddy-release.jks` (beide
  gitignored; Backup im Schlüsselordner des Betreibers). CI erzeugt beides aus den Secrets
  `ANDROID_KEYSTORE_*`. PKCS12: keyPassword == storePassword.
- Web-Builds für Pages brauchen `--base-href /pilzbuddy/` und eine `404.html`
  (Kopie von `index.html`) als SPA-Fallback.
- Datenbank-Änderungen: `supabase/schema.sql` aktuell halten (Frischinstallation)
  UND als nummeriertes `supabase/patch_NNN_*.sql` ablegen (Bestandsprojekt).
  Patches ab Nr. 006 spielt der Pflicht-Check „Schema Check" (ci.yml →
  `tool/db_migrate.sh`) direkt aus dem PR in die Live-DB ein (Tracking in
  `public.applied_patches`, Baseline 001–005 = manuell eingespielt) und
  prüft danach mit `tool/schema_check.sh`, ob alle App-Queries zum
  Live-Schema passen — ohne eingespielten Patch ist kein Merge möglich
  (Lehre aus Issue #27). Der Release-Workflow wiederholt beides als
  Sicherheitsnetz vor dem Ausliefern.
  **Ein Wächter darf sich irren, aber nie die Ursache erfinden.** Seit
  #457 trennt `app_config` „Dienst nicht erreichbar" von einem echten
  Befund; seit dem 2026-09-20 gilt das für ALLE Abfragen
  (`response_diagnosis`, im `--self-test` mitgeprüft). Vorher machte ein
  `curl`-Timeout zwei Sorten Schaden: Die Schlussmeldung riet zu einem
  fehlenden `patch_NNN` — also ausgerechnet dazu, SQL anzufassen —, und
  bei den geschützten RPCs trug die Ersatzantwort selbst ein `"code"`
  und galt damit als „vorhanden und für anon gesperrt". Ein Netzaussetzer
  erzeugte dort ein grünes Häkchen auf einer RECHTE-Prüfung. Eine
  erfundene Ursache kostet Zeit, ein erfundener Erfolg kostet die
  Prüfung. Transport-Fehler zählen jetzt getrennt, scheitern den Lauf
  („unentschieden") und sagen, dass er zu wiederholen ist.

  Vorgeschaltet ist der Pflicht-Check „Schema Dry Run" (`needs:` am Schema
  Check): ein lokaler Supabase-Stack auf dem Runner (`supabase/config.toml`,
  bewusst minimal — nur db, auth, api) fährt **beide** Wege, die es in der
  Wirklichkeit gibt:
  1. **Bestandsprojekt** — `schema.sql` **aus dem Ziel-Branch** einspielen,
     dann nur die Patches dieses PRs per `db_migrate.sh` obendrauf, dann
     `schema_check.sh`. Das ist der Weg, den die Produktion nimmt.
  2. **Frischinstallation** — `supabase db reset`, dann **nur** `schema.sql`,
     dann `db_migrate.sh` (das jetzt nichts mehr tun darf), dann
     `schema_check.sh`. Beweist, dass die Datei für sich vollständig ist.
  Erst wenn beides grün ist, fasst der Schema Check die Live-DB an. Lokal
  derselbe Ablauf: `supabase start`, dann die Schritte von Hand (psql via
  `brew install libpq`; lokalen anon-Key liefert `supabase status -o json`).
  **Warum getrennt:** Bis 1.35.0 lief nur ein Weg — `schema.sql`, dann *alle*
  Patches erneut darüber. Das verlangte von jedem alten Patch auf Dauer
  Idempotenz und verdeckte zugleich eine unvollständige `schema.sql`: Fehlte
  dort etwas, flickte der wiederholte Patch es stillschweigend, und niemand
  erfuhr, dass die Frischinstallation aus `schema.sql` allein kaputt war. Achtung: `config.toml` setzt
  `auto_expose_new_tables = true` (Legacy-Verhalten des Bestandsprojekts);
  das Feld fällt am 2026-10-30 weg — bis dahin gehören explizite Grants in
  `schema.sql`, dann kann die Zeile raus. Braucht das Repo-Secret
  `SUPABASE_DB_URL` (Supabase Session-Pooler-URI inkl. DB-Passwort; der
  Schema Check selbst läuft ohne Secret über den Publishable Key).
  Nutzt ein Repository in `lib/data/` neue Spalten/Embeds/RPCs, die
  Checks in `tool/schema_check.sh` entsprechend erweitern.
- **Edge Functions deployt der Schema Check NICHT** (#277): Er spielt nur
  SQL-Patches ein. `supabase/functions/**` bringt der eigene Workflow
  „Deploy Edge Functions" (`deploy-functions.yml`) auf `main` in die
  Live-Umgebung — pfadgefiltert, damit nicht jeder Merge deployt. Nach
  dem Merge von #284/#285 lag `send-push` deshalb zunächst nur im Repo:
  Testknopf und Cron-Versand liefen ins Leere, ohne dass irgendwo ein
  Fehler stand. Und es wäre wiedergekommen, weil `supabase/` vom Version
  Guard ausgenommen ist — eine Function-Änderung bringt nicht einmal
  einen Bump, an dem jemand stutzen könnte.
  Braucht das Repo-Secret `SUPABASE_ACCESS_TOKEN` (persönliches Token,
  supabase.com/dashboard/account/tokens). **Fehlt es, wird der Deploy
  übersprungen** und die Run-Summary sagt es samt Handbefehl — ein Job,
  der ohne Secret rot würde, wäre bei jedem Merge falscher Alarm.
  **Korrektur vom 2026-08-13:** Genau dieses Überspringen hat bis dahin
  NIE stattgefunden. Das Tor stand als `if: ${{ secrets.… }}` da, und
  der `secrets`-Kontext ist in `if:` nicht verfügbar — GitHub verwarf
  die ganze Datei beim Einlesen, der Workflow ist seit seiner Erstellung
  kein einziges Mal gelaufen (nur Startfehler, an keinem PR sichtbar),
  und dasselbe kopierte Muster hat den Release-Build von v1.91.1
  verhindert. Seither: Feststell-Schritt (Secret in `env:`, `if:` prüft
  `steps.<id>.outputs`), und `test/release_workflow_test.dart` verbietet
  `secrets.` in jedem `if:` aller Workflows — actionlint fängt das
  nicht.
  Gesetzt am 2026-08-11; Supabase gibt persönlichen Tokens **höchstens
  ein Jahr**, es läuft also spätestens am **2027-08-11** ab. Das ist der
  eine Fall, in dem der Job wirklich rot wird statt zu überspringen —
  das Secret ist dann ja da, nur ungültig. Wer hier landet: neues Token
  erzeugen, Secret ersetzen, fertig. Bewusst ein EIGENES Token und nicht
  das aus `supabase login` im Schlüsselbund: Sonst hinge die CI am
  interaktiven Anmeldetoken eines Rechners, und ein Widerruf auf der
  einen Seite legte still die andere lahm.
- **Der Benachrichtigungs-Kanal ist eine Einbahnstraße** (#277, seit
  1.86.0): Ohne die Manifest-Zeile
  `com.google.firebase.messaging.default_notification_channel_id` legt
  FCM still einen eigenen Kanal an — und der ist so leise, dass nur ein
  Symbol in der Statusleiste erscheint, kein Banner. Genau so am
  2026-08-12 auf dem Pixel gesehen, während das Nachbarprojekt mit
  eigenem Kanal ein Banner zeigte; die Nutzlasten beider Apps sind dabei
  identisch, der Unterschied lag ausschließlich auf der Android-Seite.
  Drei Stellen müssen zusammenpassen — Manifest, `res/values/strings.xml`
  und `createNotificationChannel` in `MainActivity.onCreate`;
  `test/android_manifest_test.dart` hält sie zusammen und liest dafür
  ausnahmsweise Kotlin-Quelltext (der native Code hat sonst kein Netz).
  **Die Wichtigkeit lässt sich nachträglich NICHT ändern:** Android merkt
  sie sich beim ersten Anlegen der ID, eine Änderung im Code erreicht
  bestehende Installationen nie. Deshalb `IMPORTANCE_HIGH` — leiser
  drehen kann der Nutzer selbst, lauter niemand. Wer die Stufe je ändern
  will, braucht eine NEUE Kanal-ID.
- **Ein Statusleisten-Symbol ist NUR sein Alphakanal** (#331, seit
  1.99.5): Android malt jedes nicht durchsichtige Pixel weiß und wirft
  die Farbe weg. Ohne
  `com.google.firebase.messaging.default_notification_icon` greift FCM
  auf `android:icon` zurück — das vollflächig deckende Launcher-Icon, als
  Silhouette also ein weißer Klotz. Genau so kam es beim Nutzer an
  („weißer Kreis"). `res/drawable/ic_notification.xml` ist deshalb EINE
  Fläche, und das Gesicht sind Löcher darin (`fillType="evenOdd"`, ab
  API 24 — unser minSdk). Zwei stille Fallen hält
  `test/android_manifest_test.dart` fest: Ein farbiges `fillColor` sieht
  im Diff wie eine Entscheidung aus und wird trotzdem plattgedrückt, und
  ohne `evenOdd` füllen sich die Löcher — dann ist es wieder ein Klotz.
  Von der Designsprache (`.claude/skills/pilz-designer/`) überlebt hier
  sonst nichts: keine Farbe, kein Halo, keine Kontur, keine
  Boden-Ellipse.
  Dieselbe Grafik trägt die Download-Meldung des Foreground-Service.
  `flutter_foreground_task` sucht sie ausschließlich über einen
  Meta-Data-Namen im Manifest und liefert bei einem Tippfehler stumm die
  Ressourcen-id 0; der Name steht deshalb als
  `downloadNotificationIconMetaData` in Dart, und derselbe Test hält
  beide Seiten zusammen.
- **Im Vordergrund ist die SnackBar die einzige Anzeige** — und sie stellt
  sich hinten an. `ScaffoldMessenger.showSnackBar` reiht ein, statt zu
  ersetzen: Die Quittung des Testknopfs („Testnachricht ist unterwegs.",
  4 s) stand deshalb vor der Meldung, die sie ankündigte, und das sah wie
  ein Empfangsfehler aus. `PushListener` räumt jetzt erst
  (`clearSnackBars`) und zeigt dann.
- **Web-Push entscheidet unser eigener Worker, nicht Firebase**
  (`web/push/firebase-messaging-sw.js`, seit 1.203.0). Bis dahin lud er
  das Firebase-SDK, und das zeigte nichts an, sobald IRGENDEIN Fenster
  der Domain sichtbar war — auf GitHub Pages liegen Freigabe und
  Vorschau aber auf einem Ursprung, und „sichtbar" heißt nicht
  „angesehen". Im Feld (2026-09-24, Opera) kam deshalb in der Vorschau
  nur die Testnachricht an, obwohl FCM jeden Versand mit `ok`
  quittierte. Vier Dinge, die man wissen muss:
  - **Fokus, nicht Sichtbarkeit, und nur DIESE App**
    (`APP_BASE` = eine Ebene über dem Scope). Fokussiert ⇒ die App bekommt
    die Meldung per `postMessage` als Leiste; sonst zeigt der Browser
    sie. Die Fehlerrichtung ist gewählt: Meldet ein Browser keinen
    Fokus, erscheint die Systembenachrichtigung — eine zu viel statt
    einer verschluckten.
  - **Beide Seiten der Übergabe gehören uns** (`kPushBridgeType`,
    `pushBridgeMessageOf`, `push_web_bridge_web.dart`); im Web hört die
    App NICHT auf `FirebaseMessaging.onMessage`. Das Firebase-Format
    nachzubauen hätte an Interna gehangen. Zum Empfangen braucht der
    Worker kein SDK — das Abo legt die Seite an (`getToken`), nachgeprüft
    mit echtem Token.
  - **Der Tipp kennt sein Ziel selbst**: `#` + `route` unter der eigenen
    App (Hash-Strategie, kein `usePathUrlStrategy`). `send-push` schickt
    kein `fcmOptions.link` mehr; der feste `/pilzbuddy/` öffnete aus der
    Vorschau die Freigabe.
  - **Geprüft im echten Chrome** (`tool/check_push_worker.mjs`, Job
    „Build Web"): echtes `push`-Ereignis über
    `ServiceWorker.deliverPushMessage`, Freigabe und Vorschau
    nebeneinander. Gestellt ist genau eines — der Fokus, weil ein
    kopfloser Chrome `WindowClient.focused` nie wahr meldet.
  Den Worker frischt die App bei jedem Start auf (`update()`): Sein
  Scope wird nie angesteuert, der Browser sähe sonst höchstens einmal
  am Tag nach. Tote Tokens räumt `send-push` selbst ab („unregistered"),
  weil `push_flush` die Antwort über pg_net nie abwartet.
- **Ein eingespielter Patch wird nie wieder angefasst** (Pflicht-Check
  „Patch-Buchführung", `tool/patch_guard.sh`, im Schema Dry Run): Ändern,
  Löschen oder Umbenennen einer Patch-Datei, die es im Ziel-Branch schon
  gibt, macht CI rot. Grund: `applied_patches` sorgt dafür, dass er live
  **nie** erneut läuft — die Änderung käme also ausschließlich in
  Frischinstallationen an, und beide Welten driften still auseinander. Der
  Weg ist immer ein NEUER `patch_NNN`.
  Damit das durchhaltbar ist, laufen alte Patches bei der Frischinstallation
  gar nicht mehr: `schema.sql` trägt sie am Ende selbst in
  `applied_patches` ein (Saat-Liste). **Ein neuer Patch gehört deshalb im
  selben PR an drei Stellen**: als `patch_NNN_*.sql`, in die Struktur von
  `schema.sql` und in dessen Saat-Liste. Die letzten beiden erzwingt
  `patch_guard.sh` ebenfalls — er vergleicht Liste und Dateien.
  Die frühere Regel („Patches müssen idempotent bleiben, notfalls einen alten
  rückwirkend anpassen — so geschehen in `patch_007`") ist damit **aufgehoben**;
  genau dieses Anpassen war der Fall, den der Wächter jetzt verhindert.
- Breaking-Migration (Spalte/Embed/RPC umbenannt oder entfernt): im selben PR
  `public.app_config.minimum_supported_version` auf die Version dieses PRs
  hochsetzen — per `patch_NNN`, NIE von Hand im Dashboard. Der Schema Check
  garantiert nur, dass die *aktuelle* App passt; ältere Clients im Feld
  scheitern sonst still mit „Internet verfügbar?" (Issue #80). Die App liest
  den Wert beim Start (`updateRequiredProvider`, `UpdateGate` in `app.dart`)
  und sperrt sich per Vollbild darunter. Zwei Leitplanken: die Sperre greift
  nur bei eindeutiger Antwort (fehlgeschlagener Abruf, fehlende Zeile oder
  unbekannte eigene Version ⇒ App läuft normal — sie wird im Wald ohne
  Empfang benutzt), und `tool/schema_check.sh` bricht ab, wenn die
  Mindestversion über `version:` aus `pubspec.yaml` liegt: dieser Wert würde
  auch den neuesten Client aussperren. `app_config` ist bewusst für anon
  lesbar, weil die Prüfung vor der Anmeldung läuft.
- Neue DB-Funktionen: Sichtbarkeit explizit entscheiden — jede Funktion im
  public-Schema ist automatisch ein API-Endpunkt (`/rest/v1/rpc/…`) für anon
  UND authenticated (Default-Grant an PUBLIC; Supabase-Advisor-Funde vom
  20.07.2026). RPCs für die App: `revoke … from public, anon` plus gezielter
  Grant (Muster: `delete_own_account`, `search_profiles` — anon wäre dort ein
  E-Mail-Orakel). Policy-Helfer gehören ins nicht exponierte Schema
  `app_internal` (Patch 011); EXECUTE entziehen geht bei ihnen nicht, weil
  Policies die Funktionen mit den Rechten der anfragenden Rolle auswerten.
  Trigger-Funktionen: alle API-Grants entziehen (der Trigger feuert trotzdem).
  Nach jeder Schema-Änderung den Security Advisor im Supabase-Dashboard
  gegenprüfen. **Dismissen kann das Dashboard NICHT** (Betreiber,
  2026-09-24; hier stand bis dahin das Gegenteil). Was sich beheben lässt,
  wird behoben, auch wenn es nur INFO ist — ein Fund, der für immer
  stehen bleibt, übertönt den nächsten echten: fester `search_path`
  (Patch 036), Sperr-Policy `using (false)` statt „RLS ohne Policy"
  (Patch 037). Dauerhaft stehen bleiben genau vier, alle bewusst:
  `delete_own_account` und `search_profiles` für `authenticated`
  ausführbar (die beiden RPCs der App), `pg_net` im Schema `public`
  (lässt sich nicht verschieben) und Leaked Password Protection (siehe
  unten). Wer dort mehr sieht, hat einen neuen Fund.
- Flutter-Version in CI gepinnt (subosito/flutter-action, aktuell 3.44.8) —
  bei lokalem Flutter-Upgrade auch `.github/workflows/*.yml` anpassen. Es
  sind **sechs** Stellen in vier Dateien: dreimal `ci.yml`, je einmal
  `release.yml` und `security.yml`, dazu `FLUTTER_VERSION` in
  `promote.yml`. Der Eintrag in `release.yml` ist nicht nur Build-Sache —
  `tool/symbolize_anr.py` liest ihn aus dem TAG, um die passende
  ungestrippte `libflutter.so` zu holen; steht dort die falsche Version,
  sind die nativen Frames stumm falsch benannt.
  Die Drift lokal↔CI ist am 2026-08-11 aufgelöst worden (3.41.2 → 3.44.8,
  Betreiber: „3.44 soll auch in der CI laufen"). Vorher hieß die Regel,
  `pubspec.lock` vor dem Commit zurückzunehmen — das ging nur, solange
  keine neue Abhängigkeit dazukam.
- Supabase-Keys in `lib/core/supabase_config.dart` sind bewusst öffentlich
  (Publishable Key); niemals den service_role-Key einchecken.
- Supabase-Auth-Härtung im Dashboard: „Secure password change" ist **an** —
  Passwort-Änderungen über die Auth-API verlangen das aktuelle Passwort bzw.
  eine frische Re-Authentifizierung, ein gestohlenes Session-Token allein
  reicht nicht für eine Kontoübernahme. Eine frisch per Reset-Code angelegte
  Sitzung gilt als frische Authentifizierung, deshalb funktioniert der
  Reset-Flow damit.
- **Leaked Password Protection gibt es auf diesem Projekt NICHT** (geklärt
  2026-08-06): Der HaveIBeenPwned-Abgleich ist ein **Pro-Plan-Feature**,
  PilzBuddy läuft auf Free. Frühere Fassungen dieser Datei behaupteten, sie
  sei „seit 2026-07-22 aktiv" — das war falsch bzw. hat nie getragen, und der
  Security-Advisor-Fund vom 2026-08-05 war kein verlorener Schalter, sondern
  der Normalzustand.
  **Folgen, die man kennen muss:**
  - Der Advisor-Fund bleibt dauerhaft stehen (dismissen geht nicht, siehe
    oben) — nicht gesucht. Wer ihn das nächste Mal sieht, soll nicht wieder eine halbe
    Stunde nach dem Schalter suchen.
  - Der einzige Passwortschutz ist damit `minPasswordLength = 8`
    (`lib/core/widgets/password_field.dart`). „passwort" hat acht Zeichen —
    die Grenze hält also niemanden auf, der ein bekanntes Leak-Passwort
    wählt.
  - Ersatz wäre ohne Pro-Plan machbar: Die HIBP-Pwned-Passwords-API ist
    kostenlos und arbeitet mit k-Anonymity (nur die ersten fünf Zeichen des
    SHA-1-Hashes gehen raus, das Passwort selbst nie). Das wäre ein eigenes
    Feature mit neuem Netzziel — also Datenschutzerklärung und
    `docs/play-console.md` im selben PR. Bisher nicht gebaut, bewusst offen.
- Passwort ändern für Angemeldete (`AuthRepository.changePassword`, Dialog im
  Profil, Issue #127, seit 1.31.0): meldet sich zuerst mit dem **aktuellen**
  Passwort neu an (`signInWithPassword`) und ruft erst dann `updateUser` —
  wegen „Secure password change" scheitert `updateUser` allein mit 403. Wer
  den Zwischenschritt wegkürzt, merkt es nur live; deshalb prüft ihn
  `tool/auth_reset_check.sh` gegen echtes GoTrue. Nebeneffekt mit Absicht:
  Ein falsches aktuelles Passwort scheitert schon an der Anmeldung.
  Mitfahrbars `_AdminPasswordDialog` fragt das aktuelle Passwort NICHT ab —
  das geht dort nur, solange die Einstellung aus ist; beim nächsten Anfassen
  mitziehen.
- Passwort-Reset (`lib/features/auth/login_screen.dart`, drei Modi;
  `AuthRepository.sendPasswordResetCode` / `resetPasswordWithCode`): läuft
  über den **Zahlencode** aus der Mail (`verifyOTP` mit
  `OtpType.recovery`), nicht über deren Link. Grund: Im PKCE-Standardflow
  legt das SDK beim Anfordern einen „code verifier" im Speicher des
  anfragenden Geräts ab und verlangt ihn beim Einlösen wieder — wer in der
  App anfordert und die Mail im Browser öffnet, scheitert an
  „Code verifier could not be found in local storage.". Daraus folgen zwei
  Pflichten im Dashboard: eigenes SMTP (Brevo Free, der Standardversand
  liefert nur an Projekt-Mitglieder) und eine Reset-Mail-Vorlage, die
  `{{ .Token }}` zeigt und **keinen** Link enthält — bleibt der Link drin,
  existiert der kaputte Weg weiter. Der Router lässt eine
  `passwordRecovery`-Sitzung bewusst nicht in die App (`lib/core/router.dart`
  filtert das Ereignis), sonst läge die Karte mitten im Reset offen, bevor
  das neue Passwort gesetzt ist.
  Mitfahrbar löst denselben Fall über den Mail-Link und hat damit genau die
  Lücke, die PilzBuddy hier umgeht (dort `MacBuchi/MitFahrBar` Issue #102) —
  beim nächsten Anfassen dort gleich mitziehen.
  Von den sechs Mail-Vorlagen im Dashboard sind **drei** angepasst (deutsch,
  mit Code, im Stil von #192): „Reset password", „Confirm sign up" und seit
  #193 „Change email address" — genau die drei, die die App auslöst.
  „Magic link or OTP", „Invite user" und „Reauthentication" schlafen und
  stehen bewusst auf englischem Standardtext: Eine fertig aussehende
  Vorlage würde vortäuschen, das Feature existiere (Einladen läuft über
  das System-Teilen-Blatt, nicht über eine Server-Mail). Der Zahlencode kommt aus der jeweiligen Vorlage, NICHT aus
  „Magic link or OTP" — `/recover` bzw. `/signup` verschickt, `verifyOTP`
  prüft nur. „Confirm email" ist seit 2026-07-26 **an**; damit liefert
  `signUp` keine Sitzung mehr — `AuthRepository.signUp` gibt deshalb zurück,
  ob bestätigt werden muss, und der Registrieren-Screen zeigt dann die
  Code-Eingabe statt stumm stehenzubleiben (Issue #129, seit 1.31.0). Beide
  Wege haben ein „Erneut senden" mit 60-Sekunden-Sperre (`ResendButton`);
  im Reset meldet es bewusst immer dasselbe, ein Rate-Limit-Hinweis käme nur
  bei existierendem Konto und wäre damit ein Orakel. Bestätigt wird wie beim
  Reset über den **Code** aus der Mail (`verifyOTP` mit `OtpType.signup`),
  nicht über deren Link: `signUp` legt denselben PKCE-Verifier auf dem
  anfordernden Gerät ab, der Link wäre also wieder gerätegebunden.
  `verifyOTP` meldet direkt an, die Registrierung endet also auf der Karte.
  Warum überhaupt Pflicht: Freundessuche läuft über die exakte
  E-Mail-Adresse, und der Reset-Code geht an ein Postfach — beides
  verlässt sich darauf, dass die Adresse dem Konto gehört. Am 2026-07-25
  ist genau das passiert: eine Registrierung auf eine `+`-Alias-Adresse,
  die web.de nicht zustellt, hinterließ ein dauerhaft unrettbares Konto;
  solche Zustellversuche zählen bei Brevo zusätzlich als Hard Bounce
  gegen die Absender-Reputation.
  **Reihenfolge beim Umstellen im Dashboard** (am 2026-07-26 so gemacht,
  hier als Muster für den nächsten Schalter dieser Art): erst die App-Version
  ausliefern, die beide Einstellungen beherrscht, dann die Vorlage „Confirm
  sign up" auf `{{ .Token }}` ohne Link setzen, dann „Confirm email"
  anschalten. Andersherum bricht die Registrierung still.
  **Unverlangte Reset-Mails an das Play-Testkonto sind erwartbares
  Rauschen** (Befund 2026-08-17; die Adresse steht im DocuHub, `apps/pilzbuddy.md`): Die Adresse
  liegt als App-Zugriff in der Play Console, und Googles automatische
  Prüf-Robots klicken die App durch — auch „Passwort vergessen" auf dem
  Login-Screen (im Wochendigest als „Passwort-Reset anfordern" mit 429/
  504 sichtbar). Ohne Postfachzugriff ist das harmlos: Der Code geht nur
  dorthin, die Vorlage trägt die „nicht angefordert? nichts passiert"-
  Zeile. Geräte-/IP-Angaben in der Mail gehen NICHT — GoTrue reicht
  keine Request-Metadaten an Vorlagen (nur Token/URL/Email); üblich sind
  solche Angaben ohnehin in Anmelde-Benachrichtigungen, nicht in
  Reset-Mails. Der eine echte Hebel gegen Missbrauch: das Mail-Rate-
  Limit im Dashboard (Auth → Rate Limits) unter Brevos 300/Tag halten —
  **gesetzt auf 3/h am 2026-08-17** (≤ 72/Tag). Es gilt projektweit für
  ALLE Mail-Sorten, auch Registrierungs-Bestätigungen: Für eine
  Einladungs-Welle (12 Tester an einem Abend) vorher hochdrehen und
  danach zurück.
  E-Mail ändern (Issue #193, seit 1.52.0): `AuthRepository.changeEmail`
  meldet sich wie beim Passwortwechsel erst mit dem aktuellen Passwort neu
  an, dann verschickt `updateUser(email:)` ZWEI Mails mit je eigenem Code
  (alte und neue Adresse, „Secure email change"/`double_confirm_changes`).
  Der erste eingelöste Code wird nur quittiert, erst der zweite vollzieht
  den Wechsel und bringt eine frische Sitzung — die Profil-Kachel hört auf
  `authStateProvider`, sonst zeigt sie die alte Adresse weiter (am
  Emulator gefunden). Ein Postfach allein reicht also nie, und genau das
  prüft der Wächter mit.
  Geprüft werden die Flows von `tool/auth_reset_check.sh` im Job „Schema Dry
  Run" — gegen echtes GoTrue im lokalen Stack, inklusive Mailabholung aus
  Mailpit: Registrierung samt Bestätigung, Reset, Passwortwechsel und
  E-Mail-Wechsel (der Name des Skripts ist seit #127/#129/#193 zu eng).
  `supabase/config.toml` spiegelt dafür die Dashboard-Härtung
  (`[auth.email] secure_password_change = true`,
  `double_confirm_changes = true`), damit lokal nicht laxer
  geprüft wird als live; die Mail-Vorlagen liegen als versionierte Kopien
  unter `supabase/templates/`. **Blinder Fleck:** Die im Dashboard
  hinterlegte Vorlage sieht CI nie. Wer sie dort auf den Link zurückstellt,
  bricht „Passwort vergessen" oder den Adresswechsel in Produktion,
  während CI grün bleibt — Vorlagen also immer an beiden Stellen ändern.
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
- **Zwischenspeicher und Ausgangskorb liegen im Browser in IndexedDB**
  (#385 seit 1.115.0, #386 seit 1.116.0). `NoSpotCache`/`NoOutbox` sind
  nicht mehr der Web-Zweig, sondern nur noch der Fall „kein IndexedDB".
  **Name und Version der Datenbank haben EINEN Besitzer**
  (`browser_db.dart`): Öffnete der eine Speicher v1 und der andere v2,
  blockierte der Upgrade — im selben Tab, dauerhaft, ohne Fehlermeldung.
  Ein neuer Speicher heißt: dort eintragen und `kBrowserDbVersion`
  erhöhen. Vier Dinge, die man wissen muss:
  - **Abgelegt wird derselbe JSON-TEXT wie in der Datei auf Android**,
    nicht ein Objekt. IndexedDB nähme verschachtelte Maps direkt an, gäbe
    sie aber als `Map<String, Object?>` zurück — und darauf ist
    `Map<String, dynamic>` nicht zuweisbar, was `Spot.fromJson` erwartet.
    Ein Text nimmt denselben Weg durch `jsonDecode` wie auf dem Telefon:
    `encodeSpotCache`/`decodeSpotCache` sind deshalb geteilt.
  - **Fester Schlüssel, Konto IM Eintrag** — wie in der Datei. Nach der
    Nutzer-id zu schlüsseln wäre naheliegend, ließe aber die Spots jedes
    früher angemeldeten Kontos im Browser liegen.
  - **`idb_shim` ist DIREKTE Abhängigkeit**, obwohl `vector_map_tiles` es
    ohnehin mitbringt (dieselbe Begründung wie bei `executor_lib`: nicht
    an einer exakt gepinnten Beta hängen). Der Nebengewinn ist der Test:
    `newIdbFactoryMemory()` fährt dieselbe Implementierung auf der VM.
  - **Ohne IndexedDB (privater Modus, `file://`) gelten weiter
    `NoSpotCache`/`NoOutbox`.** Bewusst NICHT `idbFactoryBrowser`, das
    still auf die Speicher-Fassung zurückfällt — ein Zwischenspeicher,
    der jeden Neustart vergisst, sähe von außen aus wie einer, der
    bleibt.
  Und der Unterschied, der die zweite Stufe ausmacht: **Ein Browser darf
  seinen Speicher ohne Vorwarnung räumen.** Für die KOPIE ist das
  verkraftbar, für das ORIGINAL im Korb nicht. Deshalb bittet
  `IndexedDbOutbox.append` beim ersten Ablegen einmal um
  `navigator.storage.persist()` (`browser_storage.dart`) — erst dort und
  nicht beim Start, weil Firefox dafür nachfragt und eine Nachfrage ohne
  Anlass eine Zumutung wäre; dieselbe Linie wie `positionFixProvider`.
  Lehnt der Browser ab, wird **trotzdem abgelegt** und die Karte sagt es
  (Streifen unter dem Korb-Banner): Chrome lehnt in einem gewöhnlichen
  Tab regelmäßig ab, und dann wäre der Fund SOFORT verloren statt
  vielleicht später. Die Anzeige fragt nie nach (`persisted()`, nicht
  `persist()`), und der Stub auf Android sagt `true` — ein Warnhinweis
  über ein Dateisystem wäre schlicht falsch.
- **Der eigene Service Worker** (`web/sw.js` + `web/flutter_bootstrap.js`,
  #387, seit 1.117.0). Acht Dinge, die man wissen muss:
  - **Immer zuerst das Netz, der Cache nur als Rückfall.** Das ist die
    tragende Entscheidung: Ein Cache, der gewinnt, nagelt Nutzer auf einen
    alten Stand und umgeht damit genau die kontrollierte Beförderung. Dazu
    ein harter Grund — Flutters Web-Ausgaben tragen KEINE
    Inhalts-Prüfsummen (`main.dart.js` heißt immer gleich), ein
    `cache-first` lieferte also stillschweigend die alte App. Der Preis
    ist ehrlich: Die PWA wird dadurch **nicht schneller**, nur startfähig.
  - **„Zuerst das Netz" heißt nicht „auf das Netz warten"** (seit
    1.204.2, Feldbefund 2026-09-24: „kein Flugmodus, aber quasi kein
    Empfang", die PWA blieb leer). Bis dahin hatte nur die Seite selbst
    eine Grenze (3 s); `main.dart.js` und CanvasKit warteten ohne Grenze
    auf ein Netz, das Verbindungen annahm und nie antwortete. Jetzt gilt
    für jede Datei MIT Kopie eine Grenze (4 s), und nach einem Reißen
    nur noch 300 ms, bis wieder etwas aus dem Netz kommt — die App lädt
    ihre Dateien nacheinander, mit 4 s je Stück waren es gemessen 20 s
    statt 1,8. Ohne Kopie wird weiter gewartet.
  - **Der alte Cache geht erst, wenn der neue alles hat** (seit 1.204.2).
    Vorher löschte das Aktivieren ihn sofort, im neuen lag nur die
    Hülle, und wer nach einem Deploy kurz online war, hatte keinen
    Offline-Start mehr — mit einem Deploy je Merge in der Vorschau der
    Normalfall. Es bleibt genau EIN früherer (der mit Vollständig-
    Merker); solange er steht, kommt jeder Rückfall zuerst aus ihm, damit
    ein Start ohne Netz aus EINEM Stand kommt. `topUp` füllt den neuen
    per `If-None-Match` nach — 304 heißt umlegen statt neu laden — und
    räumt erst dann ab. „Früher" heißt in Anlegereihenfolge VOR dem
    eigenen Cache — liegt der Cache eines neueren, noch wartenden
    Workers daneben, mischte der Rückfall sonst zwei Stände, und die
    Mischung startete ohne Netz nicht (beim Bau gemessen).
    Drei Fallen beim Prüfen, alle passiert: Ein Update bei HÄNGENDEM
    Netz aktiviert nie (der Browser wartet auf die offenen Anfragen des
    alten Workers), prüft also nur den alten. Wird das Netz erst nach
    dem Update knapp, ist das Nachfüllen auf einem schnellen Rechner
    schon fertig, und der Schritt prüft nichts (in CI so). Deshalb
    blockiert der Testserver gezielt nur das Nachfüllen — erkennbar an
    der Kennung `x-pilzbuddy-topup`, die auch die 304 des Nachfüllens von
    denen des Browsers trennt.
    `version.json?cachebuster=…` legt der Worker gar nicht ab — sonst
    wüchse der Cache je Start um einen Eintrag.
  - **`web/flutter_bootstrap.js` ist Pflicht, nicht Bequemlichkeit.** Die
    erzeugte Fassung übergibt dem Loader `serviceWorkerSettings`, und der
    registriert `flutter_service_worker.js` (784 Bytes, meldet sich selbst
    ab) genau dann, wenn für den Scope schon eine Registrierung existiert
    — ab dem zweiten Besuch also UNSERE. Der Cache wäre bei jedem Laden
    weg, ohne eine Fehlermeldung.
  - **Die Platzhalter dürfen in KEINEM Kommentar der Datei stehen.** Der
    Build ersetzt sie überall, und der Lader ist mehrzeilig: Aus einer
    `//`-Zeile bricht er aus, danach ist die Datei Syntaxmüll und die App
    startet gar nicht. Beim Bau von #387 genau so passiert; sichtbar nur
    als `SyntaxError` in der Browser-Konsole. Ein Test wacht darüber.
  - **Der erste Besuch füllt den Cache NICHT von allein.** Die ersten
    Anfragen gehen raus, bevor der Worker aktiv ist; er sieht sie nie
    (`clients.claim()` übernimmt die Seite mitten im Laden, kann aber
    nicht rückwirkend mithören). Deshalb meldet die Seite ihm per
    `postMessage`, was sie geholt hat (`warm`) — eine Liste von Hand wäre
    bei jeder Änderung still falsch, und „still falsch" heißt hier:
    startet ohne Netz nicht. Gegengeprobt: Ohne den Schritt bleiben 6
    statt 12 Einträge übrig und der Offline-Start scheitert, während
    `flutter test` grün bleibt.
  - **Gemeldet wird über einen BEOBACHTER, nicht mit einer
    Momentaufnahme** (#427, seit 1.128.2). Bis dahin stand dort ein
    einmaliges `getEntriesByType('resource')` gleich nach `runApp`. Das
    ersetzte die Liste, tauschte sie aber gegen einen Wettlauf: Was bis
    zu diesem einen Augenblick geholt war, kam in den Cache, alles
    Spätere nie. Zwei Läufe desselben Commits legten daraufhin 15 bzw.
    16 Dateien ab — und der mit 16 startete ohne Server nicht. **Mehr ist
    nicht vollständiger**, die beiden Mengen stehen in keinem
    Teilmengen-Verhältnis; eine Zahl ist hier eine Aussage über den Lauf,
    nicht über den Build. `PerformanceObserver` mit `buffered: true`
    liefert Vergangenes UND Künftiges, es gibt also keinen Zeitpunkt mehr,
    an dem gemessen wird. Damit verhält sich der erste Besuch wie jeder
    weitere — ab dem zweiten legt der Worker als Kontrolleur ohnehin jede
    erfolgreiche eigene Antwort ab. Folgerichtig prüft
    `check_service_worker.mjs` seither keine Untergrenze mehr, sondern die
    Zusage selbst: **jede Datei, die der Besuch geholt hat, liegt danach
    im Cache** — der Lauf gegen sich selbst, eine feste Liste wäre wieder
    still falsch. Die verbliebene Zahl (`>= 8` auf der Soll-Seite) beweist
    nur, dass überhaupt gemessen wurde.
  - **`--no-web-resources-cdn` gehört in JEDEN Web-Build** (ci, promote,
    preview; ein Test wacht darüber). Ohne den Flag holt der Loader
    CanvasKit von `www.gstatic.com` — offline tot, und die IP jedes
    Besuchers ginge an Google. Die Dateien liegen ohnehin im Build, der
    Flag kostet nichts.
  - **Die Notbremse lädt bewusst NICHT neu**
    (`postMessage({type:'unregister'})`): Beim nächsten Laden meldet der
    Bootstrap den Worker sofort wieder an, und dann wäre von der Wirkung
    nichts zu sehen. Der eigentliche Ausweg aus einem kaputten Worker ist
    ein Build ohne die Registrierung plus ein `sw.js`, das sich selbst
    abmeldet — der erreicht jeden Online-Nutzer, eben WEIL die Navigation
    netzwerkzuerst läuft.
  **Geprüft wird im echten Browser**, nicht per Textsuche:
  `tool/check_service_worker.mjs` (Job „Build Web") fährt einen Chrome
  gegen den gebauten Ordner und **schaltet den Webserver dabei wirklich
  ab**. Die Prüfungen in `test/web_shell_test.dart` fangen nur die Fallen,
  die man im Diff übersieht — eine falsche Entscheidung im Worker sehen
  sie nicht.
- **Die Web-Fassung lädt Roboto von `fonts.gstatic.com`** — gemessen am
  2026-09-04, bei jedem Seitenaufruf und vor jeder Anmeldung. Das ist
  Flutters Vorgabe für die Standardschrift und hat mit CanvasKit nichts zu
  tun (das kommt seit #387 lokal). Offenzulegen war es trotzdem:
  `web/datenschutz.html` nennt es seit 1.117.0. Abstellen hieße Roboto
  mitliefern und im Theme setzen — eigenes Issue, eigene Größenfrage.
  Nebenkosten, die bleiben: `assets/map_glyphs/` (984 KB) landet im
  Web-Build und wird dort NIE gelesen (nur MapLibre nutzt Glyphs, und
  MapLibre ist im Web aus). Flutter kennt keine plattformabhängigen
  Asset-Listen.
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
- **Die Pilztour macht aus einem Weg die Leergänge, die niemand
  einträgt** (#338, seit 1.102.0): GPS-Aufzeichnung auf Knopfdruck
  (`lib/features/tour/`), Punktspur auf der Karte, und beim Beenden ein
  Blatt, das je eigenem Spot vorschlägt, ob dort „nichts gefunden"
  gebucht wird. Sechs Dinge, die man wissen muss:
  - **Die Fehlerrichtung ist vorgegeben, überall.** Ein übersehener
    Leergang kostet eine Zeile; ein ERFUNDENER vergiftet die Stichprobe,
    die #199 als unabhängigen Prüfstein für die Ampel aufhebt. Wo
    `tour_track.dart` zwischen „lieber zu wenig" und „lieber zu viel"
    wählen muss, wählt sie zu wenig — ein Zeitabschnitt zählt nur, wenn
    BEIDE Enden im Radius liegen und BEIDE Fixes scharf genug sind.
  - **Ein Radius, ein Faktor — keine zweite Zahl.**
    `kNearbySpotMeters` (20 m, #215) bleibt die eine Antwort auf
    „derselbe Ort"; das Vorbeigeh-Band ist `kTourPassByFactor` × davon
    (Betreiber, 2026-08-27). Die Verweildauer ist die einzige
    unterscheidende Achse: Der Radius sagt, wo man war, die Uhr sagt, ob
    man hingesehen hat.
  - **Die Genauigkeit je Fix wird MITGEFÜHRT und entscheidet.** Unter
    Blätterdach liegt GPS 10–20 m daneben; ein 20-m-Radius gegen einen
    ±40-m-Fix ist Rauschen im Gewand einer Messung. Unscharfe Punkte
    zählen keine Verweildauer, gehen aber weiter in die kürzeste
    Entfernung ein — sonst verschwände ein wirklich abgesuchter Spot ganz
    aus dem Blatt.
  - **Das Blatt zeigt die Bewertung, statt sie zu verstecken.** Erfüllt
    ⇒ hervorgehoben und angehakt; gestreift ⇒ verblasst, aus, mit Grund
    und Zahl. Eine Liste, in der alles vorangekreuzt ist, wäre ein
    Anstupser, Leergänge zu buchen, die nie verdient wurden. Ein Fund
    von HEUTE am selben Spot sperrt den Leergang doppelt — in der
    Anzeige und im Buchen; die zweite Sperre trägt wirklich, weil ein
    abgesuchter Spot in `_checked` auf true steht.
  - **Foreground-Service vom Typ `location`, NICHT
    `ACCESS_BACKGROUND_LOCATION`.** Die Aufnahme startet im Vordergrund
    und trägt eine Dauerbenachrichtigung — die IST die Offenlegung. Der
    ganze Abschnitt „Prominent Disclosure: nicht erforderlich" in
    `docs/play-console.md` hängt daran, und ein Test hält beide Hälften
    fest. Der Manifest-Typ ist `dataSync|location` als OBERMENGE; welche
    Typen ein Lauf beansprucht, entscheidet `startService`. **Ändert
    sich die Typmenge, startet der Koordinator den Service NEU** —
    `updateService` kann Typen nicht ändern (nachgesehen in
    flutter_foreground_task 10.0.0).
  - **Gemessen wird im ISOLATE DES SERVICE, nicht im Main-Isolate**
    (#342, korrigiert in 1.103.0). Die erste Fassung nahm einen
    `Timer.periodic` in der App — richtig, solange die App lebt, und
    genau das war der Fehler: Wischt der Nutzer sie aus der Übersicht,
    stirbt der Flutter-Prozess samt aller Timer, während der Service
    sichtbar weiterläuft (`START_STICKY`, kein `stopWithTask`). Im Feld
    am 2026-08-27 so gesehen. `flutter_foreground_task` startet für den
    Service ein eigenes Flutter-Isolate; dort steht jetzt
    `recordTourTick`. Drei Folgen:
    - **Der Service hat genau EINEN Einstiegspunkt**, also trägt ein
      Handler beide Nutzer: Für einen Download tut er nichts, für eine
      Tour misst er. Was gilt, steht in der Brücke
      (`kTourDataActive` über `FlutterForegroundTask.saveData`, also
      SharedPreferences — sie ist in beiden Isolaten lesbar).
    - **Der Takt lässt sich am laufenden Service ändern**
      (`updateService` nimmt `foregroundTaskOptions`), die Service-TYPEN
      dagegen nicht. Deshalb `setRepeat` ohne Neustart und ein Neustart
      bei Typwechsel.
    - **Im Isolate gibt es kein Riverpod, keine Widgets und keinen
      `ErrorSink`.** Der Verzeichnispfad wird einmal drüben aufgelöst
      und über die Brücke gereicht; `recordTourTick` fängt alles, weil
      eine durchgereichte Ausnahme dort niemanden hat, der sie fängt —
      und die Tour für den Rest des Wegs still beenden würde.
    - **Die Rückrichtung muss in `main()` ANGEMELDET werden** (#465,
      behoben in 1.143.1). `sendDataToMain` schlägt seinen Port über
      `IsolateNameServer.lookupPortByName` nach, und angelegt wird der
      ausschließlich von `FlutterForegroundTask.initCommunicationPort()`
      — das Paket ruft es nie von selbst, es steht als Zeile für `main()`
      in dessen README. Sie hat von #342 an gefehlt: Jeder Takt landete
      korrekt in der Datei und die Meldung im Nichts, weil
      `sendPort?.send(data)` auf `null` still durchfällt. Vier Wochen
      unbemerkt, und zwar weil `_firstFix` noch im Main-Isolate
      `acceptTick` ruft — die Karte hatte damit GENAU EINEN Punkt: als
      Punkt ein Pünktchen unterm Fadenkreuz, das nach „läuft" aussieht,
      als Linie gar nichts (`tourTrackPolyline` braucht zwei). Gemeldet
      wurde deshalb „die Linie geht nicht", kaputt war die Anzeige
      insgesamt. Verloren ging nie etwas; ein Neustart holte den Weg
      über `restore()` zurück, und genau das war beim Nachstellen der
      entscheidende Kontrollversuch. `test/tour_live_bridge_test.dart`
      prüft Rundlauf, Gegenprobe UND die Zeile in `main.dart` — die
      ersten beiden allein leuchten grün, während die App steht.
    Ebenfalls gefallen: das `timeLimit` von 20 s auf dem Fix. Es machte
    aus jedem langsamen Hintergrund-Fix stillschweigend gar keinen.
  - **Der Track liegt in `tours/` als JSON Lines** und wird beim Gehen
    angehängt, nicht am Ende geschrieben: Der Prozess-Kill ist hier der
    Normalfall (#147). Ein Abbruch kostet damit höchstens die letzte
    Zeile; beim Ausgangskorb wäre derselbe Abbruch eine halbe Datei,
    deshalb steht dort `.part` + `rename`. `tours/` gehört in beide
    Backup-Ausschlüsse — ein Bewegungsprofil hat in Googles Cloud so
    wenig verloren wie die Fundstellen. Gelöscht wird **erst nach dem
    Blatt**: Wer vorher aufräumt, verliert drei Stunden Gehen, wenn das
    Blatt weggewischt wird.
  - **Die Spur verlässt das Gerät seit 1.147.0 doch** (#340 Stufe 2) —
    aber nur, wenn BEIDES läuft: eine Tour UND die Standort-Freigabe.
    Die Bedingung ist ein UND und steht als eine Zeile in
    `planTrackShare` (`tour_sharing.dart`); wer aufzeichnet, ohne zu
    teilen, behält Stufe 1 unverändert. `expires_at` wird aus der
    Freigabe GEERBT statt neu eingeholt: eine Zustimmung statt zwei, und
    zwei Fristen könnten auseinanderlaufen. Tour- oder Teilen-Ende
    löscht die Zeile sofort — nicht erst beim Ablauf, sonst läge dort
    eine Freigabe, die niemand mehr gibt.
    **Eine Zeile je Nutzer, ersetzt statt angehängt** (`tour_tracks`,
    Patch 023, Policies als Spiegel von `live_locations`): Eine Zeile je
    Messpunkt wären ~720 je Person und Drei-Stunden-Tour — die erste
    Tabelle, deren Größe mit der verbrachten ZEIT wächst statt mit den
    Funden. Gedünnt sind es ≤ 400 Punkte, rund 10 KB.
    **Hochgeladen wird im MAIN-Isolate**, gemessen wird im Service-Isolate
    (#342). Die Folge ist benennbar: Wer die App wegwischt, zeichnet
    weiter auf, lädt aber nichts mehr hoch, bis er sie öffnet. Verloren
    geht nichts, weil immer die GANZE Spur geschrieben wird — deshalb
    braucht der Weg auch keinen Ausgangskorb.
    **Die Spur eines Buddys darf die eigenen Leergänge NIE beeinflussen.**
    Boden, den jemand anders gegangen ist, ist kein Boden, den ICH
    abgesucht habe; `tourVisits` sieht weiterhin nur eigene Punkte. Das
    ist die Stichprobe, die #199 als unabhängigen Prüfstein aufhebt.
    Die vier Stellen, an denen die alte Zusage stand, sind im selben PR
    mitgezogen: `web/datenschutz.html`, `docs/play-console.md`,
    `docs/datenschutz-nachweise.md` und dieser Abschnitt.
  - **Die Anzeige (1.148.0) hat kein eigenes Tor.** `friendTracksProvider`
    hängt am ERGEBNIS von `friendLocationsProvider`: Eine Spur gibt es
    nur, wo ein geteilter Standort ist, also spart man sich den Poll,
    wenn niemand teilt — statt dessen drei Tore (Freundschaft,
    Vordergrund, träger Takt) zu kopieren. `select` auf „teilt überhaupt
    jemand", nicht auf die Liste: Der Standort-Strom liefert alle paar
    Sekunden neu und baute die Schleife sonst jedes Mal neu auf.
    Der Takt ist der des SENDERS (`kTrackUploadInterval`) — häufiger zu
    fragen, als geschrieben wird, holt dieselben Punkte noch einmal.
    Im Test ist der Provider wie `friendLocationsProvider` auf einen
    Einmal-Abruf überschrieben (`test/fakes/test_app.dart`), sonst
    hinge nach jedem Widget-Test ein Timer.
    **Die Farbe je Buddy kommt aus der Spanne, nicht aus einem
    Sonderfall**: 190°…429°, umgebrochen also [190°,359°] ∪ [0°,69°] —
    `forestGreen` (~123°) liegt außerhalb. Ein erster Entwurf hatte
    zusätzlich einen Sprung über den grünen Sektor; die Gegenprobe zeigte
    ihn als toten Code (entfernen ließ den Test grün). Wer die Spanne
    ändert, muss den Test lesen.
- **Das Ampel-Banner rechnet beim Start, nicht auf einem Server**
  (Baustein B aus #277, seit 1.101.0): Ein Hinweis auf der Karte, wenn
  die Ampel an einem EIGENEN Spot günstig steht
  (`lib/features/ampel/ampel_scan.dart`). Vier Dinge, die man wissen
  muss:
  - **Die KARTE zeigt das Maximum über alle Klassen** (seit 1.140.0,
    Betreiber 2026-09-12: „soll das Maximum für alle Klassen wiedergeben
    und nicht nur für eine"). Die Regel steht in `ampelBestOf`
    (Gitterweg) und `ampelBestReadingFrom` (volle Ablesung) — und NUR
    dort; Fläche, Legende und „Was ist hier?" müssen dieselbe Antwort
    geben, `test/ampel_fill_test.dart` hält sie Zelle für Zelle zusammen
    (#279). Fünf Dinge:
    - **Saison-Tor je KLASSE auf der Fläche** (seit 1.157.0, #495;
      davor galt „kein Saison-Tor auf der Fläche", weil die Fläche keine
      Art kennt). Die Antwort darauf ist das Maximum über die
      Mitglieder: Eine Klasse rechnet, solange mindestens eine ihrer
      Arten Saison hat (`ampel_season_gate.dart`, Tor, kein Faktor).
      Anlass: „Austernseitling & Co." war im September günstig — zu
      Recht, für Krause Glucke und Leberpilz (Saisonanteil 100), der
      Austernseitling liegt bei 3. Das Fenster kommt aus dem
      Case-Crossover, die Saison kürzt sich dort heraus; die Klasse
      sagt nie „es ist die Saison". Die Legende nennt deshalb, wer die
      Klasse gerade trägt („jetzt: Krause Glucke, Leberpilz"), sobald
      es nicht der Namensgeber ist. Fläche, Legende, Ampel-Blatt,
      Spot-Blatt und Nachlauf lesen `activeAmpelClassesProvider`; die
      Fundorte-Scheiben lesen weiter die rohe Auswahl, sie zeigen
      Meldungen, keine Ampel. Frost/Mindesttemperatur war Laborarbeit
      (#497) — und ist seit 1.160.0 als „milder" ein Code-Wert, siehe
      unten.
    - **Arten lassen sich von der Ampel ausnehmen** (#495, Schalter je
      Art im Reiter „Pilze", gerätelokal `ampel_excluded_species`):
      raus aus Nachlauf, Spot-Blatt und dem Saison-Tor — alle Arten
      einer Klasse aus heißt Klasse aus.
    - **Bei Gleichstand gewinnt die frühere Klasse, nicht der höhere
      Score.** Scores verschiedener Klassen sind nicht vergleichbar:
      Jede Schwelle ist auf ihre eigene Verteilung kalibriert, 0,55
      heißt im Herbstfenster „günstig" und im Sommerfenster
      „verhalten". Aus demselben Grund sortiert das Blatt nach STUFE
      und nicht nach Score.
    - **Die Häufigkeit steigt, und das ist gewollt:** 19,9 % → 30,2 %
      günstige Vergleichstage (`docs/pilzampel-schwellen-messung.md`).
      Es wird mehr behauptet — „für mindestens eine von zwei Gruppen" —,
      also gilt es öfter. Wer eine Klasse hinzufügt, misst die Quote neu.
    - **Die Ampel gilt nur für SAMMELPILZE** (Betreiber, 2026-09-22:
      „für giftige / ungenießbare Pilze brauchen wir keine Ampel").
      Heute stimmt das ohnehin — 16 Arten, alle Speisepilz oder nur
      gegart —, aber seit 1.171.0 hält `test/ampel_model_test.dart`
      es fest. Eine Günstig-Meldung über einen Giftpilz läse sich als
      Einladung, und der Weg von einem neuen Verwechslungspartner in
      eine Ampel-Gruppe ist eine Zeile.
    - **Die Klassen stehen einzeln nur in der AUSGEKLAPPTEN Legende**
      (Betreiberauflage). `_AmpelSection` steckt ohnehin nur im
      `_LegendPanel`; die 40-px-Schiene trägt ihr Urteil in der Form des
      Daumens, eine Aufzählung passt dort nicht hin. Ein Test prüft
      beide Richtungen.
    - **Der Nutzer kann Gruppen abwählen** (seit 1.142.0, Chips im
      Kartenfilter; Betreiber: „Default sollte alles an sein" und
      „auch die Fläche"). Die Auswahl liegt als `SpotFilter.classes`
      (leer = alle, wie bei den Arten) und wird über
      `selectedAmpelClassesProvider` EINMAL aufgelöst — Fläche,
      Legende, Nachlauf und Ampel-Filter lesen dieselbe Liste. Vier
      Dinge, die man wissen muss:
      - **Sie gehört in den FILTER, nicht zu den Ebenen-Schaltern.**
        Ein Filter muss sich auf der Karte melden (#154), und das tut
        nur, was in `describe()` steht — ein Ebenen-Schalter hätte
        diese Pflicht nicht, und die Karte zeigte dann eine engere
        Aussage, ohne es zu sagen. Der Chip sagt „Ampel:
        Steinpilz & Co." und bewusst nicht „nur …": Die Gruppe
        „Pfifferling" heißt wie die Art, und „nur Pfifferling" schreibt
        schon die Artenauswahl.
      - **Sie muss in den DATEINAMEN der Fläche** (`forestFillVariant`).
        Dieselbe Falle wie bei Klassenwahl, Fenster und Feinstufe: Die
        MapLibre-Strecke ist idempotent auf der URL, gleicher Name
        heißt altes Bild.
      - **Sie hängt NICHT am `ampelLevelGridProvider`.** Das Gitter
        trägt die Zutaten und ist die teure Hälfte (Isolate, 26
        Entpackungen); ausgewertet wird beim Abnehmer. Hinge die
        Auswahl im Gitter, würfe jeder Chip-Tipp es weg.
      - **Der Hinweis zieht mit.** `ampelScanOf` überspringt abgewählte
        Gruppen — sonst stünde „2 Spots" über einer Karte, auf der nach
        dem Tipp einer liegt. Die Chips selbst zeigt das Blatt nur bei
        eingeschalteter Vorschau: Ohne sie rechnet die Ampel nirgends,
        und der Artenliste fehlt der Platz.
  - **Die Einheit des Modells ist die KLASSE, nicht die Art** (seit
    1.137.0, Betreiber 2026-09-12). Eine Klasse ist ein
    Temperaturfenster; die beiden Stufenschwellen folgen daraus als
    Quantile der Score-Verteilung an Vergleichstagen und stehen NICHT
    mehr als zwei globale Zahlen da. Drei Dinge, die man wissen muss:
    - **Eine Schwelle gilt für EIN Fenster.** Der Austernseitling kommt
      mit den alten 0,5 auf 1,1 % günstige Fundtage, der Steinpilz auf
      58,4 % — ein eigenes Fenster ohne eigene Schwelle macht die Ampel
      dunkel, nicht besser. Umgekehrt sind die Schwellen von Arten, die
      sich ein Fenster teilen, nicht unterscheidbar; je Art ausgeliefert
      wären sie Rauschen in Konstantenform.
    - **Eine Klasse kommt erst nach einem HOLD-OUT hinein** — angepasst
      auf einem Teil der Daten, bestätigt auf Daten, die daran nie
      beteiligt waren. „Fällt in der Tabelle auf" reicht nicht; daran
      wäre die Pfifferling-Spur fast gescheitert. Hallimasch,
      Stockschwämmchen und Austernseitling haben gemessene Fenster und
      bleiben trotzdem grau.
      **Am 2026-09-13 sind zwei registrierte Erweiterungen daran
      gescheitert**, und beide Male auf dieselbe Weise: Geprüft wird das
      Fenster der KLASSE im Ausland (`--holdout AT,CH --class <key>`),
      nicht das jeder Art für sich — ausgeliefert würde ja ein Fenster
      für alle Mitglieder.
      - **Herbst-Holz** (11,625 °C): Hallimasch +0,018, Stockschwämmchen
        **−0,036** gegenüber 13 °C, beide Kontrollen sauber bei 0,501.
      - **Kalt** (−1,0 °C): Der Judasohr fällt mit −0,066 [−0,117,
        −0,013] unter die 13 °C zurück und passt sich in AT+CH auf
        12,0 °C an statt auf seine deutschen 1,5.
      Zwei Lehren, die bleiben: Ein Kalttest in Deutschland kann
      bestehen, ohne dass die Klasse REIST (`docs/pilzampel-kalttest.md`
      gegen `docs/pilzampel-kaltklasse-holdout.md`) — und ein sauber
      gemessener Fehlschlag EINES Mitglieds entscheidet nach „alle oder
      keine", auch wenn ein anderes ungemessen bleibt. Ein Bericht, der
      das als „noch nicht entschieden" führt, verschiebt die
      Entscheidung auf Daten, die nichts mehr ändern können.
    - **Die Schwellen altern.** Dieselbe 0,5 wurde vor 2019 an rund 30 %
      der Vergleichstage überschritten, seither an rund 20 % — die Ampel
      war im Feld still pessimistischer geworden, ohne Codeänderung. Wer
      sie anfasst, misst nach (`tool/ampel_validate.py --thresholds`,
      rechnet nur aus dem Cache) und schreibt das Datum dazu. Wie oft
      die Ampel „günstig" sagen soll, ist dabei eine
      Produktentscheidung und keine Messung; sie steckt im Quantil
      (80 %) und lautet „gleich häufig wie bisher".
    - **Die Klasse Holz & Winter hat seit 1.160.0 eine SECHSTE
      Konstante, „milder"** (#497, Labor 19–24, `docs/pilzampel-frost-plan.md`):
      das Mittel der Tagesminima der letzten fünf Tage minus das der
      Tage 6 bis 28, in °C, +0,042 je Grad. Fünf Dinge, die man wissen
      muss:
      - **Es ist die ABFOLGE, nicht der Frost.** Vor Fundtagen der
        Winterarten sind die letzten Tage milder und die Wochen davor
        kälter (Labor 21); Frosttage-Zählungen summieren genau das weg
        und trugen auf den Testblöcken nichts (Labor 19). Der Anlass
        war die Betreiberfrage „Minusgrade (Aktivierung) gefolgt von
        milderen Bedingungen?" — und die Regel dahinter: erst die
        vorhandenen Daten verstehen, dann eine Hypothese rechnen.
      - **Gewählt auf Training, bestätigt auf Test** (Betreiberregel
        vom 2026-09-21: Anpassungen nur auf den Trainingsblöcken DE +
        AT + CH, die Testblöcke bewerten). Auf den 1 970 Teststrata
        +0,007 [+0,001, +0,013] je Stratum gegen das
        Fünf-Konstanten-Logit, keine Art schlechter, Placebo mit
        permutiertem Merkmal −0,002 ▼ — der Preis EINES nutzlosen
        Parameters, und die Messlatte für jeden weiteren. Ein
        Zwanzigstel dessen, was die Klasse selbst gebracht hat.
      - **Die Stationstabelle trägt dafür 28 statt 20 Tage** (#506,
        `tool/spot_weather.py`, seit dem 2026-09-21). Eine ältere
        Tabelle füllt das Fenster nicht, und dann ist DIESE Klasse grau
        mit Grund („Tagesminima der Station: keine 28 vollständigen
        Tage"), klassenspezifisch wie ohne Bodenfeuchte — kein Mittel
        aus 20 Tagen, das wäre eine erfundene Beobachtung. Die Glocken
        rechnen weiter. `ampelMilderOf` verlangt 28 lückenlose Werte;
        die Höhenkorrektur kürzt sich in der Differenz heraus, die
        Minima gehen ROH hinein.
      - **Die Konstante 0 heißt „keine Reihe nötig"** (`AmpelLogit.needsMilder`):
        Herbsttrompete & Co. trägt sie, weil das Merkmal dort nie
        gemessen wurde, und rechnet ohne Minima weiter. Wer einer
        Klasse das Merkmal gibt, misst es für SIE — die Null ist keine
        Vorgabe.
      - **Alle sechs Konstanten sind neu gefittet, die Schwellen neu
        gezogen** (Kandidat K6_5 in `24-testbloecke-abfolge.md`;
        0,387 / 0,558 statt 0,454 / 0,606, `tool/ampel_logit_klasse.py
        --schwellen`). Der Python-Selbsttest hält Dart und Werkzeug
        Zahl für Zahl zusammen — deshalb kommen Werkzeug und Dart-Kern
        immer im SELBEN PR.
  - **Es gibt keinen dritten Modellkern.** `ampelScanOf` ruft dasselbe
    `ampelReadingFrom` wie das Spot-Blatt. Ein nächtlicher Server-Push
    hätte das Modell neben `ampel_model.dart` und
    `tool/ampel_validate.py` ein drittes Mal geführt — genau die Stelle,
    an der der geforderte Gleichlauf „Zahl für Zahl" unbemerkt
    auseinanderläuft. Der Preis dafür ist ehrlich: Der Hinweis erreicht
    einen beim ÖFFNEN der App, also wenn man ihn am wenigsten braucht.
  - **Ein EIGENER Schalter, nicht der der Ampel-Vorschau**
    (`ampelBannerEnabled`, ab Werk aus). Der Nachlauf braucht das
    Höhengitter, und dessen 3,4 MB beim Start auszupacken ist genau die
    Last, die 1.99.4 aus dem Startpfad genommen hat. Ohne Höhe rechnen
    wäre kein Ausweg: #279 verlangt, dass Fläche und Blatt gleich
    korrigieren, und in den Alpen sind das ~3 K — ein Banner, das dem
    Blatt widerspricht, wäre schlimmer als keins. **Die Reihenfolge der
    Prüfungen in `ampelScanProvider` IST die Zusage**: erst alle
    Schalter, dann das erste `ref.watch` auf ein Gitter. Beobachten ist
    laden. Ein Flow-Test hält es fest.
  - **Nur `guenstig` zählt.** „Verhalten" ist die Mehrzahl der Tage und
    damit ein Banner, das immer steht — und eines, das immer steht, sagt
    nichts mehr.
  - **Der Hinweis paart ZWEI Bedingungen, und zwar je ART** (seit
    1.138.0, Betreiber 2026-09-12): Die Klasse dieser Art muss günstig
    stehen UND ihre Saisonkurve muss sagen, dass sie jetzt überhaupt
    auftaucht. Ein Spot erscheint, sobald das für eine seiner Arten
    zusammenfällt; der Treffer trägt ihren Namen (`AmpelHit.species`).
    Vier Dinge, die man wissen muss:
    - **Beides über den SPOT zu fragen gäbe Unsinn.** An einer Stelle
      mit Pfifferling- und Steinpilzfunden stünde im Juli die Ampel des
      Herbstfensters (jüngster Fund), während das Saison-Tor wegen des
      Pfifferlings aufginge — zwei Aussagen über zwei Pilze, zu einer
      verrechnet. Gepaart wird deshalb innerhalb der Art.
    - **Die Saison ist ein TOR, kein Faktor.** In den Score darf sie
      nicht: Die Validierung vergleicht den Fundtag gegen Tage
      DERSELBEN Saison, dort kürzt sie sich heraus und ist prinzipiell
      ungeprüft. Als Bedingung „taucht die Art jetzt auf" ist sie eine
      Tatsache über GBIF-Meldungen und braucht keine Validierung.
    - **Banner, Filter und Blatt müssen dieselbe Menge zeigen.** Der
      Tipp setzt deshalb BEIDE Filter (`onlyAmpel` und `onlySeason`,
      beide im Chip genannt — #154), das Blatt zeigt seit 1.138.0 EINE
      ZEILE JE ART (`scanSpeciesOf`, geteilt mit dem Nachlauf) statt nur
      der des jüngsten Fundes, und der Monat kommt aus
      `currentMonthProvider` und nicht aus `DateTime.now()`.
    - **Die Saisonkurven sind damit AUSLIEFERUNGSRELEVANT geworden.**
      `lib/core/season_curves.g.dart` ist ein erzeugtes Asset
      (`tool/season_curves.py`, GBIF, kein Open-Meteo-Kontingent) — und
      seit es das Tor stellt, verschiebt jede Neuerzeugung, welche Spots
      der Hinweis meldet. Wer sie neu baut, misst nach, in wie vielen
      Art-Monaten `months[m] >= kSeasonNowThreshold` kippt, und schreibt
      die Zahl in den PR. Beim Lauf vom 2026-09-12 war es **1 von 1080**
      (Schwefelporling im März, 14 → 15).
    - **Eine Art ohne genug Material kann die Kurve ihrer
      Verwandtschaft BORGEN** (seit 1.139.0): `curveFrom` (Gattung,
      wissenschaftlich) plus `curveFromName` (deutsch, für den Satz) in
      `mushroom_species.dart`; das Werkzeug fragt GBIF nach der Gattung
      und schreibt `borrowedFrom` in die Kurve. Drei Dinge:
      - **Das ist NICHT `isGenus`.** Dort ist der deutsche Name selbst
        ein Sammelbegriff („Rotkappe"), die Kurve gehört also dem, was
        eingetragen wurde. Beim Borgen meint der Name genau eine Art —
        die Anzeige sagt deshalb „Saison nach verwandten Arten: …“ statt
        „(mehrere ähnliche Arten)“.
      - **Es geht nur, wenn die Verwandtschaft eine gemeinsame Saison
        hat.** *Hericium* ja (1147 Meldungen, alle Stachelbärte);
        *Amanita* nein — 60 448 Meldungen, aber Frühjahrs- UND
        Herbstarten gemischt, für den Frühjahrsknollenblätterpilz zeigte
        die Kurve in die Gegenrichtung. Der bleibt ohne, und bei einem
        tödlich giftigen Pilz ist das die richtige Richtung.
      - **`curveFrom` ohne `curveFromName` bricht den Bau ab**, und
        `test/species_test.dart` hält Artenliste und Asset in beide
        Richtungen zusammen: keine geborgte Kurve ohne Quelle, keine
        Quelle an einer Kurve, die nicht borgt.
    - **Im Zweifel zeigen** — die Regeln des Saison-Filters (#414)
      gelten hier genauso: Eine Art ohne Kurve verdeckt nichts (`null`
      heißt „wir wissen es nicht"), ein Spot ohne eingetragene Art
      bleibt die Gildenfrage. Und die Wortleiter im Blatt („Hauptzeit /
      Nebenzeit / Randzeit / kaum gemeldet") hängt unten an
      `kSeasonNowThreshold` — sonst stünde dort „außerhalb", während das
      Banner für dieselbe Art anschlägt.
  - **Der Wortlaut trägt das Urteil.** Die Ampel bewertet BEDINGUNGEN,
    nie Vorkommen. Also „2 Spots · **Ampel günstig (experimentell)**",
    kein „geh jetzt", kein Ausrufezeichen.
    **Geändert am 2026-09-12** (vorher „stünde die Ampel günstig"): Der
    Konjunktiv war mit der durchgefallenen Arten-Kontrolle begründet —
    und die ist aufgelöst, sie war an ihrer AUSWAHL gescheitert
    (`docs/pilzampel-artenfenster-messung.md`). Er tat ohnehin nicht,
    was er sollte: „Ampel günstig" behauptet nichts über Pilze, sondern
    sagt, was die Ampel zeigt. Den Vorbehalt trägt „experimentell", und
    der steht deutlicher da, wenn er nicht um Platz ringt.
    **Was bleibt:** „experimentell" ist ein eigenes Stück im Chip, nicht
    Teil des Textes — dort würde es als Erstes abgeschnitten. Lieber ein
    gekürzter Ortsname als ein gekürzter Vorbehalt.
  - **Das X schaltet nur für die SITZUNG stumm** (#425, seit 1.128.1) —
    vorher bis Tagesende, mit der Begründung „morgen sind es andere
    Daten und damit eine andere Aussage". Die stimmt weiter; ungeprüft
    blieb der Preis. Ein Tipp nahm das Feature für bis zu 24 Stunden
    weg, nirgends stand, dass eine Stummschaltung läuft, und zurück
    führte kein Weg außer Warten — während der Schalter im Profil sich
    weiter als „an" las. Gemeldet als „ich bekomme kein Banner mehr",
    und zwar vom Betreiber selbst: Wer nicht erkennen kann, dass er es
    abgeschaltet hat, hält es für kaputt. Es war die ZWEITE Meldung
    dieser Form (#349: „das Banner schaltet sich beim Antippen selbst
    stumm").
    Die Sitzungsgrenze macht einen Rückweg in der Oberfläche
    überflüssig — der nächste Start IST der Rückweg. Deshalb steht der
    Zustand jetzt als `bool` in `ampelBannerMutedProvider` und nicht
    mehr in den Einstellungen; der Prefs-Schlüssel
    `ampel_banner_dismissed_until` liegt auf Bestandsgeräten weiter
    herum und wird nie wieder gelesen (Vermerk in `settings.dart`).
  Der gebündelte `rainCoursesProvider` ist der Provider zum längst
  vorhandenen `rainCoursesFrom` (1.99.3): 19 Spots kosten 26
  Dekodierungen statt 494. Sein Familienschlüssel ist eine
  zusammengefügte Zeichenkette, keine Liste — zwei inhaltlich gleiche
  Listen sind für `==` verschieden.
- **Erklär-Tour und Kontexthilfe** (#350, seit 1.107.0/1.108.0): Zwei
  Bausteine, bewusst getrennt. **A** ist Kontexthilfe ohne jede
  Maschinerie — leerer Kartenzustand, Leergang-Erklärung am frischen
  Spot, `lib/features/help/help_screen.dart` als Kurzanleitung mit den
  ECHTEN Symbolen (kein `.md`-Asset: das läge im Binary, gälte dem
  Version Guard aber als `*.md` und wäre damit von der Bump-Pflicht
  ausgenommen — dieselbe Falle wie bei `CHANGELOG.md`). **B** ist die
  geführte Tour (`lib/features/help/map_tour.dart`), seit 1.205.0 ein
  Skript auf der **Hinweis-Maschine** (`lib/features/coach/coach.dart`,
  #596). Die erste Fassung schnitt vergrößerte runde Löcher je Knopf —
  seit die Werkzeuge in EINER Leiste sitzen, griffen die in den
  Nachbarknopf, und sie zeigte nur, WO etwas ist (PWA-Screenshots des
  Betreibers, 2026-09-24). Jetzt FÜHRT sie vor: Der lange Druck öffnet
  das Kontextmenü, die Ebenen öffnen ihr Blatt („wichtig ist mir, dass
  das Kontextmenü gezeigt wird, nicht nur der erste Button"). Sechs
  Dinge, die man wissen muss:
  - **Die Maschine liegt über allem** (`MaterialApp.builder`), also über
    Dialogen und Blättern, und schluckt jeden Tipp — eine Vorführung
    löst nie etwas aus. Deshalb meldet sie sich beim **Zurück-Verteiler
    des Routers** mit Vorrang an, solange sie läuft (sonst verließe
    Zurück auf der Karte die App), und danach wieder ab (sonst sperrte
    sie ein). Beide Richtungen stehen im Flow-Test.
  - **Anker und Szenen haben Kennungen** (`MapCoach`). `CoachAnchor`
    meldet ein Widget an, der Screen meldet Szenen an (Menü, Blatt), und
    eine Szene gibt ihren Schließer zurück. Die Maschine schließt beim
    Szenenwechsel und am Ende immer; das Menü meldet dabei `null`, also
    keine Aktion. Die Szenen rufen `showMapContextMenu`/
    `showMapLayersSheet` DIREKT, nicht `_openContextMenu`/`_openLayers`,
    die das Ergebnis auswerten würden.
  - **Gemessen wird über die ganze Transformation** (`getTransformTo`)
    und bei jedem Bild — die Leiste steckt in einem `FittedBox`, ein
    Blatt fährt animiert herein. **Im Karten-Test wird die Leiste nie
    verkleinert** (auch bei 360×560 nachgemessen: 44×44), deshalb steht
    die Zusage in `test/coach_test.dart` mit einem `Transform.scale`.
  - **Aussparung in Form des Elements, Ring auf dem gemeinten.** Bei der
    Leiste ist sie ganz ausgespart, der Ring sitzt auf dem Knopf; im
    ersten Schritt nur um „Neuer Spot", sonst wäre er ein Kasten von der
    Bildmitte bis in die Ecke. Fehlt ein Ziel ~2 s lang (Menü an der
    Tour vorbei geschlossen), geht es weiter statt ins Leere.
  - **`FakeSettings.mapTourSeen` steht auf `true`, die App auf `false`.**
    Andersherum bekäme jeder Bestandstest die Tour übergestülpt — in der
    Gegenprobe gemessen: 13 Tests brechen. Muster wie `lastFindSeenAt`.
  - **Überspringen und Zurück zählen wie Durchsehen.** Gemerkt wird über
    den Notifier von `mapTourSeenProvider`, nicht über den `ref` des
    Aufrufers — aus der Kurzanleitung gestartet, ist der beim Ende
    vielleicht schon abgebaut.
  Der Merker ist gerätelokal (Betreiber, 2026-08-29); nach einer
  Neuinstallation läuft sie wieder, und das ist angenommen.
  **Zurückgesetzt für alle in 1.208.0** (Betreiber, 2026-09-25): neue
  Schlüssel für Karten-Tour (`map_tour_seen_2`), Reiter-Touren,
  Neuheiten-Stand und „Neu"-Punkte. Der alte Tour-Merker wird weiter
  GELESEN (`legacyMapTourSeen`), aber nur für die Rückblick-Erkennung —
  sonst hielte die App nach dem Zurücksetzen jeden für eine
  Neuinstallation, und der Rückblick fiele weg (Flow-Test mit
  Gegenprobe). Wer wieder zurücksetzt: dieselbe Trennung, und
  `LAST_RESET` in `tool/highlights_preview.py` nachziehen — aber NUR,
  wenn auch der Neuheiten-Stand zurückgesetzt wird.
  **Noch einmal in 1.210.1, nur die Touren** (Betreiber, 2026-09-25,
  nach Startseiten und Beispielen): `map_tour_seen_3`,
  `seen_coach_tours_3`. Neuheiten-Stand und „Neu"-Punkte bleiben, also
  bleibt auch `LAST_RESET`. `legacyMapTourSeen` liest seither ALLE
  früheren Tour-Schlüssel (`_legacyMapTourSeenKeys`) — beim nächsten
  Mal kommt der dann alte dazu, sonst hieße ein Nutzer von 1.208 bis
  1.210 „Willkommen" (`test/settings_tour_reset_test.dart`).
  **Startseiten, Willkommen und die Kette** (seit 1.209.0, Betreiber
  2026-09-25: „man öffnet die App und es geht sofort los"). Jede Tour
  beginnt mit einer Startseite (`CoachStep.art`, Bilder in
  `tour_intro_art.dart`): Bild, WOZU, dann die Wahl. Beim ersten Start
  ist es die Willkommensseite, danach die Karten-Tour mit einem Schritt
  zur Leiste unten, danach fragt JEDE Grenze „Weiter mit den Spots?"
  (`startWelcomeTour`). Sechs Dinge, die man wissen muss:
  - **„Nicht jetzt"/„Später" ist kein Gesehen** (`CoachNotifier.decline`,
    `onDecline`): Die Tour fragt beim nächsten Start wieder, JEDES Mal
    (Betreiber); in derselben Sitzung nicht bei jedem Reiterwechsel
    (`declinedTabToursProvider`, nur im Speicher). Zurück auf der
    Startseite heißt „Nicht jetzt", ein Tipp daneben tut nichts.
  - **Die Willkommens-Tour hat keinen Weg in die Kurzanleitung am Ende**
    — sonst liefe die Kette gleichzeitig in den nächsten Reiter.
  - **Bestandsnutzer sehen nicht „Willkommen"** (`kReturningIntro`, über
    `legacyMapTourSeen`) — nach dem Zurücksetzen in 1.208.0 wäre das
    falsch.
  - **Tippsperre, 400 ms nach jedem neuen Schritt** (`_guarded`, Zeit des
    Takts, nicht der Uhr — im Test wäre `DateTime.now` echt). Feldmeldung
    „scheint einen Schritt direkt zu überspringen": Die neue Blase steht
    woanders, ein nachwackelnder Finger traf ihr „Weiter". Tests müssen
    deshalb nach dem Erscheinen eines Schritts einen Moment warten.
  - **Ein fehlendes Ziel wird gesagt, nicht übersprungen** — bis 1.208.x
    ging die Tour nach ~2 s still weiter, auf einem langsameren Gerät
    sah das wie ein übersprungener Schritt aus.
  - **Auf der Startseite scrollt nur der Inhalt**, die Wahl bleibt immer
    im Bild, und das Bild schrumpft mit dem Schirm — auf einem kurzen
    Schirm lag „Tour starten" sonst unter dem Rand (im Test gesehen).
  Zähler und „Los geht's" zählen die Startseite nicht mit; Vorführungen
  übernehmen Schritte über `tourSteps` (ohne Startseite).

  **Beispiele für leere Konten** (seit 1.210.0, `tour_examples.dart`,
  Betreiber: „er sollte ja dennoch einen Eindruck bekommen"). Ohne Spot
  erklärte die Spot-Tour bis dahin nur das Suchfeld — über die Kette lief
  sie auch ohne Inhalt. Jetzt zeigen Spots und Buddys während ihrer Tour
  eine Beispielzeile, ein Beispiel-Blatt, einen Beispiel-Buddy und eine
  Beispiel-Galerie. Drei Regeln:
  - **Gezeichnet, nie gespeichert** — keine `Spot`-, `Find`- oder
    `Friendship`-Objekte, kein Provider, kein Cache. Als Modell käme ein
    Beispiel-Fund in Statistik, Ampel und GPX-Export an.
  - **Immer „Beispiel"** (`TourExampleBadge`), auch für den
    Bildschirmleser.
  - **Nur während der Tour und nur, wo Echtes fehlt**
    (`CoachScript.examples` → `coachExamplesProvider`). Die Anker sind
    dieselben wie an der echten Zeile. `examples` gehört nur an Skripte
    MIT Startseite: Die Beispiele erscheinen ein Bild nach dem Start, und
    ein erster Schritt mit `requires` fiele sonst sofort weg.
  Die Spot-Tour wartet deshalb nicht mehr auf einen Spot (`ready`); der
  Wächter gegen „Tour fällt über die Karte" ist davon unberührt und hat
  seinen Test behalten.

  **Kurze Touren je Reiter** (seit 1.206.0, `lib/features/help/tab_tours.dart`):
  Spots, Pilze und Buddys, auf derselben Maschine, beim ERSTEN Besuch
  des Reiters. Vier Dinge, die man wissen muss:
  - **Sie startet nur, wenn der Reiter SICHTBAR ist** (`TickerMode`, den
    go_router für verdeckte Reiter abschaltet). Die Reiter bleiben nach
    dem ersten Besuch im Baum, und die Spot-Liste lädt gern nach, während
    man auf der Karte ist — dann fiele die Tour über die Karte. Ein
    Flow-Test hält es fest, die Gegenprobe ist gemessen.
  - **Sie wartet auf Inhalt** (`ready`): ohne Spot keine Spot-Tour, und
    sie bleibt dann ungesehen. Einzelne Schritte an Dingen, die nicht
    jeder hat, tragen `requires` und fallen sofort weg — ein Anker ohne
    Fläche (`SizedBox.shrink`) zählt als fehlend.
  - **Schritttitel dürfen nicht wie etwas auf dem Schirm heißen.** „Buddy
    finden" ist das Suchfeld; mit dem gleichen Titel prüfte der Test das
    Feld statt der Blase. Zum zweiten Mal passiert (vorher „Was ist hier?").
  - **Die Blase wird erst gemessen, dann gesetzt** (`_BubbleLayout`):
    neben ihr Ziel, bei einem hohen schmalen Ziel (die Leiste auf
    360×640) DANEBEN, und ragt sie trotzdem hinaus, wird sie ins Bild
    geschoben — dann ohne Pfeil. Bis 1.205.0 lag sie im Leisten-Schritt
    bei y = −27 und auf der Artseite unten außerhalb, „Weiter" war nicht
    zu erreichen. Der Test prüfte nur „deckt nichts zu", und das tut eine
    Blase außerhalb nie; seither prüft jeder Tour-Test, dass sie ganz im
    Bild liegt. Eine Regel VOR dem Messen („zu wenig Platz ⇒ an den
    Rand") war der erste Versuch und schob sie auch dann aufs Ziel, wenn
    sie gepasst hätte.
  Gemerkt wird in `seenCoachTours` (die Karten-Tour behält
  `mapTourSeen`); `FakeSettings` setzt ab Werk alle, Muster wie bei der
  Karten-Tour.
  **Die Hand** (`FingerPainter`, seit 1.206.0) ist gezeichnet: Zeigefinger
  mit Nagel, eingerollte Finger, Daumen, grüner Ärmel. **Von hinten nach
  vorn gemalt, jedes Teil mit eigener Kontur**, die Handfläche zuletzt
  und ohne Kontur (sie deckt die Fingerenden zu), den Außenrand zieht der
  Umriss aller Teile. Der erste Ansatz — ein Umriss mit eingeritzten
  Trennlinien — zeichnete verdeckte Linien, und der Daumen sah erst
  gebrochen, dann aufgeklebt aus (Betreiber mit Zeige-Icon als Vorlage,
  2026-09-25). Wer die Form ändert: groß rendern und ANSEHEN. Der Ablauf steht
  rein in `FingerMotion` (herankommen, drücken, abheben; beim Wischen von
  rechts nach links), damit ein Test ohne Pixel prüfen kann, dass AUF dem
  Ziel gedrückt wird.
  Nebenbefund aus #350: Der einzige Erklärsatz, den die App davor hatte
  (im Profil, „halte auf der Karte gedrückt"), wies auf eine Geste, die
  seit #210 abschaltbar war und **ab Werk aus** stand. Seit #483 stimmt
  der Satz wieder — er steht jetzt in der Kurzanleitung.
- **Neuheiten und „Entdecken"** (#596, seit 1.204.0,
  `lib/features/highlights/`): EINE Liste (`kFeatureHighlights`), zwei
  Anzeigen — das Blatt nach einem Update (höchstens drei Highlights
  untereinander, jüngste zuerst) und die Seite „Entdecken" (alles,
  auch die Tipps).
  Die Tour bleibt daneben und hat eine andere Aufgabe: Das Blatt sagt,
  WAS es gibt, die Tour zeigt, WO es ist. Fünf Dinge, die man wissen
  muss:
  - **Wer eine Funktion baut, bringt ihren Eintrag im selben PR mit** —
    Highlight, wenn sie ins Blatt gehört, sonst Tipp. Verankert an drei
    Stellen (seit 1.208.0), weil „steht in CLAUDE.md" allein nicht
    trägt: die PR-Vorlage (`.github/pull_request_template.md`, erster
    Haken), die Vorschau in der Run-Summary von `promote.yml`
    (`tool/highlights_preview.py`: was das Blatt nach dem Update zeigt,
    Warnung bei keinem Highlight — kein Tor, manche Stände bringen ehrlich
    nur Korrekturen) und der Skill `pilz-release` für den Ablauf der
    Beförderung. Die Vorschau kennt den Rückblick: Wer von einem Stand vor
    1.204.0 kommt, hat keinen Merker und bekommt ihn — dort ist „kein neues
    Highlight" kein Befund. Kuratiert wird
    nicht bei der Beförderung: Stehen mehr als drei an, zeigt das Blatt
    die jüngsten, der Rest wartet in „Entdecken".
    `test/feature_highlights_test.dart` prüft Kennungen, `since` gegen
    `pubspec.yaml` und die Textlänge, der Flow-Test, dass jedes Ziel
    eine Route ist.
  - **Rückwirkend geht es nur über `mapTourSeen`.** Vor 1.204.0 hat kein
    Gerät seine Version gemerkt (`highlightsSeenVersion` ist dort
    `null`). Tour gesehen ⇒ Bestandsnutzer ⇒ einmal der Rückblick, mit
    `kRecapLead` an der Spitze (dort wäre „die jüngsten" die falsche
    Regel). Tour nicht gesehen ⇒ frisch installiert ⇒ Version merken,
    nichts zeigen. **Gemerkt wird schon beim ERSTEN Start**, auch wenn
    Haftungshinweis oder Tour laufen — sonst hielte sich eine frische
    Installation nach der Tour für einen Bestandsnutzer. Nur ZEIGEN
    wartet dann auf einen ruhigen Start (keins der beiden, keine
    laufende Pilztour).
  - **Gemerkt wird VOR dem Zeigen**, und nie ein älterer Stand über
    einen jüngeren (Rückschritt vom Vorabkanal). Ein weggewischtes
    Blatt kommt nicht wieder; verpasst ist nichts, „Entdecken" hat es.
    **Das Blatt ist EINE Seite, alle Einträge untereinander** (seit
    1.204.1, Muster der „Neu in …"-Seiten). 1.204.0 blätterte mit
    „Ausprobieren" je Seite, und wer mittendrin antippte, verlor den
    Rest — im Feld gemeldet. Eine „Weiter ansehen"-Leiste am Ziel war
    gebaut und ist verworfen: Sie flickte einen Fall, den der übliche
    Aufbau gar nicht erst hat. Wer das Blatt wieder zum Blättern macht,
    muss „gesehen" je angezeigter Seite merken, nicht beim Öffnen.
  - **Eine Zeile im Blatt führt es VOR** (seit 1.208.0): Sie startet die
    Vorführung aus `highlight_demos.dart`, die selbst an die Stelle
    wechselt. Ohne Vorführung bleibt es beim Sprung.
  - **„Animationen entfernen" und Bildschirmleser** (seit 1.208.0): Ring
    und Hand stehen dann still (`gestureStillFrame`, dasselbe Bild wie in
    „Entdecken"), der Pilz im Bild schaukelt nicht. Während einer Tour
    blendet `CoachSemanticsGate` (in `app.dart` um den Inhalt UNTER der
    Überlagerung) alles darunter für TalkBack aus — dort nimmt ohnehin
    nichts einen Tipp an —, und die Blase ist eine `liveRegion`, ein
    neuer Schritt wird also angesagt. `BlockSemantics` in der Überlagerung
    reichte nicht, es wirkt nicht über die Grenze zum Navigator. Im Test
    `find.semantics.byLabel`, nicht `find.bySemanticsLabel`: Letzteres
    findet auch ausgeblendete Knoten.
  - **Bilder aus Widgets** (`HighlightArt`: das echte Knopfsymbol plus
    ein schaukelnder Pilz-Buddy), keine Screenshots — die veralten mit
    jeder Oberflächenänderung —, kein Lottie.
  - **„Zeig es mir" (seit 1.207.0, `highlight_demos.dart`)**: je Eintrag
    eine Vorführung auf der Hinweis-Maschine, und sie endet IN der
    Funktion (Blatt, Menü, Dialog, Seite). **Wer einen Eintrag anlegt,
    bringt seine Vorführung mit** — `highlight_demos_flow_test.dart`
    verlangt eine je Kennung und fährt JEDE aus „Entdecken" durch: jeder
    gezeigte Schritt findet sein Ziel, die Blase liegt im Bild, danach
    ist nichts offen. Was dafür in die Maschine kam:
    - **Szenen schachteln** (`a/b`): Der Meldedialog liegt AUF der
      Artseite; die äußere bleibt offen, geschlossen wird von innen.
    - **Szenen dürfen sich spät anmelden** (`retryScenes`, je Bild) —
      ihr Besitzer entsteht oft erst, wenn die äußere steht.
    - **`scrollIn`**: Ziele weit unten in einer `ListView` (Ampel-
      Schalter im Profil, Meldeknopf der Artseite) sind nicht gebaut,
      bis man hinscrollt; die Maschine scrollt die genannte Liste weiter,
      bis der Anker da ist.
    - **`unless`** als Gegenstück zu `requires`: der Ersatzschritt
      („erst einen Buddy finden"). Zähler und „Los geht's" rechnen über
      die Schritte, die WIRKLICH laufen.
    - **`reserve`**: Zwischen Tipp und Start (drei Bilder, damit der
      Zielreiter seine Anker meldet) ist die Maschine belegt, und die
      Reiter-Tour weicht für den Rest dieses Besuchs.
    Eine Falle beim Bau: Ein Dialog-`builder`, der über `ref` liest,
    baut beim Schließen noch einmal — schließt die Vorführung erst den
    Dialog und dann die Seite darunter, ist dieses `ref` schon tot. Werte
    vor `showDialog` lesen.
  - **`FakeSettings.highlightsSeenVersion` steht auf `9999.0.0`**, die
    App auf `null`. Andersherum bekäme jeder Bestandstest das Blatt über
    die Karte gelegt; Muster wie `mapTourSeen`.
- **Der Reiter „Pilze"** (seit 1.153.0): das Artenverzeichnis — je
  Ampel-Gruppe ihre Mitglieder, je Art die Mini-Saisonkurve, hervorgehoben,
  was jetzt Saison hat. Drei Dinge, die man wissen muss:
  - **Der Inhalt ist GERECHNET, nicht geschrieben**
    (`lib/features/species/species_catalogue.dart`, ohne Widgets): Gruppen
    aus `ampelClasses`, Mitglieder aus `ampelSpeciesClass`, Kurven aus
    `season_curves.g.dart`, Belege aus `ampelEvidenceBySpecies`. Wer eine
    Klasse oder Art hinzufügt, muss hier NICHTS tun —
    `test/species_catalogue_test.dart` verlangt, dass jede bekannte Art
    genau einmal darin steht.
  - **Eine Schwelle, ein Balken-Widget, eine Wortleiter.** Hervorhebung ist
    `kSeasonNowThreshold`; die Balken sind `SeasonBars`
    (`lib/core/widgets/`), die auch das Spot-Blatt zeichnet; die Wörter
    kommen aus `seasonShareWord`. Der Reiter darf der Karte nie
    widersprechen — er ist ihre Legende.
  - **Der Filter „Nur jetzt Saison" verdeckt nichts, was er nicht weiß**:
    Arten ohne Kurve bleiben stehen (#414-Regel), leere Gruppen behalten
    die Überschrift.
  - **Die Suche (seit 1.164.0) trifft über drei Namen** — Hauptbezeichnung,
    Zweitnamen und den wissenschaftlichen —, alle drei durch
    `foldSpeciesName` (#395). `speciesSearch` steht widgetfrei im Katalog.
    **Sie macht DENSELBEN Zweischritt wie `suggestSpecies` im Blatt
    „Fund eintragen"**: erst Teiltreffer, und nur wenn der leer ausgeht,
    der Tippfehler-Ausgleich über den Editierabstand. Der erste Entwurf
    ließ den Rückfall weg („ein Filter, der aufweitet, ist keiner") —
    das Argument trägt genau dort nicht, wo der Rückfall greift: Ist
    nichts gefunden, gibt es nichts aufzuweiten, und die Alternative war
    „Keine Art mit diesem Namen", also der Satz, aus dem #395 entstanden
    ist (Betreiber, 2026-09-21). `speciesTypoTolerance` und
    `nearContainsDistance` liegen deshalb seither in
    `mushroom_species.dart` statt privat bei den Vorschlägen.
    Zwei Auflagen dabei: **Die Oberfläche muss sagen, dass sie rät**
    („Meintest du …?") — ein geratener Treffer, der aussieht wie ein
    gefundener, ist eine Behauptung über die Eingabe. Und **nur der
    beste Abstand** wird angeboten: Bei „Steipilz" liegen acht Arten in
    der Toleranz und drei auf dem besten Abstand.
    Zwei Unterschiede bleiben: **leere Gruppen fallen weg**, anders als
    beim Saison-Filter, der seine Überschrift behält, um „keine" zeigen
    zu können; und die **Gesamtzahl im leeren Zustand ist gezählt**,
    nicht geschrieben.
    Nebenwirkung für Tests: Ein `TextField` bringt einen eigenen
    `Scrollable` mit, der im Reiter ist also nicht mehr der einzige.
    `species_detail_flow_test.dart` sucht seither, statt zu scrollen —
    kürzer UND eindeutig.
  - **Je Art eine Seite darunter** (#511, seit 1.162.0): Route
    `/pilze/:name` als Unterroute wie die Seiten des Profil-Tabs,
    gerechnet in `speciesDetailFor` (weiter widgetfrei), gezeichnet von
    `species_detail_screen.dart`. Sie zeigt, wofür in der Zeile kein
    Platz war — wissenschaftlicher Name, Zweitnamen („auch: …", derselbe
    Wortlaut wie im Spot-Blatt), die volle Kurve MIT Monatsbuchstaben,
    Gruppe samt Fenster und Belegen, eigene Funde und die
    GBIF-Meldungen. Fünf Dinge, die man wissen muss:
    - **Der Satz zur Kurve steht seither in `season_curves.dart`**
      (`seasonSentence`/`seasonSourceLine`), nicht mehr im Spot-Blatt:
      Zwei Fassungen wären zwei Meinungen darüber, wie stark eine
      GEBORGTE Kurve einzuschränken ist — und bis 1.161.0 sagte der
      Reiter „Pilze" davon gar nichts, die Kurve des Igelstachelbarts
      las sich dort als Aussage über ihn.
    - **Hier werden die 0,6 MB der Fundorte ausgepackt, in der Liste
      nicht.** Beobachten ist laden; eine bewusst geöffnete Seite darf
      das (wie das „Was ist hier?"-Blatt), ein Reiterwechsel nicht. Ein
      Flow-Test zählt die Aufrufe der Lade-Naht.
    - **`GbifFinds.totalsFor` unterscheidet „0 Meldungen" von „nicht im
      Asset".** Eine Art ohne wissenschaftlichen Namen wird bei GBIF nie
      abgefragt — das ist eine Lücke bei uns, keine bei den Meldern, und
      die Seite sagt es anders. (Heute trägt jede der 91 Arten einen;
      der Zweig ist gemessen unbenutzt und bleibt trotzdem, weil `sci`
      bewusst nullbar ist.)
    - **Ein Weg auf die Karte, nicht zwei.** `showOnlySpecies` SETZT den
      Artenfilter, und der wirkt auf eigene Spots UND die
      GBIF-Scheiben; zwei Knöpfe wären zwei Antworten auf dieselbe
      Frage. Reihenfolge wie in der Spot-Liste: erst der Reiter, dann
      der Filter.
    - **Keine Bestimmungshilfe und keine Fotos** — und ein Satz am Fuß,
      der das sagt. Eine Detailseite weckt die Erwartung, die eine
      Listenzeile nicht weckt.
  - **Essbar oder giftig** (`lib/core/species_edibility.dart`, seit
    1.163.0): eine Stufe je Art, sechs Stufen, dazu Freitext. Vier
    Dinge, die man wissen muss:
    - **Die Fehlerrichtung ist nicht symmetrisch, und der Code richtet
      sich danach.** Ein zu vorsichtiges „ungenießbar" kostet eine
      Mahlzeit, ein zu großzügiges „essbar" eine Leber. Deshalb: im
      Zweifel die Warnung; `Edibility.umstritten` für die Fälle, in
      denen die Literatur uneins ist (die DGfM führt dafür selbst die
      Kategorie „uneinheitlich beurteilte Arten"); **kein Grün und kein
      Häkchen für „Speisepilz"** (`isWarning`) — Grün läse sich als
      Freigabe; und in der LISTE nur die beiden giftigen Stufen
      (`warnsInList`), weil knapper Platz der teuren Fehlerrichtung
      gehört.
    - **Die Tabelle ordnet NAMEN Stufen zu, nicht Pilzen.** Wer sich bei
      der Bestimmung irrt, liest die Einstufung des falschen Pilzes —
      `kEdibilityDisclaimer` sagt das unter jeder Stufe, einmal
      formuliert.
    - **Prüfbar ist nur das Drumherum.** Ob der Grünling giftig ist,
      steht in der Literatur und nicht in Dart. `test/species_edibility_test.dart`
      prüft stattdessen die Pflegefehler: jede bekannte Art hat genau
      einen Eintrag (eine neue Art erzwingt damit eine Entscheidung,
      statt still ohne Einstufung zu erscheinen), keine Karteileichen,
      Zweitnamen erben, `umstritten` trägt immer eine Begründung, und
      die tödlichen stehen als tödlich da.
    - **Der Freitext steht nur, wo die Stufe allein in die Irre
      führt**: tödliche Verwechslungen, Arten, die jahrzehntelang als
      Speisepilz galten, und deutsche Namen, die eine Gattung meinen.
      Eine Bemerkung an jeder Zeile wäre Lärm, in dem die wichtigen
      untergehen.
  - **Verwechslungspartner** (`lib/core/species_lookalikes.dart`, seit
    1.165.0): je Paar ZWEI Einträge, einer je Richtung. Vier Dinge, die
    man wissen muss:
    - **Die Beziehung ist symmetrisch, und ein Test erzwingt das.** Wer
      auf der Seite des Giftpilzes landet, ist oft gerade der, der dort
      nicht hinwollte; eine einseitige Warnung findet nur, wer schon
      weiß, wonach er sucht.
    - **Der Unterscheidungssatz steht je RICHTUNG.** „Der Perlpilz
      rötet" ist beim Perlpilz eine Bestätigung und beim Pantherpilz ein
      Ausschluss. Ein Test verlangt, dass die beiden Sätze eines Paares
      verschieden sind — wortgleich hieße, eine Seite wurde nur kopiert.
    - **Jede Zeile trägt die Einstufung des PARTNERS** und führt auf
      dessen Seite. „Gifthäubling" allein sagt nichts, „Gifthäubling ·
      Tödlich giftig" beantwortet die Frage, wegen der man hinsieht.
    - **Leer heißt „keine bekannt", nicht „keine vorhanden"** — deshalb
      fällt der Abschnitt bei einer Art ohne Partner ganz weg statt als
      leere Überschrift dazustehen, und unter jeder vollen Liste steht,
      dass sie nicht vollständig ist.
    - **Die harmlosen Partner klappen ein, die warnenden nie** (seit
      1.172.0). Drei Bedingungen, jede mit eigenem Grund: Die Art
      selbst darf nicht warnen (auf der Seite eines Giftpilzes sind die
      Speisepilz-Partner der Punkt), es muss überhaupt eine Warnung
      geben (sonst nimmt das Einklappen nur den Inhalt weg — die vier
      Reizker sind genau dieser Fall), und es muss beides geben. Anlass
      war der Steinpilz mit sechs Partnern, bei dem die harmlosen die
      Warnung aus dem ersten Bildschirm drückten. Dieselbe Trennlinie
      wie in `confusionHint`.

    - **Der Einzeiler beim Eintragen nennt nur, was etwas ändern
      kann** (seit 1.171.0). Ist die eingetippte Art selbst harmlos,
      fallen die harmlosen Partner weg. Anlass: Mit der
      Steinpilz-Gruppe bekam der Steinpilz sechs Partner und die Zeile
      158 Zeichen, mit dem Satansröhrling als zweitem von sechs — eine
      Warnung, die man suchen muss. Bei einer Art, die SELBST warnt,
      bleibt alles stehen; dort erklärt der Speisepilz-Partner erst,
      warum jemand sie im Korb hätte. Die volle Liste trägt die
      Artseite.
    - **iNaturalist ist als Fundquelle brauchbar, als Beleg nicht.**
      `identifications/similar_species` liefert, wie oft eine
      Bestimmung von A nach B korrigiert wurde — daraus kamen die
      beiden echten Lücken (Fliegenpilz ohne jeden Partner, Perlpilz
      ohne den Grünen Knollenblätterpilz). Von 197 gemeldeten Paaren
      waren die meisten Rauschen: „Marone ↔ Steinpilz" mit 180
      Korrekturen sind Anfängerfehler zwischen Arten, die sich nicht
      ähneln. Was aus dieser Quelle kommt, wird gegen Literatur
      geprüft, bevor es in die Tabelle geht.

    Geprüft wird außerdem, dass jeder genannte Partner eine bekannte Art
    ist (ein Verweis ins Leere wäre schlimmer als keiner), dass die acht
    tödlichen Paare drinstehen, und dass jede giftige Art mit Partnern
    mindestens einen Speisepilz nennt — sonst erklärt die Warnung nicht,
    warum jemand sie überhaupt im Korb hätte.
  - **Bestimmungsmerkmale** (`lib/core/species_features.dart`, seit
    1.166.0): sechs Felder je Art — Hut, Unterseite, Stiel, Fleisch,
    Geruch, Vorkommen. Vier Dinge, die man wissen muss:
    - **Die Pflichtmenge ist JEDE bekannte Art** (seit 1.169.0).
      Vorher war sie enger — Arten mit Verwechslungspartner plus die
      giftigen —, und sie hat am falschen Ende gemessen: am Giftpilz
      statt am Sammler. Die vier Reizker sind Speisepilze ohne
      eingetragenen Partner und fielen durch beide Siebe; ihre Seite
      sagte über den Pilz kein Wort (Betreiber, 2026-09-22). Betroffen
      waren 30 Arten, fast alle Speisepilze — also durchweg das, was
      jemand wirklich im Korb hat. `test/species_features_test.dart`
      rechnet die Menge nach: eine neue Art OHNE Merkmale macht den
      Lauf rot. Die Pflicht ist teurer, die Alternative war eine
      Detailseite, die über den Pilz schweigt.
    - **Das Raster ist fest, und das ist kein Ordnungssinn.** Wer zwei
      Arten vergleicht, springt zwischen zwei Seiten und liest dieselbe
      Zeile zweimal; Freitext in wechselnder Reihenfolge macht genau das
      unmöglich — und Vergleichen ist der einzige Grund, aus dem jemand
      hier liest. „Trifft nicht zu" wird ausgeschrieben („keine
      Lamellen"), ein leeres Feld sähe aus wie eine Lücke.
    - **Geprüft wird die Pflege, nicht die Mykologie.** Ob der
      Gifthäubling einen glatten Stiel hat, steht in der Literatur. Der
      Test fängt, was beim Pflegen schiefgeht: zu kurze Felder,
      kopierte GESTALT-Zeilen (Hut/Unterseite/Stiel — Geruch und
      Vorkommen dürfen sich wiederholen, weil zwei Pilze eben beide mild
      riechen), zwei Arten mit demselben ganzen Satz. Beim ersten Lauf
      hat er neun echte Schlampigkeiten gefunden.
    - **Reihenfolge auf der Seite: erst die Warnungen, dann die
      Beschreibung.** Wer von oben liest, weiß vor dem ersten Merkmal,
      ob er es mit einem Giftpilz zu tun hat.
  - **Bildpaare** (`lib/core/species_photos.dart` + `assets/species/`,
    seit 1.167.0): elf Fotos von Wikimedia Commons, 700x700 WebP,
    zusammen 0,85 MB. Fünf Dinge, die man wissen muss:
    - **Zwei oder keines.** Ein einzelnes Bild zeigt, wie EINER von
      beiden aussieht, und das genügt zum Verwechseln — erst das Paar
      stellt die Frage. Deshalb steht kein Porträt am Seitenkopf, und
      eine einseitig bebilderte Zeile bleibt bildlos (den Fall gibt es:
      Grüner Knollenblätterpilz ↔ Frauentäubling).
    - **Die Auswahl hat ein Mensch ANGESEHEN.** Ein Werkzeug kann nicht
      beurteilen, ob ein Foto das Merkmal zeigt, das der
      Unterschiedssatz nennt. Zwei Kandidaten sind beim Ansehen
      ausgeschieden, weil sie eine andere Art zeigten als ihr Dateiname
      behauptete (eine nordamerikanische *Amanita*; ein als
      „Weisser Knollenblätterpilz" abgelegter Scheidenstreifling) — auf
      Commons ist die Bestimmung nicht garantiert. Wer ein Bild tauscht,
      sieht es an.
    - **Die Namensnennung steht an ZWEI Stellen**, und beide kommen aus
      derselben Tabelle: als Zeile unter dem Bild und auf der
      Lizenzseite (`speciesPhotoCredits()`). Eine von Hand gepflegte
      zweite Liste wäre die Stelle, an der ein getauschtes Bild seinen
      alten Urheber behält. NC- und ND-Lizenzen sind ausgeschlossen —
      ein Test prüft es, und der Zuschnitt allein verstößt schon gegen
      ND.
    - **`commons.wikimedia.org` ist `textOnly`** im Datenschutz-Wächter:
      Die Bilder liegen im Binary, die Adresse ist Quellenangabe.
      Geholt werden sie von `tool/species_photos.py` — das Werkzeug
      erzeugt die Assets Byte-genau reproduzierbar.
    - **„Zwei oder keines" ist seit 1.176.0 eine FUNKTION**
      (`onlyWithOwn`), keine Bedingung im Widget. Sie hing sonst daran,
      dass es zufällig eine Art ohne eigenes Bild mit bebildertem
      Partner gibt: Dreimal musste der Flow-Test dafür eine neue Art
      bekommen, und nach der zweiten Commons-Tranche gab es keine mehr
      — die Gegenprobe blieb grün, obwohl der Riegel entfernt war. Über
      zwei Listen geprüft ist die Regel unabhängig vom Datenbestand rot
      zu bekommen. Der Riegel bleibt, obwohl der Fall heute nicht
      vorkommt: Ein Bild wird ersetzt, ein Partner kommt dazu, und dann
      zählt er wieder.

    - **Alle Bilder stehen in EINEM Streifen** (seit 1.174.0): links
      die Art selbst, dann eine sichtbare Trennung, rechts ihre
      Verwechslungspartner. Vorher saß das Paar in der
      Verwechslungszeile — und seit die harmlosen Zeilen einklappen
      (1.172.0), konnte es hinter einem Tipp verschwinden. Vier Dinge:
      **Rahmen nur bei Warnung**, der eigene Pilz und ein harmloser
      Partner bekommen den neutralen Rand; Grün gibt es nicht, es läse
      sich als Freigabe. **Die Unterschrift trägt die Aussage**, nicht
      die Farbe — sonst hält jemand beim Überfliegen das
      Pantherpilz-Bild für den Perlpilz; der Screenreader hört
      „Verwechslungspartner" mit. **„Zwei oder keines" gilt weiter**,
      nur an anderer Stelle: `ownPictures` leer heißt kein Streifen,
      auch wenn ein Partner ein Bild hätte. Und **die Kachel wird nach
      dem BILD geschlüsselt, nicht nach der Art** — drei Porträts einer
      Art hätten sonst denselben Schlüssel, und `getTopLeft` bricht bei
      drei Treffern ab.

    - **Die Detailseite braucht einen Schlüssel je Art**
      (`ValueKey(name)` in `router.dart`). Ohne ihn hält Flutter die
      Seite der nächsten Art für dieselbe, verwendet das Element weiter
      — und die `ListView` behält ihre Scrollposition. Wer von einem
      Verwechslungspartner aus weitertippt, landete mitten auf dessen
      Seite statt oben bei Namen und Einstufung. Gefunden hat das ein
      Test, der eigentlich etwas anderes prüfen sollte.
  - **Porträts je Art** (`speciesPortraits`, seit 1.170.0): zwei bis
    drei EIGENE Aufnahmen des Betreibers je Art, waagerecht
    durchblätterbar, für 14 Arten. Fünf Dinge, die man wissen muss:
    - **Das ist etwas anderes als das Bildpaar, und beide bleiben.**
      Beim Paar gilt „zwei oder keines", weil ein einzelnes Bild eine
      Verwechslung nicht auflöst. Das Porträt beantwortet die andere
      Frage — wie die Art überhaupt aussieht —, und dafür ist ein Bild
      zu wenig: Farbe und Form ändern sich mit Alter und Wetter
      (Betreiber, 2026-09-22: „wir können auch 2-3 Bilder je nehmen").
      Ein Test hält die Spanne 1 bis 3 fest.
    - **Eigene Fundbilder schlagen Lehrbuchbilder**, und das ist
      gemessen, nicht behauptet: Das Reizker-Foto des Betreibers trug
      die Stielgrübchen, die unsere Merkmalstabelle dem Edelreizker
      ALLEIN zuschrieb — die Zeile war zu absolut und ist in 1.169.0
      berichtigt worden. Ein Commons-Bild hätte den Fehler bestätigt,
      weil dort die Lehrbuchform abgelegt wird.
    - **Der Hinweis darunter steht EINMAL je Seite** und hängt an
      „zeigt diese Seite irgendein Bild", nicht an „gibt es Porträts" —
      sonst stünde unter den Vergleichspaaren nichts. Die beiden
      tragenden Sätze (`kPhotoDisclaimer`) stehen AUSSERHALB des
      Ausklappers; eingeklappt wird nur die Begründung. Eine
      eingeklappte Warnung ist Deko.
    - **Die Lizenzseite liest EINE Naht** (`allSpeciesPhotos()`).
      Vorher kannte `speciesPhotoCredits` nur die Paar-Tabelle; eine
      zweite Bildquelle wäre dort stillschweigend unerwähnt geblieben,
      und ein nicht genanntes CC-BY-Bild ist ein Lizenzverstoß. Die
      Gegenprobe dazu ist gemessen.
    - **Die Detailseite hat seither ZWEI Scrollables**, und die
      senkrechte trägt deshalb `kSpeciesDetailListKey`. Ein Test, der
      „das Scrollable dieser Seite" sucht, fand zwei und scheiterte im
      Zug; `descendant` trifft dabei auch das innere, es braucht
      ausdrücklich das erste. Dieselbe Falle wie beim Suchfeld (#516).
      Und eine negative Aussage über die Seite braucht einen ANKER:
      Nach `scrollUntilVisible` steht das Ziel am oberen Rand, alles
      darüber ist nicht gebaut, und `findsNothing` ist dann grün, egal
      was dort stünde. In der Gegenprobe genau so passiert.

  - **Bilder antippen und groß ansehen** (#537, seit 1.179.0): Die
    großen Fassungen (1200x1200, 78 Dateien, 15,9 MB) liegen NICHT im
    APK, sondern auf dem Branch `species-photos`. Fünf Dinge:
    - **Ein Branch, kein Release-Anhang**, aus demselben Grund wie beim
      Regengitter: Release-Anhänge tragen kein
      `access-control-allow-origin`, der Web-Build bekäme still nichts.
      Nachgemessen am 2026-09-22: `raw.githubusercontent.com` liefert
      `*`. Ein Wurzel-Commit, force gepusht — jedes Commons-Bild ist
      ein Platzhalter, wird also ersetzt, und sonst wüchse die Historie
      je Tausch um die volle Bildgröße.
    - **Kein neues Netzziel**, der Host steht schon in der
      Datenschutzerklärung.
    - **Der Tipp vergrößert IMMER**, auch ohne Empfang: erst das
      mitgelieferte 400er, das große ersetzt es, sobald es da ist. Erst
      laden und dann zeigen wäre ein Versprechen, das im Wald nicht
      hält.
    - **Die Lupe an der Kachel löst nichts aus** — „beobachten ist
      laden", geholt wird erst beim Antippen. Ein Test zählt die
      Abrufe.
    - **Jedes Bild braucht seine große Fassung** (#588): `ci.yml`
      bricht ab, wenn ein `assets/species/*.webp` keine auf dem Branch
      hat (`tool/species_photos.py --check-large`). Mit #541 kamen 34
      ohne — die Vergrößerung zeigte still das 400er. `--large` baut sie
      aus dem Commons-Original mit demselben Ausschnitt (SSIM-geprüft);
      kleinere Originale liegen in ihrer Größe da, nie hochgerechnet.
    - **Eine GRÖSSENgrenze, keine Frist** (24 MB, älteste Ansicht
      fliegt zuerst). Das unterscheidet diesen Speicher von
      `spot_cache/`, `outbox/` und `tours/`: Ein Bild ist jederzeit
      nachladbar, deren Inhalt nicht. Im Browser gibt es keinen eigenen
      Speicher — der HTTP-Cache und der Service Worker tun es schon.

  - **Eine neue Art durch die ganze Kette** (Schönfußröhrling, 1.167.0,
    als Muster): `kBekannteArten` mit akzeptiertem GBIF-Namen →
    `tool/season_curves.py --out` (Netz, dabei die Zahl der
    Art-Monate messen, die an `kSeasonNowThreshold` kippen) →
    `tool/gbif_finds.py build` (lokale DB) → `tool/generated_assets.py
    --update` → Einstufung, Paare, Merkmale. Die Tests verlangen jeden
    Schritt: ohne Einstufung rot, mit Paar ohne Merkmale rot, und
    `_Reported` sagte ohne neu gebautes Fundorte-Asset „lässt sich nicht
    laden" über eine Art, die schlicht nicht drin war.
  - **Die Warnung dort, wo der Pilz ist** (seit 1.168.0; Betreiber-
    Durchsicht 2026-09-22: „haben wir was Essenzielles vergessen?" —
    ja, genau das). Bis dahin führte von KEINER anderen Stelle der App
    ein Weg zur Artseite; Einstufung und Partner waren ein
    Nachschlagewerk, das man aufsuchen musste. Drei Dinge:
    - **Eingabefeld** (`species_field.dart`): `confusionHint` unter dem
      Feld, sobald die Vorschlagskarte zu ist — dieselbe Bedingung wie
      das Symbol, denn ein voller Name mit mehreren Treffern
      („Steinpilz") ist noch keine Entscheidung. Bewusst OHNE Verweis:
      Das Blatt ist ein Formular, ein Wechsel würde die Eingabe
      verwerfen. Die Einstufung des Partners steht nur dabei, wenn sie
      warnt (Asymmetrie).
    - **Spot-Blatt**: ein `ActionChip` je bekannter Art des Spots
      (`scanSpeciesOf` → `knownSpeciesFor`, Freitext-Arten haben keine
      Seite). Der Router wird VOR `pop()` gegriffen — danach ist der
      Kontext des Blatts nicht mehr eingehängt.
    - **Rückkanal**: „Hinweis zu dieser Art melden" am Fuß der Artseite,
      als `FeedbackType.bug` mit dem Artnamen im Text — der Bot macht
      daraus ein Bug-Issue. Handgepflegte Tabellen, an denen eine
      Vergiftung hängen kann, brauchen den Weg dort, wo man den Fehler
      sieht.
- **Der Reiter „Spots"** (#509, seit 1.161.0): die Karte als Liste
  (`lib/features/spots/spots_screen.dart`) plus die Statistik, die bis
  1.160.0 im Profil stand. Sechs Dinge, die man wissen muss:
  - **Keine neue Abfrage, kein Schema-Patch.** Alles kommt aus
    `mySpotListProvider` und `friendSpotsProvider` — der Reiter
    funktioniert damit offline und zeigt den Ausgangskorb mit. Wer hier
    etwas ergänzt, das eine eigene Abfrage bräuchte, hat die Idee
    verlassen.
  - **Sortiert wird nach dem jüngsten EINTRAG, nicht nach dem jüngsten
    Fund** (`spot_list.dart`, ohne Widgets, wie `species_catalogue.dart`):
    Ein Leergang ist Aktivität. Die Trennlinie aus #211 gilt weiter — die
    STATISTIK zählt nur `ownFinds`.
  - **Drei Gruppen, und die dritte gibt es nur wegen der Freigaben.**
    Ein Buddy-Spot ohne `share_details` kommt ohne einen einzigen
    Eintrag an und sähe aus wie eine Vormerkung (#499). Er steht
    deshalb unter „Ohne Einträge" mit demselben Satz, den auch das
    Spot-Blatt sagt. Dieselbe Falle umgeht die Karte am Marker mit
    `spot.isOwn && spot.isPlanned`.
  - **Zwei Ziele je Zeile.** Antippen öffnet `showSpotDetailSheet` an
    Ort und Stelle (das Blatt braucht nur eine id und hängt an keiner
    Karte), das Kartensymbol wechselt den Reiter (`kMapBranchIndex` in
    `lib/core/router_branches.dart` — eigene Datei, weil `router.dart`
    jeden Screen importiert) und stellt dann den Fokus-Wunsch (#345).
    Reihenfolge: erst Reiter, dann Wunsch.
  - **Der Reiter schaltet die Buddy-Meldung NICHT stumm.**
    `lastFindSeenAt` gehört dem Karten-Banner; hier wird nur gelesen
    (`spotsWithNewsProvider` fasst `newBuddyFindsProvider` zusammen —
    EINE Definition von „neu"). Wer das ändert, holt #349/#425 zurück:
    ein Feature, das nach dem ersten Benutzen kaputt aussieht.
  - **Der Karten-Filter bleibt bei der Karte.** Hier stehen eigene,
    leichte Regler (Suche über Name/Art/Buddy mit derselben Faltung wie
    die Artensuche, #395; Dreier-Schalter nur, wenn es geteilte Spots
    gibt). Ein Filter, der an zwei Orten verschieden wirkt, wäre
    schlimmer als zwei getrennte — auf der Karte muss er sich melden
    (#154).
  Die Statistik (`widgets/spot_stats_view.dart`, gerechnet in
  `spot_stats.dart`) ist UMGEZOGEN, nicht verdoppelt: Im Profil steht ein
  Verweis. „Funde nach Jahreszeit" ist dabei einem Monatsverlauf
  gewichen, der `SeasonBars` benutzt — nur so lässt sich der eigene
  Jahresgang neben den gemeldeten legen. Der Vorjahresvergleich rechnet
  **bis zum selben Tag**, sonst stünde man jeden Herbst gegen ein volles
  Vorjahr im Rückstand.
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
  Sechs Dinge, die man wissen muss:
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
    „kein Schutzgebiet".
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
- **Vormerkung** (#499, seit 1.159.0): ein Spot OHNE Einträge, mit
  erwarteten Arten (`spots.expected_species`, Patch 025). Drei Dinge,
  die man wissen muss:
  - **Vorgemerkt IST `finds.isEmpty`**, keine Zustandsspalte: Der erste
    Eintrag beendet die Vormerkung von selbst, zwei Wahrheiten könnten
    auseinanderlaufen. Bis 1.158.0 legte der Anlege-Weg immer einen
    Fund an (der Arten-Sammler meldet auch eine leere Zeile — bewusst:
    „da stand was, ich weiß nicht was"); der Schalter „Nur vormerken"
    im Blatt umgeht genau diese Zeile.
  - **Erwartete Arten sind KEINE Funde.** Als Fund-Sorte (wie der
    Leergang) sickerten sie in Statistik, Marker-Art und
    Artenvorschläge; als Liste am Spot liest sie nur, wer sie braucht:
    `scanSpeciesOf` (Ampel-Blatt, Nachlauf) und `spotSpeciesNames`
    (Arten-Filter, Saison-Filter, Arten-Zähler) — jeweils nur, solange
    der Spot keine Funde hat.
  - **Verblasst wie wartend, aber ohne Uhr** (`MushroomIcon.planned`);
    kein viertes Abzeichen. Der Ausgangskorb trägt die Liste im
    Auftrag mit (`NewSpotJob.expectedSpecies`).
- **Fundfotos für Buddys** (#532, seit 1.185.0): ein Foto am eigenen
  Fund, 14 Tage sichtbar für die, die den Fund sehen dürfen; Posteingang
  ist der Reiter „Spots". Sechs Dinge, die man wissen muss:
  - **Die Bytes liegen im Bucket `find-photos`, nicht in Postgres.**
    Je Foto eine Zeile `find_photos` (~200 Byte, Patch 026) und zwei
    JPEGs (1024 px ≈ 150 KB, Vorschau 200 px ≈ 12 KB). Der Speicher
    ist damit KONSTANT: 14 Tage Frist als Default UND Constraint in der
    Datenbank (ein Client kann sie nicht verlängern), und der
    Feedback-Bot räumt alle zwei Stunden per ABGLEICH — jedes Objekt
    ohne lebende Zeile fliegt (`sweep_find_photos`, Schonfrist 1 h für
    Uploads im Aufbau). Kein „erst Zeile, dann Objekt": Das ließe
    Uploads, deren Zeile nie kam, für immer liegen.
  - **Das Foto erbt die Sichtbarkeit des FUNDES.** `fp_friend_select`
    fragt nur `exists (select … from finds)`; die Storage-Policy
    `find_photos_read` fragt nur, ob eine Zeile sichtbar ist. Keine
    zweite Freigabe, die neben der ersten driften kann. Ein Objekt ohne
    Zeile ist für niemanden lesbar — deshalb erst die Objekte, dann die
    Zeile. Im Fake spiegelt `findVisibleTo` die drei finds-Policies an
    EINER Stelle; Spot-Abruf und Fotos lesen dieselbe Antwort.
  - **Die Fundstelle steckt im Foto, und die Bibliotheken lassen sie
    drin.** `image_picker` kopiert beim Verkleinern auf Android
    absichtlich alle 30 GPS-Tags zurück (`ExifDataCopier.java`);
    `package:image` reicht EXIF durch `bakeOrientation` und
    `copyResize` und schreibt es in `encodeJpg` wieder hinein.
    `lib/core/photo_pipeline.dart` leert `exif` ausdrücklich und LIEST
    das Ergebnis (`jpegForeignMarkers`, Erlaubnisliste der Segmente,
    dazu „Bytes hinter EOI") — bei jedem Upload, nicht nur im Test. In
    der Gegenprobe ohne die eine Zeile wurden drei Tests rot, darunter
    der Laufzeit-Riegel selbst. Der Dialog sagt dazu, was bleibt: Ein
    erkennbarer Ort ist erkennbar.
  - **Die Kachel lädt die Vorschau, die Vergrößerung das Bild** — der
    Egress-Hebel (Faktor 10) auf 5 GB im Monat. Beides über
    `BoundedFileCache` (aus #537 herausgelöst, 24 MB, älteste fliegt).
    Der Profil-Schalter „Fundfotos von Buddys anzeigen" (Vorgabe AN)
    filtert im PROVIDER, nicht in der Kachel: aus heißt kein Abruf,
    eigene bleiben. Rand, Wischen und Ausgänge der Vergrößerung wohnen
    in `PhotoOverlay`, geteilt mit den Artbildern.
  - **Offline scheitert sichtbar, kein dritter Korb-Weg.** Ein Foto ist
    ein Extra-Schritt nach dem Eintragen; ein Binärauftrag im Korb wäre
    eine eigene Idempotenz-Geschichte. Wartende Funde haben keine id
    und deshalb keine Kamera, Leergänge nichts zu zeigen.
  - **Keine neue Berechtigung, kein neues Netzziel** — Storage liegt
    unter der Supabase-Adresse. Trotzdem eine neue Datenkategorie:
    `web/datenschutz.html`, `docs/play-console.md` (Fotos: erhoben,
    optional; die Zeile „Fotos: NICHT erhoben" ist gefallen) und
    `docs/datenschutz-nachweise.md` sind im selben PR mitgezogen. Der
    Schema Dry Run braucht seither `[storage] enabled = true` in
    `config.toml`, sonst gibt es `storage.buckets` nicht.
  - **Foto gleich beim Eintragen** (seit 1.188.0): Das Blatt „Fund
    eintragen" nimmt ein `PreparedPhoto` mit und gibt es als
    `AddFindResult` zurück; hochgeladen wird erst NACH dem Schreiben,
    an die id des ERSTEN Fundes (`SpotRepository.addFinds` liefert die
    ids seither, per `client_id` zugeordnet — `RETURNING` verspricht
    keine Reihenfolge). Der Fund ist das Original: Scheitert der
    Upload, steht er trotzdem, und die Meldung sagt beides. Wandert er
    in den Korb, gibt es keine id und damit kein Foto — ein wartender
    Spot bietet es deshalb gar nicht erst an.
  - **Galerie im Reiter „Buddys"** (seit 1.189.0): `FindPhotoGallery`
    ganz oben, dieselbe `findPhotosProvider`-Liste wie der Streifen —
    keine eigene Abfrage, also keine eigenen Sichtbarkeitsregeln. Der
    Neu-Punkt ist GERÄTELOKAL (`Settings.seenFindPhotoIds`), weil eine
    Tabelle dafür eine Lesequittung wäre, die niemand bestellt hat;
    gesetzt beim Öffnen, nicht beim Vorbeiscrollen, und beim Setzen auf
    lebende Fotos gestutzt. Eigene Fotos sind nie neu. Der Ring rechnet
    über die volle Restdauer, nicht über `daysLeft` — ganze Tage
    springen, ein frisches Foto stünde sonst bei 13/14.
  - **Kudos** (Patch 028, seit 1.190.0): `find_photo_kudos`, ein Pilz
    je Buddy und Foto, keine Skala. Sichtbarkeit geerbt vom Foto
    (`fpk_select` fragt `find_photos`), abgeräumt per Cascade mit ihm.
    **`user_id` verweist auf `auth.users`, NICHT auf `profiles`** — mit
    Fremdschlüsseln auf `find_photos` UND `profiles` hielt PostgREST die
    Tabelle für eine Verbindungstabelle, und das `profiles`-Embed der
    Fotos wurde mehrdeutig (PGRST201). Lokal gegengeprobt: Beide
    Fassungen der Abfrage, auch die der ausgelieferten Clients, brachen.
    Der Schema Check prüft deshalb auch die Abfrage OHNE Kudos (Stand
    1.189.0). Namen löst die App über die eigene Buddy-Liste auf
    (`buddyNamesProvider`); Buddys von Buddys werden nur gezählt — mehr
    gäbe die profiles-Policy ohnehin nicht her.
  - **Ein Bild am Feedback** (#525, seit 1.186.0, Patch 027) läuft
    über dieselbe Naht — `PhotoAttachment` in beiden Melde-Dialogen,
    `photoPickerProvider`/`photoPreparerProvider` aus
    `core/photo_providers.dart`, Repository nimmt nur ein
    `PreparedPhoto`. Der Bucket `feedback-photos` ist STRENGER: Nutzer
    legen nur hinein, lesen darf allein der Betreiber (Service-
    Schlüssel, Dashboard). Der Text einer Meldung wird öffentlich, das
    Bild nicht — das Issue nennt nur den Dateinamen, keinen Pfad und
    keine Nutzer-id (`feedback_issue_body`, Selbsttest). Frist 90 Tage
    wie die Fehlerberichte, der Bot fegt per Erstellzeit; die Zeile
    behält ihren Pfad ins Leere, das Issue existiert ja.
    **Seit 1.196.0 bis zu DREI Bilder** (#569, Patch 033):
    `PhotoAttachmentList`, Repository nimmt eine Liste. Die Pfade stehen
    als Array `photo_paths` in der Zeile, KEINE Kindtabelle — die App
    darf ihre Feedback-Zeile nicht zurücklesen, eine Kindtabelle
    bräuchte deshalb eine vorab erzeugte id und eine Definer-Funktion.
    Grenze und Ordner erzwingt der Check über
    `app_internal.feedback_photos_ok` (ein CHECK kann kein Array
    durchlaufen). **`photo_path` bleibt**, solange 1.186.0–1.195.x im
    Feld sind; neue Clients schreiben nur `photo_paths`, der Bot liest
    beide (`feedback_photo_names`). Erst danach darf die alte Spalte
    weg — erweitern → ausliefern → entfernen.
    **Einwilligung für die Artgalerie** (seit 1.197.0, Patch 034,
    #569 Teil b): ein Haken im Art-Hinweis-Dialog, ab Werk aus, nur mit
    Bild, fällt mit dem letzten Bild weg. Er ist die EINZIGE Grundlage,
    ein Feedback-Bild in `species_photos.dart` zu übernehmen — ohne ihn
    ist ein solches Bild ausdrücklich nicht zur Veröffentlichung
    gedacht. Lizenz `kGalleryPhotoLicence` = CC BY-SA 4.0, dieselbe wie
    die eigenen Aufnahmen (ein Test hält Dialog, Galerie und Bot
    zusammen); Urheber ist der Benutzername, festgehalten im Issue zum
    Zeitpunkt der Meldung. Übernommen wird weiter nur nach Ansicht.
    **Art-Hinweise laden in Galerie-Größe hoch** (seit 1.199.0, Patch
    035): 2048er Kante, Qualität 85 (`prepareGalleryPhoto`,
    `galleryPhotoPreparerProvider`), allgemeines Feedback bleibt bei
    1024. Die Galerie zeigt 1200x1200 im Quadrat, aus 4:3 mit 1024er
    Kante blieben 768 px. Bei einem fremden Melder ist das Hochgeladene
    die EINZIGE Kopie — der Austauschordner ist nur der Weg des
    Betreibers. Gemessen an elf Pixel-Fotos: 581–1186 KB, deshalb
    Bucket-Grenze 2 MB statt 600 KB. Freigegebene Bilder innerhalb der
    90 Tage mit `tool/feedback_photos.py` abholen, danach sind sie weg.
- **Funde an iNaturalist melden — und darüber an GBIF** (#553, seit
  1.191.0, **noch unsichtbar**): Alle Entscheidungen stehen im TEXT von
  #553 (maßgeblich vor dem Plan-Kommentar), die Registrierung als
  Checkliste daneben. Sieben Dinge, die man wissen muss:
  - **`kInatAppId` ist leer, und das ist der Schalter.** Ohne
    Application ID zeigt die App den Weg nirgends
    (`inatAvailableProvider`). Der Betreiber kann die App bei
    iNaturalist frühestens am 2026-11-24 registrieren (Konto 2 Monate
    alt + 10 verbessernde Bestimmungen im letzten Monat); dann ist die
    ID eine Zeile. Im Browser bleibt es vorerst aus — dort fehlt die
    Rückleitungsseite, und CORS der Token-Adresse ist ungemessen.
  - **Jeder meldet mit SEINEM Konto** (OAuth + PKCE, öffentlicher
    Client, kein Geheimnis in der APK). Ein Sammelkonto hat der
    Betreiber vorgeschlagen; iNaturalist hat genau das bei QuestaGame
    als ToS-Verstoß gesperrt.
  - **Der Zugang liegt im Keystore** (`flutter_secure_storage`), nie in
    Supabase, und ist vom Backup ausgenommen — `FlutterSecureStorage.xml`
    UND `FlutterSecureKeyStorage.xml`, ein Test hält beide fest.
  - **Die Rückleitung steht an drei Stellen**: `kInatRedirectUri`, die
    CallbackActivity im Manifest, die Registrierung bei iNaturalist.
    Stimmt eine nicht, bleibt der Custom Tab nach dem Bestätigen offen,
    ohne Fehlermeldung.
  - **`find_reports` (Patch 029) entsteht VOR dem Senden** und trägt die
    uuid, die iNaturalist übernimmt. Ein zweiter Versuch mit derselben
    uuid legt dort keine zweite Beobachtung an — nachgelesen in
    `observations_controller.rb` (#create sucht erst nach der uuid).
    Reihenfolge: Art, JWT, Zeile, Beobachtung, Fotos, `reported`.
    `user_id` zeigt auf `auth.users`, aus demselben Grund wie bei den
    Kudos (PGRST201).
  - **Die Netzziele stehen AUSGESCHRIEBEN im Code** (`kInatWebBase`,
    `kInatApiBase`). Der Datenschutz-Wächter sucht `https://…`; ein
    `Uri.https(host, …)` hätte er übersehen — beim Bau genau so
    passiert, bevor er es sah.
  - **Was NICHT hinausgeht:** Notiz, Spot-Name, Buddys — und das
    Buddy-Foto nur mit ausdrücklichem Haken (Betreiber: „nicht blind").
    Vorgabe der Stelle ist VERSCHLEIERT; iNaturalist kennt die genaue
    trotzdem, der Verbinden-Dialog sagt es.
  **Stufe 2 (seit 1.192.0): Stand am Fund, nachträglich melden.** Drei
  Dinge:
  - **Einmal je Sitzung abgeglichen, EINE Abfrage für alle**
    (`myFindReportsProvider`, `InatReporter.refresh`): iNaturalist nimmt
    eine id-Liste; GBIF wird nur für bestätigte gefragt, im Datensatz
    `kInatGbifDataset` über `catalogNumber` = Beobachtungsnummer
    (nachgesehen an einer echten Beobachtung). `sending` gleicht niemand
    ab — dort fehlt etwas, das nur ein neuer Versuch nachholt. Fehlt eine
    Beobachtung in der Antwort, gilt sie als gelöscht; deshalb reicht
    `per_page` immer für alle gefragten ids.
  - **„Vervollständigen" ist derselbe Weg wie Melden** und knüpft über
    die uuid an: auch wenn die Beobachtungs-id nie in der Zeile ankam,
    entsteht keine zweite (Flow-Test mit genau diesem Abbruch).
  - **Ein Ausfall bei iNaturalist/GBIF gehört nicht in den
    Wochendigest** — `InatException` und Funklöcher werden beim
    Abgleich verschluckt, der gespeicherte Stand gilt.
- **Nachrichten zwischen Buddys** (#564, seit 1.193.0, Patch 030): Text
  bis 500 Zeichen, 30 Tage. Entscheidungen im Text von #564. Fünf Dinge,
  die man wissen muss:
  - **Die Grenzen zieht die Datenbank.** `app_internal.may_message`:
    angenommen ⇒ frei, offene Anfrage ⇒ höchstens drei eigene je Person,
    sonst nichts. Die Zahl im Verlauf („Noch 2 Nachrichten …") ist nur
    die Ansage vorher.
  - **Die 30 Tage hängen an SPALTEN-Grants**, nicht nur am Check: Ein
    Client darf beim Anlegen nur `recipient_id` und `body` setzen, beim
    Ändern nur `read_at`. Dafür steht zuerst ein `revoke all` — die
    Legacy-Vorgabe `auto_expose_new_tables` gäbe sonst Tabellen-INSERT,
    und der schlüge jeden Spalten-Grant. `anon` hat damit GAR keinen
    Grant; der Schema Check prüft die Tabelle deshalb über
    `check_get_protected` (42501 = vorhanden, 42703 = Spalte fehlt —
    gemessen, Postgres löst Spalten vor der Rechteprüfung auf).
  - **Ende der Freundschaft löscht den Verlauf beider Seiten** (Trigger
    `friendships_delete_messages`, Definer). `FriendshipsNotifier.remove`
    verwirft danach die Nachrichtenliste, sonst bliebe der
    Ungelesen-Punkt stehen.
  - **„Gelesen" hat eine Sperre: ein Versuch je Nachricht und Öffnen.**
    Ohne sie markierte der Verlauf bei jeder neuen Liste erneut, und
    jede Markierung lud neu — bewirkte der Server nichts, lief das ohne
    Ende (Gegenprobe; der Test dazu HÄNGT ohne Sperre, weil die Schleife
    über Microtasks läuft und kein Test-Timeout greift).
  - **Die Nachrichten lädt der Reiter-Punkt beim Start** (`BuddysNavIcon`)
    — eine Abfrage für alle Verläufe. Kein Realtime; frisch geholt wird
    beim Öffnen eines Verlaufs, per Ziehen und bei jeder eintreffenden
    Nachrichten-Meldung.
  - **Push MIT Text** (seit 1.194.0, Patch 031) — die EINE Ausnahme von
    „nie Inhalt über Google", Betreiber-Entscheidung; Profil-Schalter,
    Datenschutzerklärung und `send-push` sagen es. Eigene Warteschlange
    `app_internal.push_messages` (Cascade an der Nachricht: zurückgenommen
    ⇒ keine Meldung), versandt im selben minütlichen `push_flush`, je
    Empfänger und Absender eine Meldung. **`tool/push_flush_check.sh`
    ruft `push_flush` im Schema Dry Run WIRKLICH auf** (zurückgerollte
    Transaktion, Schein-Geheimnisse): PL/pgSQL prüft den Rumpf erst beim
    Aufruf, und ein Fehler dort legte live ALLE Benachrichtigungen still.
    Das Ziel reist als `data.route`; die App folgt nur Pfaden aus
    `pushRouteOf` (Erlaubnisliste) — Tipp aus dem Hintergrund
    (`onMessageOpenedApp`) UND aus dem beendeten Zustand
    (`getInitialMessage`, `pushInitialMessageProvider`).
- **Aliase für Buddys** (#567, seit 1.195.0, Patch 032): ein eigener
  Name je Buddy, nur für den Besitzer, geräteübergreifend. Vier Dinge,
  die man wissen muss:
  - **Jeder Buddy-Name geht über `BuddyNames.of`**
    (`lib/features/friends/buddy_alias.dart`). Namen stehen an rund
    fünfzehn Stellen; wer dort `username` direkt liest, zeigt an genau
    einer Stelle den alten Namen, und die fällt dann auf. Liste und
    Verlaufskopf zeigen Alias UND Namen, alles andere nur den Alias.
  - **Nur für bestätigte Buddys** (`are_friends` in `fa_insert`/
    `fa_update`), sonst ließe sich jedem Konto aus der Namenssuche ein
    Etikett anheften. Ende der Freundschaft löscht beide Seiten
    (Trigger `friendships_delete_aliases`, Betreiber-Entscheidung).
  - **Die Push trägt den Alias des EMPFÄNGERS** — `push_flush` schlägt
    ihn nach; `tool/push_flush_check.sh` prüft Alias, Rückfall auf den
    Namen und dass der Alias der Gegenseite nicht durchsickert.
  - **Ohne Empfang fällt der Alias weg** und der Name steht da: kein
    eigener Zwischenspeicher, er ist Bequemlichkeit, kein Inhalt.
- **Fundstellen weit vom Spot** (#475, seit 1.156.0): Ab 100 m
  (`kFindFixMaxOffsetM`, dieselbe Grenze wie der Riegel beim Eintragen)
  trägt der eigene Spot ein „!"-Abzeichen (im selben Kreis wie Uhr und
  Fragezeichen — kein Dreieck, kein Pilz-Glyph), das Blatt nennt die Stellen,
  „So gewollt" bestätigt. Vier Dinge, die man wissen muss:
  - **Abgeleitet, nicht gespeichert** (`driftingFinds` in
    `find_offset.dart`). Gespeichert ist nur die Bestätigung, und die
    hängt als ZEITPUNKT am Spot (`spots.offset_confirmed_at`, Patch
    024): Warnung, solange eine abweichende Fundstelle jünger ist als
    die Bestätigung. Ein Flag je Fund ginge nicht — den Fund eines
    Buddys darf der Besitzer per RLS nicht schreiben, die Warnung stünde
    für immer.
  - **Verlegen fragt.** Spot mit eigenen Fundstellen: „Nur den Spot"
    (Bestätigung wird gelöscht, eine neue Abweichung fällt wieder auf)
    oder „Spot und alle Fundstellen" (`pinFindsToSpot`: eigene Position
    der Funde wird GELÖSCHT, keine erfundene Koordinate — gemessene
    Stellen gehen verloren, der Dialog sagt es). Fundstelle verlegt:
    „Spot mitverschieben?", Vorgabe Nein.
  - **Fremde Fundstellen bleiben immer**, wo sie sind (RLS
    `finds_author_all`); kein RPC, keine Security-Definer-Funktion.
    Zwei Schreibvorgänge statt einer Transaktion — bricht der zweite ab,
    ist der Spot verlegt und die Warnung zeigt genau das.
  - **Gemessen vor dem Bau** (2026-09-21, Kommentar in #475): 9 von 166
    Funden hatten eine eigene Position, alle innerhalb 20 m. Der
    Hinweis ist eine Vorsorge für #473, kein Befund.
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
  Deutschland**, sonst sähe die fehlende Zeile in Österreich nach einem
  Fehler aus.
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
- **Höhengitter & Temperaturkorrektur** (`tool/elevation_grid.py` +
  `elevation-data.yml`, Rest aus #279, seit 1.93.0): Drittes Gitter auf
  DEMSELBEN Hex-Raster (Copernicus DEM GLO-90, 1 Byte = 20-m-Stufen,
  Zeilen-Delta + gzip, 3,4 MB, Workflow nur `workflow_dispatch` — das
  DEM ist statisch). Blatt-Ampel und Kartenfläche rechnen die
  Stationstemperatur mit 0,65 K je 100 m auf die Wabenhöhe um. Vier
  Dinge, die man wissen muss:
  - **Die Korrektur ist Eingabe-Aufbereitung, keine Modelländerung**:
    `ampel_model.dart` bleibt Zahl für Zahl Spiegel des
    Validierungswerkzeugs. Und sie führt ZUM validierten Aufbau hin —
    `ampel_validate.py` nahm Open-Meteo-Temperaturen an der
    Fundkoordinate, die dort schon aufs 90-m-DEM heruntergerechnet
    sind. Die unkorrigierte Station war die Abweichung.
  - **Fläche und Blatt korrigieren beide oder keiner** (#279-Regel),
    und zwar seit 1.94.0 JE WABE: `AmpelLevelGrid` trägt je Regenzelle
    die ZUTATEN (Regenfaktor, Stationsmittel, Stationshöhe), und erst
    der Abnehmer wertet die Glocke mit SEINER Höhe aus — der
    Wabenzeichner mit der Höhe jeder Waldwabe (grob wie fein), Legende
    und Blatt am Punkt. Eine je Regenzelle fertig gerechnete Stufe
    (so 1.93.0/.1) konnte der Punkt-Ablesung in steilem Gelände nie
    überall zustimmen — eine 1-km-Zelle überspannt in den Alpen 500+
    Höhenmeter (Feldbericht Berchtesgaden). Wächter:
    `test/ampel_fill_test.dart` (Walker) und der Pixel-Test in
    `test/forest_ampel_fill_test.dart`; Messung (316→733 ms Debug im
    teuersten Fall, Isolate) in `docs/map-performance.md`, nachgeprüft
    von `test/perf_ampel_fill_measure.dart`.
  - **Das Diagramm zeigt weiter ROHE Stationswerte** (beschriftet mit
    Station + Höhe) — nur die Ampel-Zeile rechnet um und sagt es ab
    ~0,3 K dazu („auf Spothöhe 1200 m"); darunter bleibt der Zusatz
    weg, sonst erklärte im Flachland jeder Spot eine Nullnummer.
  - Ohne Gitter/außerhalb DACH: still unkorrigiert (`null`-Pfad), wie
    vor 1.93.0 — die Stationshöhe steht ja daneben.
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
- Issue-Triage (`.github/workflows/claude-issue-triage.yml`): Claude analysiert
  jedes neue Issue (Einordnung, Labels, Ursache, Umsetzungsvorschlag als
  Kommentar) — darf aber NUR lesen/labeln/kommentieren. Umsetzung erst nach
  Freigabe-Kommentar `@claude …` (claude.yml, Branch + PR, Merge manuell).
  Braucht Repo-Secret `CLAUDE_CODE_OAUTH_TOKEN` (Abo; alternativ
  `ANTHROPIC_API_KEY`, dann Input in beiden Workflows tauschen) und die
  Claude GitHub App (github.com/apps/claude). Bot-Issues werden per workflow_dispatch triagiert
  (GITHUB_TOKEN-Events triggern keine Folge-Workflows). Temporär aus:
  `gh workflow disable "Claude Issue Triage"`.
- Feedback-Bot (`.github/workflows/feedback.yml` + `tool/feedback_bot.py`,
  Cron alle 2 h): macht aus In-App-Feedback GitHub-Issues (Features) bzw.
  fertige Arten-PRs (Merge = annehmen mit Auto-Release, Close = ablehnen).
  Auf demselben Tick läuft der **Fehlerbericht-Digest**: ein Issue pro
  ISO-Woche (Label `ops`, Titel `Error reports JJJJ-Wnn`), das bei jedem
  Lauf neu geschrieben statt kommentiert wird; keine Fehler ⇒ kein Issue.
  Dazu die 90-Tage-Bereinigung von `error_reports`. Beides liegt hier und
  nicht in einem eigenen Workflow, weil Zeitplan, service_role-Key und
  GitHub-Token schon da sind — und `error_reports` bewusst keine
  select-Policy hat, ein Leser also ohnehin den Key braucht.
  Braucht das Repo-Secret `SUPABASE_SERVICE_ROLE_KEY`. Selbsttests:
  `python3 tool/feedback_bot.py --test-insert "Name"` und `--test-digest`;
  seit #151 laufen sie im Job „Analyze & Test" mit, sonst verrotten sie.
  Jede Gruppe im Digest zeigt neben der Meldung den **obersten Frame im
  eigenen Code** (`top_frame`). Ohne den stand in KW30 61-mal
  `Infinity or NaN toInt`, ohne dass jemand die Datei benennen konnte —
  der Stack lag die ganze Zeit in der Tabelle. Vergangene Wochen
  (Rohdaten: 90 Tage) rendert `--digest-week 2026-W30`; wer den Schlüssel
  nicht zur Hand hat, startet den Workflow von Hand mit der Eingabe
  `digest_week`, dann steht der Digest in der Run-Summary. Beides liest
  nur — kein Issue, keine Bereinigung.
- Backup (`.github/workflows/backup.yml` + `tool/db_backup.sh`, montags plus
  `workflow_dispatch` vor größeren Migrationen): `pg_dump` von `public`,
  `app_internal` und `auth`, mit age verschlüsselt, als Release-Asset im **privaten** Repo
  `pilzbuddy-backups` (dieses Repo ist öffentlich, seine Artefakte wären es
  auch). Verschlüsselt wird asymmetrisch — der öffentliche Schlüssel steht
  im Skript, der private liegt **nur** in
  im Schlüsselordner des Betreibers und nie in GitHub; sein Verlust
  macht alle Backups wertlos. Vor dem Hochladen prüft das Skript, ob die
  erwarteten Tabellen (inkl. `auth.users`) wirklich im Dump stehen — ein
  halber Dump wird nicht abgelegt. Aufbewahrung: die letzten 12 Läufe.
  Braucht zusätzlich das Repo-Secret `BACKUP_REPO_TOKEN` (fein granulares
  PAT, nur `contents:write` auf das Backup-Repo). Verfahren und
  Restore-Übung: `docs/backup-restore.md` — ein nie zurückgespieltes Backup
  zählt nicht.
- Supabase-Free-Plan: Projekte werden nach ~1 Woche ohne Zugriff pausiert.
  Der Feedback-Bot-Cron (alle 2 h) und der Backup-Job halten das Projekt
  wach — das ist ab jetzt eine bewusste Zusage, kein Zufall: Wer beide
  Crons abschaltet, riskiert ein pausiertes Projekt und eine tote App.
  Grenzen: 500 MB Datenbank, 5 GB Egress. Die aktuelle Datenbankgröße steht
  wöchentlich in der Summary des Backup-Jobs — dort nachsehen, statt zu
  schätzen.
- Update-Hinweis (`lib/core/update_check.dart`, Banner in `map_banners.dart`):
  tokenlos gegen `releases/latest`. Der Dialog lädt die APK seit #161 wieder
  **in der App** (`lib/features/update/update_installer.dart`) und übergibt
  sie Androids System-Installer (`MainActivity.kt`, Kanal `apk_install`,
  FileProvider auf `updates/`); der Browser bleibt als Rückfallweg für jeden
  Fehlschlag stehen, weil er als einziger ohne Berechtigung und ohne Kanal
  auskommt. **Kein `ota_update`** — dessen Plugin-Manifest zog
  `INSTALL_PACKAGES` (Signatur-Berechtigung), `READ/WRITE_EXTERNAL_STORAGE`
  und `RECEIVE_BOOT_COMPLETED` in jeden Build (14 statt 8 Berechtigungen).
  Der eigene Weg braucht genau eine: `REQUEST_INSTALL_PACKAGES` — die App
  *bietet* eine Datei an, den Installationsdialog zeigt Android.
  `test/android_manifest_test.dart` wacht über beides: dass die Abhängigkeit
  wegbleibt und dass genau diese eine Berechtigung dasteht.
  **Diese Zeile darf nicht ins AAB** — seit 1.87.1 erledigt: Der Dart-Pfad
  war im Play-Build über `AppDistribution.showsUpdateHints` schon aus, das
  Manifest nicht. Zwei Produkt-Flavors trennen das jetzt (`github` behält
  die Berechtigung, `play` nimmt sie per `tools:node="remove"` heraus);
  beide tragen dieselbe `applicationId`, ein `applicationIdSuffix` wäre
  hier der teure Fehler. **Folge für jeden Android-Build: `--flavor` ist ab
  jetzt Pflicht**, und der Flavor steht im Ausgabepfad — ein `cp` auf den
  alten Namen bricht erst NACH dem Taggen ab. `test/release_build_test.dart`
  und `test/android_manifest_test.dart` halten Aufruf, Pfad und Manifest
  zusammen; Einzelheiten in `docs/play-console.md`.
  Der ganze Pfad hängt an `AppDistribution.showsUpdateHints`
  (`lib/core/app_distribution.dart`): im Play-Build via
  `--dart-define=PLAY_BUILD=true` abgeschaltet, weil Play dort selbst
  aktualisiert und Verweise auf APK-Downloads unzulässig sind.
  Der `<queries>`-Eintrag VIEW/https im Manifest bleibt nötig, sonst kann
  die App den Browser nicht öffnen.
- **Spot an eine Navi-App übergeben** (`lib/features/spots/spot_navigation.dart`,
  #367, seit 1.112.0): Ein Knopf im Spot-Blatt reicht die Koordinate als
  `geo:`-URI an Android weiter; welche App sie bekommt, entscheidet der
  System-Wähler. Drei Dinge, die man wissen muss:
  - **Ein zweiter `<queries>`-Eintrag, diesmal VIEW/geo.** Ohne ihn sieht
    die App ab Android 11 keinen Empfänger, der Wähler bleibt aus, und der
    Knopf fällt still auf die Zwischenablage zurück — ein Fehler, der wie
    eine Entscheidung aussieht. `test/android_manifest_test.dart` prüft
    ihn gegen `kGeoScheme` aus dem Dart-Code, wie beim MethodChannel-Namen.
  - **Kein `https://…/maps?q=…` als Rückfallweg**, so naheliegend er ist:
    Das wäre ein fester Empfänger statt der freien Wahl, ein neues
    Netzziel für Datenschutzerklärung und `docs/play-console.md` — und im
    Funkloch tot. Genau dort steht man, wenn man den Knopf drückt. Der
    Rückfall ist deshalb die Zwischenablage, und die App sagt es.
  - **Die Koordinate steht ZWEIMAL im URI** (`geo:<lat>,<lng>?q=<lat>,<lng>(<name>)`).
    Apps, die `q` auswerten, setzen darüber Pin und Titel; Apps, die es
    ignorieren, zentrieren auf den Pfad. Die verbreitete Kurzform
    `geo:0,0?q=…` schickt die zweite Gruppe in den Golf von Guinea.
  Für Data Safety ist das **keine Weitergabe**: nutzerinitiiert, mit dem
  Wähler als Bestätigung — dieselbe Ausnahme wie „Freunde sehen meine
  Spots", nachgeschrieben in Fußnote ¹ von `docs/play-console.md`.

- Beendigungsgründe (`lib/data/exit_info_repository.dart` + `exit_reporting.dart`,
  Issue #147): Beim Start liest die App über einen MethodChannel Androids
  eigene Historie (`getHistoricalProcessExitReasons`, ab Android 11, keine
  Berechtigung nötig für die eigenen Einträge) und meldet ANRs, Abstürze und
  Speicher-Kills nach `error_reports` — bei ANR mit dem Haupt-Thread-Abschnitt
  des Thread-Dumps. Das schließt die Lücke, die `logError` prinzipbedingt hat:
  Dort landet nur, was die App **überlebt**; ein ANR hinterlässt nichts, und
  genau deshalb blieb #142 unsichtbar, bis jemand ein USB-Kabel angesteckt hat.
  **Der einzige native Code im Projekt** (`MainActivity.kt`) — wer ihn anfasst,
  hat keinen Test als Netz, die Dart-Seite dagegen schon. Normale
  Beendigungen (`USER_REQUESTED`, `EXIT_SELF` …) werden bewusst NICHT
  gemeldet, sonst füllt jedes Wegwischen den Wochendigest (Lehre aus
  #124/#136). `created_at` ist der Todes-, nicht der Meldezeitpunkt. Ein
  Merker im App-Verzeichnis verhindert Doppelmeldungen; sein Verlust kostet
  nur eine doppelte Zeile. Web und Android < 11 liefern nichts.
  **Seit 1.122.0 kommt auch der NATIVE Absturz mit Spur** (#394): Android
  legt dafür seit API 31 ein Tombstone bereit, und der Kommentar „nur bei
  ANR liefert Android einen Dump" war seither falsch — der `CRASH_NATIVE`
  aus KW36 kam ohne eine Zeile an, obwohl sie bereitlag. Drei Dinge, die
  man wissen muss:
  - **Kotlin liest das Tombstone NICHT, es reicht es durch.** Es ist ein
    Protobuf; gelesen wird es in `lib/data/tombstone.dart`. Begründung:
    `MainActivity.kt` ist die einzige Datei ohne Test-Netz, ein Parser
    dort wäre der am wenigsten geprüfte Code an der am schlechtesten
    erreichbaren Stelle. Drüben prüfen erfundene Tombstones jeden Zweig.
    `test/android_manifest_test.dart` verbietet deshalb ausdrücklich ein
    `Tombstone.parseFrom` in Kotlin.
  - **Die Feldnummern stehen als Zahlen im Dart-Code**, nicht als
    kopierte `.proto`. Sie sind Teil eines veröffentlichten Formats
    („NOTE TO OEMS: do not use numbers in the reserved range") und ändern
    sich nicht rückwirkend; eine kopierte Datei müsste dagegen mit AOSP
    Schritt halten.
  - **`formatTombstone` wirft nie.** Der Weg dorthin IST die
    Fehlermeldung — ein Leser, der über ein unerwartetes Byte stolpert,
    nähme dem Bericht auch noch den Rest. Alles, was nicht passt, ergibt
    `null`, und der Bericht steht dann ohne Spur da wie zuvor.
  Die nativen Frames eines solchen Dumps übersetzt
  `python3 tool/symbolize_anr.py v1.32.0 dump.txt` — ohne dass beim Bauen
  irgendetwas aufgehoben werden muss: `(offset …)` im Dump ist die Position
  der Bibliothek in der APK (native Libs liegen dort unkomprimiert), das
  Release-Asset liefert die APK, und zu jedem Engine-Build veröffentlicht
  Flutter eine ungestrippte `libflutter.so`. Die Flutter-Version nimmt das
  Skript aus `release.yml` **im Tag selbst** — die Datei hat den Build
  gemacht, sie kann nicht danebenliegen. So kam in #151 heraus, dass der
  Haupt-Thread in `dart::MarkingVisitor::ProcessOldMarkingStack` stand,
  also im GC und nicht im Kartenrenderer. **Grenze:** `libapp.so` trägt im
  Release-Build gar keine Funktionssymbole (nur die vier Snapshot-Blobs);
  Frames im eigenen Dart-Code bleiben unbenannt, solange nicht mit
  `--split-debug-info` gebaut wird.
- Fehlerberichte: `logError` (`lib/core/errors.dart`) schreibt zusätzlich
  über einen optionalen `ErrorSink` nach `public.error_reports` (Patch 009,
  `ErrorReportRepository`). Eingehängt in `main()`, in Tests leer — deshalb
  bleibt `flutter test` netzfrei. Der Sink darf niemals werfen: ein Fehler
  beim Melden würde sonst wieder in `logError` landen. Bewusst kein
  Crash-Dienst: Abstürze zeigt Android Vitals in der Play Console ohnehin
  (nur Play-Installationen, nur Android); die Lücke sind die *gefangenen*
  Fehler, bei denen die App mit einer SnackBar weiterläuft — und Web sowie
  GitHub-APK, die Vitals nie sieht. Auswertung per SQL im Dashboard: die
  Tabelle hat absichtlich keine select-Policy.
- **Ausgangskorb** (`lib/data/outbox.dart` + `outbox_runner.dart` +
  `outbox_view.dart`, #267, seit 1.79.0): Lesen ohne Empfang konnte die
  App seit 1.44.0, Schreiben nicht — ein Fund im Funkloch war weg. Jetzt
  legen **genau zwei** Schreibwege ihren Auftrag lokal ab: neuer Spot und
  Fund/Leergang an einem Spot. Alles andere (korrigieren, löschen,
  zusammenführen, GPX-Import) scheitert weiter sichtbar; das ist
  Schreibtischarbeit im WLAN, und ein Löschauftrag, der Tage später
  zuschlägt, wäre schlimmer als eine Fehlermeldung.
  Sechs Dinge, die man wissen muss:
  - **Nur `looksOffline` führt in den Korb.** Ein Serverfehler muss
    sichtbar scheitern — sonst sammelte der Korb still Aufträge, die nie
    durchgehen, und ein kaputtes Deployment bliebe unbemerkt (dieselbe
    Regel wie im Zwischenspeicher, Lehre aus #80). Ein Flow-Test wacht
    darüber.
  - **Der Korb wirft beim Schreiben**, anders als `spot_cache.dart`: Der
    Cache ist eine Kopie, der Korb trägt das Original. Landet der Auftrag
    nicht auf der Platte, meldet die App den ursprünglichen Netzfehler
    weiter — „gespeichert" wäre eine Lüge.
  - **Der Auftrag entsteht VOR dem ersten Sendeversuch**, mit `client_id`
    je Spot und je Fund (Patch 016). Nur so trägt schon der erste Versuch
    die Kennung, und ein Abriss NACH dem Insert erzeugt beim Nachholen
    keinen zweiten Spot: Das Repository deutet `23505` als „stand schon"
    und holt sich die id von damals.
  - **Auflösen und Entfernen werden gemeinsam gültig** — der Runner
    schreibt am Ende den ganzen Korb neu (`replaceAll`). Ein Fund kann an
    einem Spot hängen, den es serverseitig noch nicht gibt; stürbe die App
    zwischen „Spot gesendet" und „Fund umgeschrieben", zeigte der Fund auf
    einen Auftrag, den es nicht mehr gibt.
  - **Wartende Einträge zählen überall mit** (Statistik, Ampel,
    GPX-Export) — sie sind passiert. Gesperrt ist nur das Ändern
    einzelner Einträge: dafür fehlt die Server-id. Auf der Karte sind sie
    blass mit Uhr (`MushroomIcon.pending`), sonst legt man denselben Spot
    zweimal an.
  - **`outbox/` gehört in beide Backup-Ausschlüsse** (`backup_rules.xml`,
    `full_backup_content.xml`) — dieselbe Begründung wie bei
    `spot_cache/`, nur schärfer: Hier stehen die Koordinaten, bevor sie
    irgendwo anders stehen. Beim Abmelden wird der Korb mitgelöscht,
    deshalb fragt das Profil vorher nach.
  - **Seit 1.116.0 gibt es ihn auch im Browser** (#386, `outbox_idb.dart`
    auf IndexedDB) — Einzelheiten oben beim Zwischenspeicher. Alles
    darüber bleibt unberührt: `outbox_view.dart`, `outbox_runner.dart`
    und die `client_id`-Idempotenz aus Patch 016 kennen nur die
    Schnittstelle.
  Ausgelöst wird die Wiedervorlage beim App-Start, bei der Rückkehr der
  Verbindung (`noConnectivityProvider`) und auf Tippen im Banner —
  bewusst NICHT am App-Resume: Wer aus dem Wald nach Hause kommt, ohne
  die App zu schließen, hat kein Resume, aber sehr wohl einen
  Netzwechsel.

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

## Play Store — offene Blocker

Fahrplan und Reihenfolge: Issue #92. Stand 2026-07-26 — noch offen:

Im Repo steckt kein Blocker mehr, und auch die Grafiken sind fertig
(`store/`: Icon 512×512, Feature-Grafik 1024×500, fünf Screenshots
1080×1920). Seit 1.87.1 ist auch der letzte Rest erledigt: Das AAB kommt
aus dem `play`-Flavor und trägt `REQUEST_INSTALL_PACKAGES` nicht mehr.
Offen ist nur noch, was in der Play Console passiert (#108, #91):
App-Eintrag anlegen, Data-Safety-Formular, Inhaltsbewertung, Store-Listing,
AAB hochladen.

Die Antworten dafür sind vorbereitet und aus dem Code abgeleitet:
**`docs/play-console.md`**. Ändert sich, was die App erhebt oder wohin sie
verbindet, gehört diese Datei in denselben PR — sonst laufen Formular und
Binary auseinander, und genau daran scheitern Play-Reviews.

**Die Frage, die den Zeitplan bestimmt** (#108): Gilt für das Konto die Regel
„12 Tester, 14 Tage durchgehend"? Persönliche Konten ab 2023-11-13 brauchen
das vor dem Produktions-Zugang. Die Antwort zeigt die Konsole erst nach dem
Anlegen des App-Eintrags, und die 14 Tage sind Kalenderzeit — alles andere
lässt sich parallel erledigen, das nicht.

**Paketname `de.mcbuchi.pilzbuddy`** (seit 1.88.0, vorher ein Paketname
mit dem Klarnamen des Betreibers): Umgestellt auf Wunsch des Betreibers, damit
sein Klarname nicht im Paket steht — und **vor** der ersten Einreichung,
weil Play die App ab dem ersten AAB-Upload unwiderruflich daran bindet.
Drei Folgen:

- **Für Android ist das eine andere App.** Der In-App-Updater FUNKTIONIERT
  trotzdem (er vergleicht nur Versionsnummern und übergibt die APK dem
  System-Installer, und ein noch nicht installiertes Paket wird schlicht
  installiert) — er ERSETZT die alte App nur nicht, sondern stellt die
  neue daneben. Die alte muss von Hand gelöscht werden.
  **Korrektur vom 2026-08-13:** Hier stand zuerst, der Installer lehne
  eine abweichende applicationId ab und es brauche eine Handinstallation.
  Das ist falsch — abgelehnt wird nur gleicher Paketname bei anderer
  Signatur. Die Anleitung im Changelog 1.88.0 war entsprechend falsch und
  ist in 1.90.0 richtiggestellt. Verloren gehen alle gerätelokalen Daten —
  Offline-Karten, `spot_cache/`, Einstellungen und der **Ausgangskorb**.
  Steht dort noch etwas, muss es VOR dem Wechsel gesendet sein. Auch das
  Push-Token hängt an der Installation: Benachrichtigungen sind in der
  neuen App wieder einzuschalten. Der Upload-Key bleibt unberührt — die
  Signatur hängt am Keystore, nicht am Paketnamen.
- **Firebase braucht eine eigene Registrierung je Paketname**, App-ID
  `…:android:25638619c3d5509a43dc77`. Während des Umzugs trug
  `google-services.json` beide Pakete, damit ein Build mit dem alten
  Namen nicht still ohne Push dasteht. Am 2026-08-13 hat der Betreiber
  die alte Registrierung gelöscht; die Datei ist seither frisch aus der
  Konsole geholt und trägt nur noch das neue Paket. **Sie wird geholt,
  nicht editiert** — der `mobilesdk_app_id` steht nur dort richtig.
  Folge der Löschung, falls doch noch jemand die alte App hat: Deren
  Push-Tokens sind ungültig, sie bekommt keine Meldungen mehr. Für den
  Umzug war das gewollt.
- **Sechs Stellen müssen gleichzeitig stimmen**, drei davon brechen
  still: Kotlin-Verzeichnis (sonst findet Gradle `.MainActivity` nicht)
  und die beiden MethodChannel-Namen (sonst antwortet niemand, und
  Beendigungsgründe wie APK-Installer hören ohne Fehlermeldung auf).
  `test/android_manifest_test.dart` prüft alle gegen die `applicationId`
  als einzige Quelle. Der Klarname steckte auch in `tool/measure_map.sh`
  und `docs/play-console.md`.

**Play App Signing** (Rest aus #111): Beim ersten AAB-Upload wird unser
Keystore zum *Upload-Key*, signiert wird danach von Google. Folge: Der
Play-Build hat eine **andere Signatur** als die GitHub-APK. Wer die APK
installiert hat, muss zum Wechsel einmal deinstallieren — Konto und Spots
liegen in Supabase und bleiben, verloren gehen nur heruntergeladene
Offline-Karten. Das gehört in die Tester-Einladung, sonst scheitert die
Installation wortlos mit „App nicht installiert".

Der Fingerprint des **Upload-Keys** (aus jeder veröffentlichten APK
ablesbar, also kein Geheimnis):

```
SHA-1    24:F7:09:2F:22:92:F5:CE:D0:3B:87:C0:5B:A1:B0:B0:53:96:1F:7D
SHA-256  CF:C8:C7:83:28:92:FA:71:B7:8A:54:51:DD:FB:76:F7:0F:B6:5A:59:0C:E3:F1:94:5B:7D:9B:89:2A:70:DC:E8
```

**Nicht** der Wert, der nach dem Upload in Firebase gehört: Die
ausgelieferte App trägt Googles App-Signing-Key, dessen Fingerprint erst
die Konsole zeigt (*Test und Veröffentlichung → Einrichtung →
App-Signatur*). Für FCM ist ohnehin keiner nötig — Push authentifiziert
über API-Key und Paketnamen, ein SHA bräuchte erst Google Sign-In, Maps
SDK, Dynamic Links oder App Check. Nachrechnen ohne Keystore:
`keytool -printcert -jarfile` scheitert (Flutter signiert nur v2/v3), es
braucht `apksigner verify --print-certs` oder den Signing-Block direkt.

Erledigt: Datenschutzerklärung (#90, `web/datenschutz.html`), Konto-Löschung
(#89), In-App-Updater entfernt (#88), AAB-Build (#87), Backup-Ausschluss
(#78). Der Build deklariert acht Berechtigungen, alle genutzt — einzeln
aufgeschlüsselt samt Herkunft in `docs/play-console.md`; zwei davon bringen
Plugins mit, und `RECEIVE_BOOT_COMPLETED` wird per `tools:node="remove"`
aktiv wieder entfernt.

Konto-Löschung: `public.delete_own_account()` (Patch 008), `security definer`
ohne Parameter — die id kommt aus `auth.uid()`, ein Argument wäre eine
Einladung, fremde Konten zu löschen. Löscht nur `auth.users`; alles andere
hängt per `on delete cascade` daran. Gegen die Live-DB mit einem
Wegwerf-Konto verifiziert (RPC 204, danach `invalid_credentials`).
Öffentliche Anleitung unter `web/konto-loeschen.html` (Play verlangt eine
URL ohne installierte App).

Unkritisch: `targetSdk` = 36 erfüllt die aktuelle Play-Anforderung,
`minSdk` = 24 (Android 7).
