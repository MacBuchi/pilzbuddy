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
  (Pflicht-Check schlägt fehl); nur `*.md` und `.github/` sind ausgenommen.
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
  Sicherheitsnetz vor dem Ausliefern. Braucht das Repo-Secret
  `SUPABASE_DB_URL` (Supabase Session-Pooler-URI inkl. DB-Passwort; der
  Schema Check selbst läuft ohne Secret über den Publishable Key).
  Nutzt ein Repository in `lib/data/` neue Spalten/Embeds/RPCs, die
  Checks in `tool/schema_check.sh` entsprechend erweitern.
- Flutter-Version in CI gepinnt (subosito/flutter-action, aktuell 3.41.2) —
  bei lokalem Flutter-Upgrade auch `.github/workflows/*.yml` anpassen.
- Supabase-Keys in `lib/core/supabase_config.dart` sind bewusst öffentlich
  (Publishable Key); niemals den service_role-Key einchecken.
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
  Braucht das Repo-Secret `SUPABASE_SERVICE_ROLE_KEY`. Selbsttest:
  `python3 tool/feedback_bot.py --test-insert "Name"`.
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

- `flutter analyze` + `flutter test` nach jeder Änderung.
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

Fahrplan und Reihenfolge: Issue #92. Stand 2026-07-20 — noch offen:

1. **Konto-Löschung** (#89) fehlt komplett. Play verlangt sie in der App *und*
   über eine Web-URL; serverseitig braucht es einen Schema-Patch (Auth-User
   plus abhängige Zeilen).
2. **Datenschutzerklärung** (#90) fehlt. Pflicht für die Konsole, inhaltlich
   nicht trivial: Spot-Koordinaten, Live-Standort, E-Mail, Benutzername — und
   Feedback, das mit Benutzernamen öffentlich auf GitHub landet.
3. **Data-Safety-Formular** (#91) in der Konsole, abgeleitet aus
   `supabase/schema.sql`.

Erledigt: In-App-Updater entfernt (#88), AAB-Build (#87), Backup-Ausschluss
(#78). Der Build deklariert jetzt nur noch acht Berechtigungen, alle genutzt.

Unkritisch: `targetSdk` = 36 erfüllt die aktuelle Play-Anforderung,
`minSdk` = 24 (Android 7).
