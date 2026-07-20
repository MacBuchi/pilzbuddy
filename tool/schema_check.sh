#!/usr/bin/env bash
# Live schema smoke test: runs the exact PostgREST queries the app uses
# against the live Supabase project. Uses only the public publishable key
# — RLS keeps all data private, but schema errors (missing columns,
# renamed FK embeds, changed RPC signatures) surface regardless of RLS.
#
# This is the guard for the bug class behind issue #27: app code that
# expects schema the live DB does not have. Extend the checks below
# whenever a repository in lib/data/ starts using new columns/embeds.
set -euo pipefail

CONFIG=lib/core/supabase_config.dart
URL=$(sed -n "s/.*'\(https:[^']*supabase[^']*\)'.*/\1/p" "$CONFIG")
KEY=$(sed -n "s/.*'\(sb_publishable_[^']*\)'.*/\1/p" "$CONFIG")
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "::error::Konnte URL/Key nicht aus $CONFIG lesen."
  exit 1
fi

fail=0

check_get() {
  local name="$1" path="$2" out
  out=$(curl -s --max-time 20 "$URL$path" -H "apikey: $KEY" || echo '{"code":"curl","message":"Verbindung fehlgeschlagen"}')
  verdict "$name" "$out"
}

check_rpc() {
  local name="$1" fn="$2" body="$3" out
  out=$(curl -s --max-time 20 -X POST "$URL/rest/v1/rpc/$fn" \
    -H "apikey: $KEY" -H "Content-Type: application/json" -d "$body" \
    || echo '{"code":"curl","message":"Verbindung fehlgeschlagen"}')
  verdict "$name" "$out"
}

# Für RPCs, die anon NICHT aufrufen darf (z. B. Konto-Löschung). Ein Fehler
# ist hier der Erfolgsfall — aber nur der richtige: PGRST202 hieße „Funktion
# fehlt" (Patch nicht eingespielt), und eine erfolgreiche Antwort hieße, dass
# anon die Funktion ausführen darf. Beides muss auffallen.
check_rpc_protected() {
  local name="$1" fn="$2" out
  out=$(curl -s --max-time 20 -X POST "$URL/rest/v1/rpc/$fn" \
    -H "apikey: $KEY" -H "Content-Type: application/json" -d '{}' \
    || echo '{"code":"curl","message":"Verbindung fehlgeschlagen"}')
  if printf '%s' "$out" | grep -q 'PGRST202'; then
    echo "::error::Schema-Check fehlgeschlagen: $name — Funktion fehlt in der Live-DB: $out"
    fail=1
  elif printf '%s' "$out" | grep -q '"code"'; then
    echo "✓ $name (vorhanden und für anon gesperrt)"
  else
    echo "::error::Schema-Check fehlgeschlagen: $name — anon darf die Funktion ausführen!"
    fail=1
  fi
}

verdict() {
  local name="$1" out="$2"
  if printf '%s' "$out" | grep -q '"code"'; then
    echo "::error::Schema-Check fehlgeschlagen: $name — $out"
    fail=1
  else
    echo "✓ $name"
  fi
}

# profiles: alle Spalten, die ProfileRepository/Profile.fromJson nutzen
check_get "profiles-Spalten" \
  "/rest/v1/profiles?select=id,username,display_name,share_spots_default,share_details,avatar&limit=1"

# spots: exakt die Freundes-Spots-Query aus SpotRepository.fetchFriendSpots
check_get "spots-Embed (Freundes-Spots)" \
  "/rest/v1/spots?select=*,finds(*),profiles(username,avatar)&limit=1"

# friendships: exakt die Query aus FriendRepository.fetchFriendships
check_get "friendships-Embed" \
  "/rest/v1/friendships?select=id,status,requester_id,addressee_id,requester:profiles!friendships_requester_id_fkey(username,avatar),addressee:profiles!friendships_addressee_id_fkey(username,avatar)&limit=1"

# finds: Spalten aus Find.fromJson / SpotRepository.addFind
check_get "finds-Spalten" \
  "/rest/v1/finds?select=id,spot_id,species,count,found_on,note,created_at&limit=1"

# live_locations: exakt die Query aus LiveShareRepository.fetchFriendLocations
check_get "live_locations-Embed (Freundes-Standorte)" \
  "/rest/v1/live_locations?select=user_id,lat,lng,expires_at,profiles(username,avatar)&limit=1"

# feedback: Spalten, die App (Insert) und Feedback-Bot (Select) nutzen
check_get "feedback-Spalten" \
  "/rest/v1/feedback?select=id,user_id,type,message,species_name,created_at,processed_at&limit=1"

# error_reports: die Spalten, die ErrorReportRepository schreibt. RLS gibt
# anon keine Zeilen zurück — eine unbekannte Spalte im select quittiert
# PostgREST aber trotzdem mit einem Fehler, genau darum geht es hier.
check_get "error_reports-Spalten" \
  "/rest/v1/error_reports?select=id,user_id,context,error_type,message,stack,app_version,platform,created_at&limit=1"

# RPC der Freundesuche (Signatur + Rückgabetyp)
check_rpc "search_profiles-RPC" "search_profiles" '{"query":"schema-check"}'

# Konto-Löschung (Patch 008): muss existieren und darf nur für Angemeldete
# aufrufbar sein. Deshalb nicht mit check_rpc — der würde den erwarteten
# 403 als Fehler werten.
check_rpc_protected "delete_own_account-RPC" "delete_own_account"

if [ "$fail" -ne 0 ]; then
  echo "::error::Live-Schema passt nicht zu den App-Queries. Fehlt ein supabase/patch_NNN_*.sql bzw. wurde er noch nicht eingespielt (tool/db_migrate.sh, Secret SUPABASE_DB_URL)?"
  exit 1
fi
echo "Live-Schema passt zu allen App-Queries."
