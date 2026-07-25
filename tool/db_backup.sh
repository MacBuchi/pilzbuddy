#!/usr/bin/env bash
# Encrypted backup of the live Supabase database.
#
# The free plan has no point-in-time recovery and no automatic dumps: a bad
# migration or an accidental delete hits user data with no way back. This is
# that way back.
#
# Encryption is asymmetric on purpose. The recipient below is the PUBLIC age
# key and may live in this repository; the private key exists only in
# ~/pilzbuddy-keys/pilzbuddy-backup.agekey on the operator's machine and
# never reaches GitHub. Someone who breaks into the repository or the
# backup store gets ciphertext and nothing else.
#
# Requires SUPABASE_DB_URL (Session-Pooler URI incl. password, GitHub
# secret — the same one tool/db_migrate.sh uses). Uploading additionally
# needs GH_TOKEN with contents:write on BACKUP_REPO.
#
# Local dry run (dump + verify + encrypt, no upload):
#     SUPABASE_DB_URL=... bash tool/db_backup.sh --no-upload
#
# pg_dump must not be older than the server (17.x) or it refuses to run.
# Where the default one is too old, point at the right binary:
#     PG_DUMP=/opt/homebrew/opt/postgresql@17/bin/pg_dump
set -euo pipefail

PG_DUMP="${PG_DUMP:-pg_dump}"
PSQL="${PSQL:-psql}"

# Öffentlicher age-Schlüssel — Chiffrat, kein Geheimnis. Der private Teil
# liegt ausschließlich in ~/pilzbuddy-keys/pilzbuddy-backup.agekey.
RECIPIENT="${BACKUP_AGE_RECIPIENT:-age1cvve78dxxq8axsa6kvhe4ynm2m6waavf3s7x4ayaqvhy8pwpj5tsw3l7rr}"
BACKUP_REPO="${BACKUP_REPO:-MacBuchi/pilzbuddy-backups}"

# Wie viele Backups aufbewahrt werden. Zwölf Wochenläufe sind lang genug,
# um einen Schaden zu bemerken, und kurz genug, dass ein gelöschtes Konto
# nicht unbegrenzt in Backups weiterlebt (Art. 17 DSGVO) — die Zahl steht
# so auch in docs/backup-restore.md.
KEEP="${BACKUP_KEEP:-12}"

upload=1
[ "${1:-}" = "--no-upload" ] && upload=0

DB_URL="${SUPABASE_DB_URL:-}"
if [ -z "$DB_URL" ]; then
  echo "::error::SUPABASE_DB_URL fehlt — ohne die Session-Pooler-URI (inkl. DB-Passwort) kann kein Dump gezogen werden."
  exit 1
fi

stamp=$(date -u +%Y-%m-%d)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
dump="$workdir/pilzbuddy-$stamp.sql"

echo "→ Dump wird gezogen (Schemata public + auth) …"
# auth muss mit: ohne auth.users kann sich nach einer Wiederherstellung
# niemand mehr anmelden, und public.profiles hängt per Fremdschlüssel daran.
# Ownership/Grants bleiben drin — die Rollen (anon, authenticated,
# service_role) heißen in jedem Supabase-Projekt gleich, und ohne die
# Grants wäre die wiederhergestellte DB ohne RLS-Rechte.
$PG_DUMP "$DB_URL" \
  --schema=public \
  --schema=auth \
  --no-comments \
  --quote-all-identifiers \
  --file="$dump"

# Ein leerer oder halber Dump, der still hochgeladen wird, ist schlimmer
# als gar kein Backup: man hält sich für gesichert und ist es nicht.
echo "→ Dump wird geprüft …"
missing=""
# --quote-all-identifiers macht daraus CREATE TABLE "public"."spots" (…
for table in public.profiles public.spots public.finds \
             public.friendships public.app_config auth.users; do
  schema=${table%%.*}
  name=${table#*.}
  grep -q "CREATE TABLE \"$schema\".\"$name\"" "$dump" || missing="$missing $table"
done
if [ -n "$missing" ]; then
  echo "::error::Dump unvollständig — diese Tabellen fehlen:$missing. Nichts hochgeladen."
  exit 1
fi

rows=$("$PSQL" "$DB_URL" -qtA -c \
  "select count(*) from public.spots" 2>/dev/null || echo "?")
db_size=$("$PSQL" "$DB_URL" -qtA -c \
  "select pg_size_pretty(pg_database_size(current_database()))" 2>/dev/null || echo "?")
dump_size=$(du -h "$dump" | cut -f1)

echo "→ Wird verschlüsselt (age, Empfänger $RECIPIENT) …"
age -r "$RECIPIENT" -o "$dump.age" "$dump"
enc_size=$(du -h "$dump.age" | cut -f1)

# Gegenprobe, dass die Datei wirklich als age-Chiffrat vorliegt und nicht
# etwa der Klartext durchgereicht wurde.
head -c 20 "$dump.age" | grep -q "age-encryption.org" || {
  echo "::error::Ausgabe ist kein age-Chiffrat — Abbruch, bevor irgendetwas hochgeladen wird."
  exit 1
}

summary="Datenbank: $db_size · Dump: $dump_size · verschlüsselt: $enc_size · Spots: $rows"
echo "✓ $summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Backup $stamp"
    echo ""
    echo "- Datenbankgröße: **$db_size** (Free-Plan-Grenze: 500 MB)"
    echo "- Dump: $dump_size, verschlüsselt: $enc_size"
    echo "- Spots in der Datenbank: $rows"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$upload" -eq 0 ]; then
  echo "--no-upload: Datei bleibt liegen unter $dump.age"
  cp "$dump.age" "./pilzbuddy-$stamp.sql.age"
  echo "Kopiert nach ./pilzbuddy-$stamp.sql.age"
  exit 0
fi

if [ -z "${GH_TOKEN:-}" ]; then
  echo "::error::GH_TOKEN fehlt — das Backup wurde erstellt, kann aber nicht abgelegt werden. Repo-Secret BACKUP_REPO_TOKEN anlegen (fein granulares PAT, nur contents:write auf $BACKUP_REPO)."
  exit 1
fi

echo "→ Wird abgelegt in $BACKUP_REPO …"
tag="backup-$stamp"
# Ein zweiter Lauf am selben Tag (z. B. manuell vor einer Migration) darf
# nicht scheitern: dann wird das Asset im vorhandenen Release ersetzt.
if gh release view "$tag" --repo "$BACKUP_REPO" >/dev/null 2>&1; then
  gh release upload "$tag" "$dump.age" --repo "$BACKUP_REPO" --clobber
else
  gh release create "$tag" "$dump.age" --repo "$BACKUP_REPO" \
    --title "Backup $stamp" --notes "$summary"
fi
echo "✓ Abgelegt als $tag"

# Alte Backups abräumen — begrenzt den Speicher und die Zeit, die Daten
# eines gelöschten Kontos in Backups überleben.
old=$(gh release list --repo "$BACKUP_REPO" --limit 100 --json tagName \
  --jq '.[].tagName' | grep '^backup-' | sort -r | tail -n "+$((KEEP + 1))" || true)
for tag in $old; do
  echo "→ Räumt altes Backup ab: $tag"
  gh release delete "$tag" --repo "$BACKUP_REPO" --yes --cleanup-tag
done

echo "Backup abgeschlossen."
