# PilzBuddy — Arbeitsregeln

Flutter-App (Android + Web): Pilz-Spots auf OpenStreetMap-Karte, Supabase-Backend
(Auth + PostgreSQL, Freigabe-Regeln komplett über RLS in `supabase/schema.sql`),
Riverpod ohne Codegen, go_router, deutsche UI-Strings direkt im Code.

## Workflow

- Kein direkter Push auf `main` (Branch ist geschützt): Feature-Branch
  (`feat/<thema>` / `fix/<thema>`) → PR → CI grün → Squash-Merge.
- Commit-/PR-Titel: Conventional Commits (`feat:`, `fix:`, `chore:`, `ci:`, …).
- Release = Versions-Bump in `pubspec.yaml` auf `main` (beide Teile erhöhen,
  z. B. `1.0.1+2`). Der Release-Workflow taggt dann `v<version>`, veröffentlicht
  die signierte APK als GitHub-Release und deployt Web auf GitHub Pages
  (https://macbuchi.github.io/pilzbuddy/). Kein Bump = kein Release.
- Version Guard in CI: Code-Änderung ohne Bump → Warnung im PR, Fehler auf main.

## Technik-Notizen

- Signing: `android/key.properties` + `android/pilzbuddy-release.jks` (beide
  gitignored; Backup in `~/pilzbuddy-keys/`). CI erzeugt beides aus den Secrets
  `ANDROID_KEYSTORE_*`. PKCS12: keyPassword == storePassword.
- Web-Builds für Pages brauchen `--base-href /pilzbuddy/` und eine `404.html`
  (Kopie von `index.html`) als SPA-Fallback.
- Datenbank-Änderungen: `supabase/schema.sql` aktuell halten (Frischinstallation)
  UND als nummeriertes `supabase/patch_NNN_*.sql` ablegen (Bestandsprojekt);
  Patches führt der Betreiber manuell im Supabase-SQL-Editor aus.
- Flutter-Version in CI gepinnt (subosito/flutter-action, aktuell 3.41.2) —
  bei lokalem Flutter-Upgrade auch `.github/workflows/*.yml` anpassen.
- Supabase-Keys in `lib/core/supabase_config.dart` sind bewusst öffentlich
  (Publishable Key); niemals den service_role-Key einchecken.
