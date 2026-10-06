# PilzBuddy — Arbeitsregeln für `supabase/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

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

- Supabase-Free-Plan: Projekte werden nach ~1 Woche ohne Zugriff pausiert.
  Der Feedback-Bot-Cron (alle 2 h) und der Backup-Job halten das Projekt
  wach — das ist ab jetzt eine bewusste Zusage, kein Zufall: Wer beide
  Crons abschaltet, riskiert ein pausiertes Projekt und eine tote App.
  Grenzen: 500 MB Datenbank, 5 GB Egress. Die aktuelle Datenbankgröße steht
  wöchentlich in der Summary des Backup-Jobs — dort nachsehen, statt zu
  schätzen.

