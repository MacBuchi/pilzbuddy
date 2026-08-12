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
  Rhythmus nach Änderungsgrad, nicht nach Kalender (Betreiber, 2026-08-10).
  Das AAB entsteht weiter je Bump als Workflow-Artefakt `android-aab` —
  noch NICHT einreichbar, siehe Play-Store-Notiz unten.
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
  Gesetzt am 2026-08-11; Supabase gibt persönlichen Tokens **höchstens
  ein Jahr**, es läuft also spätestens am **2027-08-11** ab. Das ist der
  eine Fall, in dem der Job wirklich rot wird statt zu überspringen —
  das Secret ist dann ja da, nur ungültig. Wer hier landet: neues Token
  erzeugen, Secret ersetzen, fertig. Bewusst ein EIGENES Token und nicht
  das aus `supabase login` im Schlüsselbund: Sonst hinge die CI am
  interaktiven Anmeldetoken eines Rechners, und ein Widerruf auf der
  einen Seite legte still die andere lahm.
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
  gegenprüfen; bewusste Reste (RLS ohne Policy auf `applied_patches`,
  `authenticated` auf `search_profiles`/`delete_own_account`) dort dismissen.
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
  - Der Advisor-Fund bleibt dauerhaft stehen und gehört dismissed — nicht
    gesucht. Wer ihn das nächste Mal sieht, soll nicht wieder eine halbe
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
  siehe „Erzeugte Assets" weiter unten. Offline-Layer ist strikt optional:
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
- **Karten-Engine:** Seit 1.43.0 rendert Android standardmäßig mit
  MapLibre (nativer Renderer, `maplibre` 0.3.5 exakt gepinnt) hinter der
  MapView-Fassade (`lib/features/map/map_view/`); Grundlage ist der
  nachgemessene Direktvergleich in `docs/map-performance.md`
  (Wiederholung: `tool/measure_map.sh`). Der Profil-Schalter ist ein
  OPT-OUT zur bisherigen flutter_map-Karte (`classicMapEnabled`,
  bewusst neuer Prefs-Schlüssel — der alte Beta-Schlüssel
  `maplibre_enabled` wird ignoriert, sonst bliebe ein nie angefasstes
  Beta-„aus" als Opt-out kleben). Die Rückfalllinie bleibt mindestens
  eine Release-Reihe; der flutter_map-Android-Pfad wird erst nach einer
  Beobachtungsphase über den Wochendigest aufgeräumt. Web rendert
  weiterhin flutter_map (bedingter Import, Web-Build sieht
  `package:maplibre` nie). Die folgenden flutter_map-Notizen
  (Stellschrauben, Kamera-Wächter, TileProvider-Lebenszyklus) gelten
  für diesen Rückfall- und den Web-Pfad.
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
  **Offener Play-Punkt:** Diese Zeile darf nicht ins AAB. Der Dart-Pfad ist
  im Play-Build über `AppDistribution.showsUpdateHints` komplett aus, das
  Manifest ist es nicht — vor einer Einreichung Produkt-Flavors anlegen
  (Anleitung in `docs/play-console.md`).
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
  Ausgelöst wird die Wiedervorlage beim App-Start, bei der Rückkehr der
  Verbindung (`noConnectivityProvider`) und auf Tippen im Banner —
  bewusst NICHT am App-Resume: Wer aus dem Wald nach Hause kommt, ohne
  die App zu schließen, hat kein Resume, aber sehr wohl einen
  Netzwechsel.

## Code-Konventionen

- Business-Logik in Repositories/Services, nicht in Providern oder Widgets.
- Mutations-Muster: Repo-Call, dann `ref.invalidateSelf(); await future;`
  (Read-after-write statt optimistischem Update).
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
