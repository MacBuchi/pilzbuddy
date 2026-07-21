#!/usr/bin/env bash
# Applies pending supabase/patch_NNN_*.sql files to the live database.
#
# Applied patches are tracked in public.applied_patches; patches up to
# BASELINE were applied manually by the operator before this automation
# existed and are only recorded, never re-run. Each newer patch runs in a
# single transaction and is recorded afterwards, so the script is
# idempotent and safe to run from both CI (per PR) and the release
# workflow (safety net).
#
# Requires SUPABASE_DB_URL (Session-Pooler URI incl. password, GitHub
# secret). Without it the script only fails if there are pending patches.
set -euo pipefail

BASELINE=${BASELINE:-5}
DB_URL="${SUPABASE_DB_URL:-}"

patch_number() {
  basename "$1" | sed -n 's/^patch_0*\([0-9][0-9]*\)_.*/\1/p'
}

files=$(ls supabase/patch_*.sql 2>/dev/null | sort || true)
pending_without_db=""
for f in $files; do
  n=$(patch_number "$f")
  if [ -n "$n" ] && [ "$n" -gt "$BASELINE" ]; then
    pending_without_db="$pending_without_db $(basename "$f")"
  fi
done

if [ -z "$DB_URL" ]; then
  if [ -n "$pending_without_db" ]; then
    echo "::error::Neue DB-Patches vorhanden (${pending_without_db# }), aber das Repo-Secret SUPABASE_DB_URL fehlt. Ohne eingespielten Patch darf dieser Stand nicht gemergt/released werden. Secret anlegen: Supabase-Dashboard → Connect → Session-Pooler-URI (inkl. DB-Passwort) → GitHub → Settings → Secrets → Actions → SUPABASE_DB_URL."
    exit 1
  fi
  echo "Keine neuen DB-Patches — SUPABASE_DB_URL wird nicht benötigt."
  exit 0
fi

run_sql() { psql "$DB_URL" -v ON_ERROR_STOP=1 -qtA "$@"; }

if ! run_sql -c "select 1" >/dev/null; then
  echo "::error::Keine Verbindung zur Datenbank — stimmt die Session-Pooler-URI im Secret SUPABASE_DB_URL (inkl. Passwort)?"
  exit 1
fi

# RLS + Revoke gehören zum Bootstrap (idempotent), nicht nur zu Patch 010:
# die Tabelle entsteht hier VOR dem ersten Patch-Lauf und wäre auf einer
# Frischinstallation sonst wieder offen (Supabase-Advisor:
# rls_disabled_in_public — über die API voll les- und schreibbar).
run_sql -c "create table if not exists public.applied_patches (
  filename text primary key,
  applied_at timestamptz not null default now()
);
alter table public.applied_patches enable row level security;
revoke all on table public.applied_patches from anon, authenticated;" >/dev/null

for f in $files; do
  name=$(basename "$f")
  n=$(patch_number "$f")
  if [ -z "$n" ]; then
    echo "::warning::Überspringe $name — Dateiname passt nicht zum Muster patch_NNN_*.sql"
    continue
  fi
  if [ "$n" -le "$BASELINE" ]; then
    # Baseline: manuell eingespielt, nur protokollieren.
    run_sql -c "insert into public.applied_patches (filename) values ('$name') on conflict do nothing;" >/dev/null
    continue
  fi
  applied=$(run_sql -c "select 1 from public.applied_patches where filename = '$name';")
  if [ "$applied" = "1" ]; then
    echo "✓ Schon eingespielt: $name"
    continue
  fi
  echo "→ Spiele ein: $name"
  psql "$DB_URL" -v ON_ERROR_STOP=1 --single-transaction -f "$f"
  run_sql -c "insert into public.applied_patches (filename) values ('$name');" >/dev/null
  echo "✓ Eingespielt: $name"
done

echo "Alle DB-Patches sind eingespielt."
