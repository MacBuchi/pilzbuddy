# PilzBuddy — Arbeitsregeln für `.github/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

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

- Flutter-Version in CI gepinnt (subosito/flutter-action, aktuell 3.47.5) —
  bei lokalem Flutter-Upgrade auch `.github/workflows/*.yml` anpassen. Es
  sind **sieben** Stellen in fünf Dateien: dreimal `ci.yml`, je einmal
  `preview.yml`, `release.yml` und `security.yml`, dazu `FLUTTER_VERSION`
  in `promote.yml` (`preview.yml` fehlte hier bis #621). Vollständig ist
  die Liste mit `grep -rn "flutter-version\|FLUTTER_VERSION"
  .github/workflows`. Der Eintrag in `release.yml` ist nicht nur Build-Sache —
  `tool/symbolize_anr.py` liest ihn aus dem TAG, um die passende
  ungestrippte `libflutter.so` zu holen; steht dort die falsche Version,
  sind die nativen Frames stumm falsch benannt.
  Die Drift lokal↔CI ist am 2026-08-11 aufgelöst worden (3.41.2 → 3.44.8,
  Betreiber: „3.44 soll auch in der CI laufen"). Zweite Drift aufgelöst am
  2026-09-26 (3.44.8 → 3.47.5, #621): Sie zeigte sich als Analyzer-Warnung
  (`unawaited_return_in_try_block`), die lokal kam und in CI nicht. Vorher hieß die Regel,
  `pubspec.lock` vor dem Commit zurückzunehmen — das ging nur, solange
  keine neue Abhängigkeit dazukam.

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

