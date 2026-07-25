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
- Version Guard in CI: Code-Änderung ohne Versions-Bump blockiert den Merge
  (Pflicht-Check schlägt fehl); nur `*.md`, `.github/`, `store/`, `tool/`
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
  funktioniert der Reset-Flow damit. Einen „Passwort ändern"-Dialog für
  Angemeldete gibt es weiter NICHT (Issue #127) — wer ihn baut, muss das
  aktuelle Passwort abfragen (erneutes `signIn`) und gegen die
  Live-Einstellung testen, `updateUser` allein scheitert dort.
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
  Von den sechs Mail-Vorlagen im Dashboard ist **nur „Reset password"**
  angepasst (deutsch, mit Code) — es ist die einzige, die die App auslöst.
  „Confirm sign up" (Bestätigung ist aus), „Magic link or OTP", „Invite
  user", „Change email address" und „Reauthentication" schlafen und stehen
  bewusst auf englischem Standardtext: Eine fertig aussehende Vorlage würde
  vortäuschen, das Feature existiere. Der Zahlencode kommt aus der
  Reset-Vorlage, NICHT aus „Magic link or OTP" — `/recover` verschickt,
  `verifyOTP` prüft nur. Wer „Confirm sign up" anschaltet, muss den
  Registrierungs-Screen mitziehen: `signUp` liefert dann keine Sitzung
  mehr, und genau darauf verlässt sich `signup_screen.dart` (ohne Anpassung
  bleibt die Registrierung stumm stehen). Anschalten ist dennoch fällig
  vor dem Play-Rollout (Issue #129): Freundessuche läuft über die exakte
  E-Mail-Adresse, und der Reset-Code geht an ein Postfach — beides
  verlässt sich darauf, dass die Adresse dem Konto wirklich gehört.
  Mitfahrbar hat die Bestätigungspflicht seit 2026-07-23 an; hier ist
  PilzBuddy der Nachzügler, nicht umgekehrt.
  Geprüft wird der Flow von `tool/auth_reset_check.sh` im Job „Schema Dry
  Run" — gegen echtes GoTrue im lokalen Stack, inklusive Mailabholung aus
  Mailpit. `supabase/config.toml` spiegelt dafür die Dashboard-Härtung
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
  Die Karte hat drei Schichten (Issues #118/#119): **unterste** die
  mitgelieferte DACH-Übersicht (`baseMapStyleProvider`, z0–7, ~9 MB im
  APK) — immer aktiv, unabhängig von Schalter und installierten Regionen,
  damit unter dem Finger nie eine leere Fläche liegt; **darüber** je nach
  Modus die Regionskarten oder OSM-Raster; **darüber** die Marker.
  Zwei Dinge machen das erst möglich und dürfen nicht zurückgedreht
  werden: Die Übersicht ist eine **eigene** Quelle (in der gemeinsamen
  Quelle mit den Regionen galt deren `maximumZoom`, und sie wurde nach
  Kacheln gefragt, die es in ihr nie gab — genau daher kam das Grau), und
  der Detail-Layer rendert mit einem Theme **ohne** `background`-Ebene
  (`styleWithoutBackground`), weil die sonst mit deckendem `#cccccc`
  genau dort die Basis zudeckt, wo sie gebraucht wird. Über seine
  Datentiefe hinaus skaliert der Renderer selbst hoch
  (`SlippyMapTranslator`) — deshalb reicht z7 für jede Zoomstufe.
  Folge fürs Risiko: Der Beta-Vektor-Renderer läuft jetzt bei allen, nicht
  nur bei Offline-Nutzern. Abgesichert bleibt es durch dieselbe Regel —
  lädt die Übersicht nicht, fällt der Layer weg (dann Hintergrundton).
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
- Bekannte Schuld: Farben sind als Hex-Literale über viele Dateien verstreut.
  Neuen Code nicht so schreiben — Farben/Abstände zentral halten und bei
  Berührung schrittweise auf Konstanten umstellen (Issue #53).
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

Fahrplan und Reihenfolge: Issue #92. Stand 2026-07-21 — noch offen:

Im Repo steckt kein Blocker mehr. Offen ist nur noch, was in der Play Console
passiert (#91): Data-Safety-Formular, Inhaltsbewertung, Store-Listing und die
Grafiken (Feature-Grafik 1024×500, Screenshots, Icon 512×512).

Die Antworten dafür sind vorbereitet und aus dem Code abgeleitet:
**`docs/play-console.md`**. Ändert sich, was die App erhebt oder wohin sie
verbindet, gehört diese Datei in denselben PR — sonst laufen Formular und
Binary auseinander, und genau daran scheitern Play-Reviews.

Erledigt: Datenschutzerklärung (#90, `web/datenschutz.html`), Konto-Löschung
(#89), In-App-Updater entfernt (#88), AAB-Build (#87), Backup-Ausschluss
(#78). Der Build deklariert nur noch acht Berechtigungen, alle genutzt.

Konto-Löschung: `public.delete_own_account()` (Patch 008), `security definer`
ohne Parameter — die id kommt aus `auth.uid()`, ein Argument wäre eine
Einladung, fremde Konten zu löschen. Löscht nur `auth.users`; alles andere
hängt per `on delete cascade` daran. Gegen die Live-DB mit einem
Wegwerf-Konto verifiziert (RPC 204, danach `invalid_credentials`).
Öffentliche Anleitung unter `web/konto-loeschen.html` (Play verlangt eine
URL ohne installierte App).

Unkritisch: `targetSdk` = 36 erfüllt die aktuelle Play-Anforderung,
`minSdk` = 24 (Android 7).
