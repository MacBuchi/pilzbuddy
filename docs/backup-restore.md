# Backup und Wiederherstellung

Der Supabase-Free-Plan hat **kein** Point-in-Time-Recovery und keine
automatischen Dumps. Eine fehlgeschlagene Migration oder ein versehentliches
`delete` trifft die Nutzerdaten ohne Zwischenstufe. Diese Seite beschreibt,
was dagegen läuft und wie man im Ernstfall zurückkommt.

## Was gesichert wird

`.github/workflows/backup.yml` zieht montags 03:17 UTC (und auf Zuruf per
`workflow_dispatch`) einen `pg_dump` der Schemata `public`, `app_internal`
und `auth`, verschlüsselt ihn mit age und legt ihn als Release-Asset im
**privaten** Repo `MacBuchi/pilzbuddy-backups` ab.

- `auth` ist mit drin, weil ohne `auth.users` niemand sich mehr anmelden
  könnte und `public.profiles` per Fremdschlüssel daran hängt.
- `app_internal` ist mit drin, weil dort die Policy-Helfer liegen
  (Patch 011) — ohne sie scheitert schon `CREATE POLICY` beim Einspielen.
  Dass das Schema anfangs fehlte, hat der allererste Restore-Versuch
  aufgedeckt (siehe unten).
- Vor dem Verschlüsseln prüft `tool/db_backup.sh`, ob die erwarteten
  Tabellen wirklich im Dump stehen. Ein halber Dump wird nicht hochgeladen —
  sich fälschlich gesichert zu glauben ist schlimmer als kein Backup.
- Aufbewahrt werden die letzten **12** Backups (~3 Monate). Lang genug, um
  einen Schaden zu bemerken; kurz genug, dass die Daten eines gelöschten
  Kontos nicht unbegrenzt in Backups weiterleben.

## Der Schlüssel

Verschlüsselt wird **asymmetrisch**: der öffentliche age-Schlüssel steht im
Klartext in `tool/db_backup.sh`, der private liegt ausschließlich in
`~/pilzbuddy-keys/pilzbuddy-backup.agekey` — neben dem Keystore-Backup und
**nie** in GitHub. Wer sich Zugang zu Repo oder Backup-Ablage verschafft,
bekommt Chiffrat und sonst nichts.

> ⚠️ Geht `pilzbuddy-backup.agekey` verloren, sind **alle** Backups wertlos.
> Der Ordner `~/pilzbuddy-keys/` gehört auf dasselbe Sicherungsmedium wie der
> Keystore.

## Einmaliges Setup

1. Privates Repo `MacBuchi/pilzbuddy-backups` anlegen — **mit README**.
   Ein leeres Repo hat keinen Standard-Branch, und `gh release create`
   scheitert dann.
2. Fein granulares PAT erzeugen (GitHub → Settings → Developer settings →
   Personal access tokens → Fine-grained): Zugriff **nur** auf
   `pilzbuddy-backups`, Berechtigung `Contents: Read and write`.
3. Das Token im Repo `pilzbuddy` als Secret `BACKUP_REPO_TOKEN` hinterlegen.
4. Kalendereintrag zum Ablaufdatum des PAT — läuft es ab, schlägt der Job
   fehl (GitHub mailt bei fehlgeschlagenen geplanten Läufen).

## Wiederherstellung

Voraussetzung: `age` und `psql` lokal, `~/pilzbuddy-keys/pilzbuddy-backup.agekey`
zur Hand.

```bash
# 1. Gewünschtes Backup holen
gh release list --repo MacBuchi/pilzbuddy-backups
gh release download backup-2026-07-27 --repo MacBuchi/pilzbuddy-backups

# 2. Entschlüsseln
age -d -i ~/pilzbuddy-keys/pilzbuddy-backup.agekey \
  -o pilzbuddy.sql pilzbuddy-2026-07-27.sql.age

# 3. Plausibilität prüfen, BEVOR irgendwo eingespielt wird
grep -c 'INSERT INTO\|COPY ' pilzbuddy.sql
grep 'CREATE TABLE "public"."spots"' pilzbuddy.sql

# 4. In ein FRISCHES Supabase-Projekt einspielen (nie zuerst in die
#    Produktion — siehe Übung unten)
psql "<session-pooler-uri-des-zielprojekts>" -v ON_ERROR_STOP=1 -f pilzbuddy.sql
```

Danach im Zielprojekt gegenprüfen:

```sql
select count(*) from public.spots;
select count(*) from public.finds;
select count(*) from auth.users;
select minimum_supported_version from public.app_config;
```

### Ernstfall in der Produktion

Reihenfolge, wenn die echte Datenbank beschädigt ist:

1. **Zuerst** einen Dump des aktuellen (kaputten) Zustands ziehen:
   Workflow `Database Backup` manuell starten. Ohne den ist der Schaden
   nach dem Einspielen nicht mehr analysierbar.
2. Backup wie oben in ein Wegwerf-Projekt einspielen und dort prüfen, ob es
   den gewünschten Stand enthält.
3. Erst dann in die Produktion — `public` und `auth` vorher leeren bzw. das
   Projekt neu aufsetzen und `supabase/schema.sql` überspringen (der Dump
   bringt das Schema mit).
4. `tool/schema_check.sh` laufen lassen: passt das wiederhergestellte Schema
   noch zu den App-Queries?

## Restore-Übung

Ein nie zurückgespieltes Backup ist kein Backup.

Seit 2026-07-25 läuft die Übung automatisiert und wöchentlich auf eigener
Hardware des Betreibers: Das jeweils neueste Backup wird entschlüsselt, in
eine lokale PostgreSQL 17 eingespielt (`ON_ERROR_STOP`) und gegen die
Zählwerte aus dem Release-Text geprüft; Ablauf, Skripte und Protokoll
liegen bewusst im privaten Repo `pilzbuddy-backups`. Die manuelle Übung
unten bleibt der Weg für den Restore in ein echtes Supabase-Projekt.

- Wegwerf-Supabase-Projekt anlegen (Free Plan, beliebige Region)
- Neuestes Backup wie oben entschlüsseln und einspielen
- Die vier Zähl-Queries oben ausführen und mit der Produktion vergleichen
- Projekt wieder löschen

### Stand 2026-07-25: Inhalt geprüft, Einspielen noch nicht

Das erste Backup (`backup-2026-07-25`) wurde heruntergeladen und mit
`~/pilzbuddy-keys/pilzbuddy-backup.agekey` entschlüsselt. Der Klartext enthielt:

| Prüfung | Ergebnis |
|---|---|
| Chiffrat-Kopfzeile | `age-encryption.org/v1` |
| Entschlüsselung mit dem privaten Schlüssel | erfolgreich, 160 926 Bytes |
| Schema `public` | alle Tabellen inkl. `app_config`, `applied_patches`, `error_reports`, `feedback`, `live_locations` |
| Schema `auth` | 23 Tabellen inkl. `users`, `identities`, `refresh_tokens`, `sessions` |
| Nutzdaten | 6 profiles, 6 auth.users, 32 spots, 32 finds, 1 friendship, 1 app_config |
| RLS | 16 Policies, RLS auf 25 Tabellen aktiviert |

Die Zahlen sind in sich stimmig (6 profiles ↔ 6 auth.users, weil das Profil
per Trigger aus `auth.users` entsteht) und decken sich mit dem, was der Job
aus der Live-Datenbank gemeldet hat (32 Spots).

**Damit ist bewiesen: Das Backup ist entschlüsselbar und inhaltlich
vollständig.** Der entschlüsselte Dump wurde nach der Prüfung sofort
gelöscht — er enthält E-Mail-Adressen, Passwort-Hashes und Koordinaten.

### Stand 2026-07-25, später am Tag: der erste Restore-Versuch widerlegt das

„Inhaltlich vollständig" hat den Praxistest nicht überlebt: Der erste
automatisierte Restore-Versuch (lokale PostgreSQL 17, `ON_ERROR_STOP`)
brach beim Einspielen ab — das Schema `app_internal` mit den
Policy-Helfern aus Patch 011 fehlte im Dump, und damit scheiterte schon
`CREATE POLICY`. Ein Backup, das sich entschlüsseln, aber nicht
einspielen lässt, ist keins. Der Dump sichert seither auch
`app_internal`, und `tool/db_backup.sh` prüft die Helfer vor dem
Hochladen mit — genau für diese Fehlerklasse existiert die Übung.

Zwei weitere Befunde desselben Laufs, beide im Drill-Skript dokumentiert:
Der Dump bringt `CREATE SCHEMA "public"` mit (Zielschema vorher leeren,
wie oben im Ernstfall-Ablauf beschrieben), und er erwartet die
Supabase-Standardrollen (in einem echten Supabase-Zielprojekt vorhanden,
in blankem Postgres nicht).

**Offen bleibt der Restore in ein echtes Supabase-Projekt:** Der Drill
beweist, dass das SQL durchläuft — nicht das Zusammenspiel mit GoTrue in
einem Wegwerf-Projekt aus dem Supabase-Dashboard (#111).

**Letzter vollständiger Restore in ein Supabase-Projekt: _noch keiner_.**
Datum und Ergebnis hier eintragen, sobald er gelaufen ist.
