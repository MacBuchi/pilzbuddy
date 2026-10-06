# PilzBuddy — Arbeitsregeln für `lib/core/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Im Vordergrund ist die SnackBar die einzige Anzeige** — und sie stellt
  sich hinten an. `ScaffoldMessenger.showSnackBar` reiht ein, statt zu
  ersetzen: Die Quittung des Testknopfs („Testnachricht ist unterwegs.",
  4 s) stand deshalb vor der Meldung, die sie ankündigte, und das sah wie
  ein Empfangsfehler aus. `PushListener` räumt jetzt erst
  (`clearSnackBars`) und zeigt dann.

- Supabase-Keys in `lib/core/supabase_config.dart` sind bewusst öffentlich
  (Publishable Key); niemals den service_role-Key einchecken.

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

