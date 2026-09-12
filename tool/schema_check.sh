#!/usr/bin/env bash
# Live schema smoke test: runs the exact PostgREST queries the app uses
# against the live Supabase project. Uses only the public publishable key
# — RLS keeps all data private, but schema errors (missing columns,
# renamed FK embeds, changed RPC signatures) surface regardless of RLS.
#
# This is the guard for the bug class behind issue #27: app code that
# expects schema the live DB does not have. Extend the checks below
# whenever a repository in lib/data/ starts using new columns/embeds.
#
# Default target is the live project (URL/key from supabase_config.dart).
# SUPABASE_URL/SUPABASE_KEY override it — the Schema Dry Run job in ci.yml
# points them at the local stack built from schema.sql + patches.
set -euo pipefail

CONFIG=lib/core/supabase_config.dart
URL="${SUPABASE_URL:-$(sed -n "s/.*'\(https:[^']*supabase[^']*\)'.*/\1/p" "$CONFIG")}"
KEY="${SUPABASE_KEY:-$(sed -n "s/.*'\(sb_publishable_[^']*\)'.*/\1/p" "$CONFIG")}"
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "::error::Konnte URL/Key nicht aus $CONFIG lesen (oder SUPABASE_URL/SUPABASE_KEY setzen)."
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

# Für RPCs, die anon NICHT aufrufen darf (Konto-Löschung, Freundesuche).
# Ein Fehler ist hier der Erfolgsfall — aber nur der richtige: PGRST202
# hieße „Funktion fehlt" (Patch nicht eingespielt), und eine erfolgreiche
# Antwort hieße, dass anon die Funktion ausführen darf. Beides muss
# auffallen. Der Body muss zur Signatur passen, sonst antwortet PostgREST
# mit PGRST202 statt mit dem erwarteten Rechte-Fehler.
check_rpc_protected() {
  local name="$1" fn="$2" body="$3" out
  out=$(curl -s --max-time 20 -X POST "$URL/rest/v1/rpc/$fn" \
    -H "apikey: $KEY" -H "Content-Type: application/json" -d "$body" \
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

# Die Mindestversion aus der Antwort — LEER, wenn sie nicht drinsteht.
#
# Eigene Funktion, damit sich die drei Fälle (Dienst antwortet nicht /
# Tabelle leer / Zeile ohne Feld) ohne laufende Datenbank prüfen lassen:
# `tool/schema_check.sh --self-test`. Bis zum 2026-09-12 stand unter
# allen dreien dieselbe Diagnose.
app_config_version() {
  local status="$1" body="$2"
  [ "$status" = "200" ] || return 0
  printf '%s' "$body" \
    | sed -n 's/.*"minimum_supported_version":"\([^"]*\)".*/\1/p'
}

app_config_diagnosis() {
  local status="$1" body="$2"
  if [ "$status" != "200" ]; then
    echo "dienst"
  elif [ "$body" = "[]" ]; then
    echo "leer"
  elif [ -z "$(app_config_version "$status" "$body")" ]; then
    echo "feld"
  else
    echo "ok"
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  fehler=0
  probe() {
    local erwartet="$1" status="$2" body="$3"
    local ist
    ist=$(app_config_diagnosis "$status" "$body")
    if [ "$ist" = "$erwartet" ]; then
      echo "  ✓ $status ${body:-<leer>} → $ist"
    else
      echo "  ✗ $status ${body:-<leer>} → $ist statt $erwartet"
      fehler=1
    fi
  }
  echo "app_config-Diagnose:"
  # Genau der Fall vom 2026-09-12: Antwort blieb aus, Tabelle war heil.
  probe dienst 000 ""
  probe dienst 503 ""
  probe dienst 500 '{"code":"XX000"}'
  probe leer   200 '[]'
  probe feld   200 '[{"id":true}]'
  probe ok     200 '[{"id":true,"minimum_supported_version":"1.2.3"}]'
  [ "$(app_config_version 200 '[{"minimum_supported_version":"1.2.3"}]')" \
    = "1.2.3" ] || { echo "  ✗ Version wird nicht gelesen"; fehler=1; }
  # Ohne 200 gibt es keine Version — auch wenn im Rumpf eine steht.
  [ -z "$(app_config_version 500 '[{"minimum_supported_version":"9.9.9"}]')" ] \
    || { echo "  ✗ Version aus einer Fehlantwort gelesen"; fehler=1; }
  [ "$fehler" = 0 ] && echo "schema_check self-test: ok"
  exit "$fehler"
fi

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

# spots: exakt die Freundes-Spots-Query aus SpotRepository.fetchFriendSpots.
# Der Fund-Autor (Patch 014) wird mit explizitem FK-Namen embeddet —
# Vorbild friendships: Benennt jemand den Constraint um, fällt es HIER
# auf und nicht als leises PGRST200 im Feld.
check_get "spots-Embed (Freundes-Spots)" \
  "/rest/v1/spots?select=*,finds(*,author:profiles!finds_author_id_fkey(username,avatar)),profiles(username,avatar)&limit=1"

# friendships: exakt die Query aus FriendRepository.fetchFriendships
check_get "friendships-Embed" \
  "/rest/v1/friendships?select=id,status,requester_id,addressee_id,requester:profiles!friendships_requester_id_fkey(username,avatar),addressee:profiles!friendships_addressee_id_fkey(username,avatar)&limit=1"

# spots: die Spalten, die SpotRepository SCHREIBT — addSpot und seit
# #112 restoreSpot (das als einziges `sharing_excluded` schon beim
# Anlegen mitgibt statt per Update hinterher). Der Embed-Check oben holt
# `*` und würde eine umbenannte Spalte deshalb nicht bemerken; hier
# stehen sie namentlich.
check_get "spots-Schreibspalten" \
  "/rest/v1/spots?select=id,owner_id,name,lat,lng,sharing_excluded,client_id&limit=1"

# finds: Spalten aus Find.fromJson / SpotRepository.addFinds und dem
# Batch-Insert aus restoreSpot (#112). `blank` seit Patch 015 (#211),
# `lat`/`lng`/`accuracy_m` seit Patch 022 (#373) — die eigene Stelle
# eines Fundes samt Streuradius des Fixes.
# `client_id` seit Patch 016 (#267) — ohne die Spalte könnte die
# Wiedervorlage aus dem Ausgangskorb Dubletten anlegen, und zwar
# stillschweigend.
check_get "finds-Spalten" \
  "/rest/v1/finds?select=id,spot_id,author_id,species,count,found_on,note,created_at,blank,client_id,lat,lng,accuracy_m&limit=1"

# live_locations: exakt die Query aus LiveShareRepository.fetchFriendLocations
check_get "live_locations-Embed (Freundes-Standorte)" \
  "/rest/v1/live_locations?select=user_id,lat,lng,expires_at,profiles(username,avatar)&limit=1"

# feedback: Spalten, die App (Insert) und Feedback-Bot (Select) nutzen
check_get "feedback-Spalten" \
  "/rest/v1/feedback?select=id,user_id,type,message,species_name,created_at,processed_at,app_version&limit=1"

# error_reports: die Spalten, die ErrorReportRepository schreibt. RLS gibt
# anon keine Zeilen zurück — eine unbekannte Spalte im select quittiert
# PostgREST aber trotzdem mit einem Fehler, genau darum geht es hier.
check_get "error_reports-Spalten" \
  "/rest/v1/error_reports?select=id,user_id,context,error_type,message,stack,app_version,platform,created_at&limit=1"

# push_devices (Patch 017): die Spalten, die PushRepository schreibt.
# Wie bei error_reports gibt RLS anon nichts zurück — eine unbekannte
# Spalte quittiert PostgREST trotzdem mit einem Fehler, und genau das
# prüft der Aufruf. Der `on conflict (token)` des Upserts hängt am
# Primärschlüssel; bricht der weg, scheitert das Registrieren erst am
# Gerät.
check_get "push_devices-Spalten" \
  "/rest/v1/push_devices?select=token,user_id,platform,created_at,last_seen_at&limit=1"

# app_config (Patch 012): die Zeile, aus der die App die Mindestversion
# liest. Anders als bei den anderen Tabellen darf anon hier tatsächlich
# lesen — ein leeres Ergebnis wäre also ein echter Befund: ohne Zeile
# erfährt die App nie, dass sie zu alt ist.
#
# **Warum hier der HTTP-Status mitgelesen wird** (2026-09-12): Bis dahin
# stand unter JEDER Ursache dieselbe Diagnose — „app_config hat keine
# Zeile". Am 2026-09-12 kam die Antwort einmal leer zurück, der Dienst
# war Minuten später wieder da, und die Meldung schickte auf die Suche
# nach einer fehlenden Zeile, die es gab. `verdict` sieht das nicht: Es
# prüft auf ein Fehlerobjekt, und eine leere Antwort ist keins.
#
# Ein Wächter darf sich irren. Er darf nicht die Ursache erfinden.
app_config_body=$(mktemp)
app_config_status=$(curl -s --max-time 20 -o "$app_config_body" \
  -w '%{http_code}' \
  "$URL/rest/v1/app_config?select=id,minimum_supported_version,updated_at&limit=1" \
  -H "apikey: $KEY" || echo "000")
app_config=$(cat "$app_config_body")
rm -f "$app_config_body"
min_version=$(app_config_version "$app_config_status" "$app_config")
# **Dieselbe Funktion, die der Selbsttest prüft.** Die Bedingungen hier
# noch einmal auszuschreiben hieße, zwei Entscheidungen zu führen — und
# geprüft wäre dann die, die im Ernstfall nicht läuft.
case "$(app_config_diagnosis "$app_config_status" "$app_config")" in
dienst)
  # Der Dienst hat nicht geantwortet oder mit einem Fehler. Das sagt
  # NICHTS über den Inhalt der Tabelle — und darf deshalb auch nichts
  # darüber behaupten. 000 heißt: curl kam gar nicht durch.
  echo "::error::Schema-Check fehlgeschlagen: app_config nicht abrufbar (HTTP $app_config_status). Das ist eine Aussage über den DIENST, nicht über die Tabelle — bei 000/5xx den Lauf wiederholen. Antwort: ${app_config:-<leer>}"
  fail=1
  ;;
leer)
  # Jetzt ist es wirklich der Befund, für den die Prüfung da ist.
  echo "::error::Schema-Check fehlgeschlagen: app_config ist LEER — ohne Zeile erfährt die App nie, dass sie zu alt ist (Issue #80, Patch 012)."
  fail=1
  ;;
feld)
  echo "::error::Schema-Check fehlgeschlagen: app_config antwortet ohne minimum_supported_version. Antwort: $app_config"
  fail=1
  ;;
*)
  verdict "app_config-Spalten" "$app_config"
  # Aussperr-Schutz (Issue #80): Die Mindestversion darf nie über dem
  # Stand liegen, den die Nutzer bekommen können — sonst sperrt die App
  # sie aus, und niemand käme mehr rein.
  #
  # **Der Maßstab ist seit #262 der STABILE Stand, nicht `pubspec.yaml`.**
  # Migrationen spielen beim Merge ein, der Client kommt erst mit der
  # Beförderung: Zwischen beidem liegen jetzt Wochen statt Minuten. Ein
  # Patch, der die Mindestversion auf die Entwicklungsversion hebt,
  # sperrte also genau die Leute aus, die auf stabil sind — und zwar
  # sofort beim Merge.
  app_version=$(sed -n 's/^version: \([0-9][0-9.]*\).*/\1/p' pubspec.yaml)
  stable_version=$(curl -s --max-time 20 \
    -H "Accept: application/vnd.github+json" \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    "https://api.github.com/repos/${GITHUB_REPOSITORY:-MacBuchi/pilzbuddy}/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' | head -1)
  if [ -z "$stable_version" ]; then
    # Kein stabiles Release (frisches Repo) oder GitHub nicht erreichbar:
    # Dann gilt der alte Maßstab. Ein wackeliger API-Aufruf darf keinen
    # Merge blockieren — die Grenze, die wirklich zählt, prüft die
    # Beförderung ohnehin erneut.
    echo "::warning::Kein stabiles Release gefunden — prüfe gegen pubspec.yaml ($app_version)."
    stable_version="$app_version"
    scale="App-Version"
  else
    scale="stabile Version"
  fi
  if [ "$min_version" = "$stable_version" ] || \
     [ "$(printf '%s\n%s\n' "$min_version" "$stable_version" | sort -V | head -1)" = "$min_version" ]; then
    echo "✓ Mindestversion $min_version ≤ $scale $stable_version"
  else
    echo "::error::Schema-Check fehlgeschlagen: Mindestversion $min_version liegt ÜBER der $scale $stable_version — das würde alle aussperren, die auf stabil sind (#262)."
    fail=1
  fi
  ;;
esac

# RPC der Freundesuche (Patch 011): muss existieren, ist aber für anon
# gesperrt — sonst wäre der exakte E-Mail-Vergleich ein E-Mail-Orakel.
check_rpc_protected "search_profiles-RPC" "search_profiles" '{"query":"schema-check"}'

# Konto-Löschung (Patch 008): muss existieren und darf nur für Angemeldete
# aufrufbar sein. Deshalb nicht mit check_rpc — der würde den erwarteten
# 403 als Fehler werten.
check_rpc_protected "delete_own_account-RPC" "delete_own_account" '{}'

if [ "$fail" -ne 0 ]; then
  echo "::error::Live-Schema passt nicht zu den App-Queries. Fehlt ein supabase/patch_NNN_*.sql bzw. wurde er noch nicht eingespielt (tool/db_migrate.sh, Secret SUPABASE_DB_URL)?"
  exit 1
fi
echo "Live-Schema passt zu allen App-Queries."
