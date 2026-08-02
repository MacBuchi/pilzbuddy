# PilzBuddy — Arbeitsregeln

Flutter-App (Android + Web): Pilz-Spots auf OpenStreetMap-Karte, Supabase-Backend
(Auth + PostgreSQL, Freigabe-Regeln komplett über RLS in `supabase/schema.sql`),
Riverpod ohne Codegen, go_router, deutsche UI-Strings direkt im Code.

Projektübergreifende Guidelines (Architektur, State, Testing, CI, Signing,
In-App-Update/-Feedback) liegen im DocuHub:
`/Volumes/MacStore/Programming/ProgrammingGuidelineDocuHub/`. Diese Datei
beschreibt nur, was für PilzBuddy davon abweicht oder zusätzlich gilt.

## Workflow

- Kein direkter Push auf `main` (Branch ist geschützt): Feature-Branch
  (`feat/<thema>` / `fix/<thema>`) → PR → CI grün → Squash-Merge.
- Commit-/PR-Titel: Conventional Commits (`feat:`, `fix:`, `chore:`, `ci:`, …).
- Sprache: Auf GitHub wird Englisch gesprochen — Commit-Messages, PR-Titel und
  -Beschreibungen, Issues und Kommentare auf Englisch. Deutsch bleibt für
  UI-Strings, Nutzer-Doku (README) und die Kommunikation mit dem Betreiber.
- Release = Versions-Bump in `pubspec.yaml` auf `main` (beide Teile erhöhen,
  z. B. `1.0.1+2`). Der Release-Workflow taggt dann `v<version>`, veröffentlicht
  die signierte APK als GitHub-Release und deployt Web auf GitHub Pages
  (zusätzlich entsteht ein signiertes AAB als Workflow-Artefakt `android-aab`
  für den Play Store — noch NICHT einreichbar, siehe Play-Store-Notiz unten)
  (https://macbuchi.github.io/pilzbuddy/). Kein Bump = kein Release.
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

## Technik-Notizen

- Signing: `android/key.properties` + `android/pilzbuddy-release.jks` (beide
  gitignored; Backup in `~/pilzbuddy-keys/`). CI erzeugt beides aus den Secrets
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
  Vorgeschaltet ist der Pflicht-Check „Schema Dry Run" (`needs:` am Schema
  Check): ein lokaler Supabase-Stack auf dem Runner (`supabase/config.toml`,
  bewusst minimal — nur db, auth, api) stellt die Frischinstallation nach:
  `schema.sql` einspielen, dieselben Patches per `db_migrate.sh` obendrauf
  (beweist die geforderte Idempotenz), dann `schema_check.sh` mit
  `SUPABASE_URL`/`SUPABASE_KEY`-Override gegen den frischen Stack. Erst
  wenn das grün ist, fasst der Schema Check die Live-DB an — ein kaputtes
  `schema.sql` oder ein fehlerhafter Patch fällt damit VOR der Produktion
  auf. Lokal derselbe Ablauf: `supabase start`, dann die drei Schritte
  (psql via `brew install libpq`; lokalen anon-Key liefert
  `supabase status -o json`). Achtung: `config.toml` setzt
  `auto_expose_new_tables = true` (Legacy-Verhalten des Bestandsprojekts);
  das Feld fällt am 2026-10-30 weg — bis dahin gehören explizite Grants in
  `schema.sql`, dann kann die Zeile raus. Braucht das Repo-Secret
  `SUPABASE_DB_URL` (Supabase Session-Pooler-URI inkl. DB-Passwort; der
  Schema Check selbst läuft ohne Secret über den Publishable Key).
  Nutzt ein Repository in `lib/data/` neue Spalten/Embeds/RPCs, die
  Checks in `tool/schema_check.sh` entsprechend erweitern.
  Patches > Baseline laufen bei einer Frischinstallation NACH dem aktuellen
  `schema.sql` erneut — sie müssen dagegen idempotent bleiben; notfalls einen
  alten Patch rückwirkend anpassen (so geschehen in `patch_007`, als
  Patch 011 die Helfer verschob).
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
  gegenprüfen; bewusste Reste (RLS ohne Policy auf `applied_patches`,
  `authenticated` auf `search_profiles`/`delete_own_account`) dort dismissen.
- Flutter-Version in CI gepinnt (subosito/flutter-action, aktuell 3.41.2) —
  bei lokalem Flutter-Upgrade auch `.github/workflows/*.yml` anpassen.
- Supabase-Keys in `lib/core/supabase_config.dart` sind bewusst öffentlich
  (Publishable Key); niemals den service_role-Key einchecken.
- Supabase-Auth-Härtung im Dashboard (seit 2026-07-22 aktiv): Leaked Password
  Protection (HaveIBeenPwned-Abgleich bei Registrierung) und „Secure password
  change" — Passwort-Änderungen über die Auth-API verlangen das aktuelle
  Passwort bzw. eine frische Re-Authentifizierung, ein gestohlenes
  Session-Token allein reicht nicht für eine Kontoübernahme. Eine frisch per
  Reset-Code angelegte Sitzung gilt als frische Authentifizierung, deshalb
  funktioniert der Reset-Flow damit.
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
  Von den sechs Mail-Vorlagen im Dashboard sind **zwei** angepasst (deutsch,
  mit Code): „Reset password" und „Confirm sign up" — genau die beiden, die
  die App auslöst. „Magic link or OTP", „Invite user", „Change email address"
  und „Reauthentication" schlafen und stehen bewusst auf englischem
  Standardtext: Eine fertig aussehende Vorlage würde vortäuschen, das Feature
  existiere. Der Zahlencode kommt aus der jeweiligen Vorlage, NICHT aus
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
  Geprüft werden die Flows von `tool/auth_reset_check.sh` im Job „Schema Dry
  Run" — gegen echtes GoTrue im lokalen Stack, inklusive Mailabholung aus
  Mailpit: Registrierung samt Bestätigung, Reset und Passwortwechsel (der
  Name des Skripts ist seit #127/#129 zu eng). `supabase/config.toml`
  spiegelt dafür die Dashboard-Härtung
  (`[auth.email] secure_password_change = true`), damit lokal nicht laxer
  geprüft wird als live; die Mail-Vorlage liegt als versionierte Kopie in
  `supabase/templates/recovery.html`. **Blinder Fleck:** Die im Dashboard
  hinterlegte Vorlage sieht CI nie. Wer sie dort auf den Link zurückstellt,
  bricht „Passwort vergessen" in Produktion, während CI grün bleibt —
  Vorlage also immer an beiden Stellen ändern.
- Offline-Karten (`lib/features/offline_maps/`, nur Android): Bundesland-
  PMTiles (Protomaps Basemap v4, ODbL) aus den GitHub-Releases von
  `whitespring/project-nomad-maps-europe`; Katalog entsteht dynamisch aus
  der Release-Asset-Liste (`<key>_<JJJJMMTT>.pmtiles`). Rendering über
  vector_map_tiles (exakt gepinnte Beta — nur Beta-Versionen können
  flutter_map 8; bewusst die 9er-Linie mit Canvas-Renderer, die 10er zieht
  den GPU-Stack samt CMake-Native-Builds nach sich). Style-Asset
  `assets/map_style/protomaps_light_de.json` ist generiert
  (npm `@protomaps/basemaps`, Flavor LIGHT, lang de) — nicht von Hand
  editieren, sondern neu generieren. Offline-Layer ist strikt optional:
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
  Der Download läuft im Main-Isolate und braucht deshalb einen
  Foreground-Service (`flutter_foreground_task`, Typ `dataSync`) —
  ohne den friert Android den Prozess beim App-Wechsel ein und der
  Download steht still. Eingebunden über `downloadKeepAliveProvider`
  mit bedingtem Import (`download_keep_alive_stub.dart` für Web, sonst
  `download_keep_alive_service.dart`), damit der Web-Build das
  Android-Paket nie sieht; Tests überschreiben den Provider.
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
  `python3 tool/feedback_bot.py --test-insert "Name"` und `--test-digest`.
- Backup (`.github/workflows/backup.yml` + `tool/db_backup.sh`, montags plus
  `workflow_dispatch` vor größeren Migrationen): `pg_dump` von `public`,
  `app_internal` und `auth`, mit age verschlüsselt, als Release-Asset im **privaten** Repo
  `pilzbuddy-backups` (dieses Repo ist öffentlich, seine Artefakte wären es
  auch). Verschlüsselt wird asymmetrisch — der öffentliche Schlüssel steht
  im Skript, der private liegt **nur** in
  `~/pilzbuddy-keys/pilzbuddy-backup.agekey` und nie in GitHub; sein Verlust
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
  tokenlos gegen `releases/latest`; der Dialog schickt zum Download in den
  Browser, die Installation macht der Nutzer. **Kein `ota_update` mehr** —
  dessen Plugin-Manifest zog `INSTALL_PACKAGES` (Signatur-Berechtigung),
  `REQUEST_INSTALL_PACKAGES` und `WRITE_EXTERNAL_STORAGE` in jeden Build,
  und Play verbietet Selbst-Updates. `test/android_manifest_test.dart`
  wacht darüber, dass die Abhängigkeit nicht zurückkommt.
  Der ganze Pfad hängt an `AppDistribution.showsUpdateHints`
  (`lib/core/app_distribution.dart`): im Play-Build via
  `--dart-define=PLAY_BUILD=true` abgeschaltet, weil Play dort selbst
  aktualisiert und Verweise auf APK-Downloads unzulässig sind.
  Der `<queries>`-Eintrag VIEW/https im Manifest bleibt nötig, sonst kann
  die App den Browser nicht öffnen.

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

## Code-Konventionen

- Business-Logik in Repositories/Services, nicht in Providern oder Widgets.
- Mutations-Muster: Repo-Call, dann `ref.invalidateSelf(); await future;`
  (Read-after-write statt optimistischem Update).
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
- Kein Netzwerk in Tests (Update-Check ist im Harness auf `null` überschrieben,
  Kartenkacheln werden durch eine transparente 1×1-PNG ersetzt).
- Die Fakes ersetzen keinen echten RLS-Test — das leistet der Schema Check.

## Play Store — offene Blocker

Fahrplan und Reihenfolge: Issue #92. Stand 2026-07-26 — noch offen:

Im Repo steckt kein Blocker mehr, und auch die Grafiken sind fertig
(`store/`: Icon 512×512, Feature-Grafik 1024×500, fünf Screenshots
1080×1920). Offen ist nur noch, was in der Play Console passiert (#108, #91):
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

**Play App Signing** (Rest aus #111): Beim ersten AAB-Upload wird unser
Keystore zum *Upload-Key*, signiert wird danach von Google. Folge: Der
Play-Build hat eine **andere Signatur** als die GitHub-APK. Wer die APK
installiert hat, muss zum Wechsel einmal deinstallieren — Konto und Spots
liegen in Supabase und bleiben, verloren gehen nur heruntergeladene
Offline-Karten. Das gehört in die Tester-Einladung, sonst scheitert die
Installation wortlos mit „App nicht installiert".

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
