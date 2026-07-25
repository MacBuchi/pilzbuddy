# Backup und Wiederherstellung

Der Supabase-Free-Plan hat **kein** Point-in-Time-Recovery und keine
automatischen Dumps. Eine fehlgeschlagene Migration oder ein versehentliches
`delete` trifft die Nutzerdaten ohne Zwischenstufe. Diese Seite beschreibt,
was dagegen läuft und wie man im Ernstfall zurückkommt.

## Was gesichert wird

`.github/workflows/backup.yml` zieht montags 03:17 UTC (und auf Zuruf per
`workflow_dispatch`) einen `pg_dump` der Schemata `public` und `auth`,
verschlüsselt ihn mit age und legt ihn als Release-Asset im **privaten** Repo
`MacBuchi/pilzbuddy-backups` ab.

- `auth` ist mit drin, weil ohne `auth.users` niemand sich mehr anmelden
  könnte und `public.profiles` per Fremdschlüssel daran hängt.
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

- Wegwerf-Supabase-Projekt anlegen (Free Plan, beliebige Region)
- Neuestes Backup wie oben entschlüsseln und einspielen
- Die vier Zähl-Queries oben ausführen und mit der Produktion vergleichen
- Projekt wieder löschen

**Letzte durchgeführte Übung: _noch keine_.**
Datum und Ergebnis hier eintragen, sobald sie gelaufen ist. Solange diese
Zeile leer ist, gilt das Backup als ungeprüft.
