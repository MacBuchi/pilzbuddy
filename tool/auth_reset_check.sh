#!/usr/bin/env bash
# End-to-end check of the auth flows against a real GoTrue in the local
# Supabase stack (started by the Schema Dry Run job):
#   sign up → confirm the address with the code from the mail
#           → request a reset code → redeem it → sign in with the new one
#           → change the password from a signed-in session (Issue #127).
#
# Why this exists as its own check: the widget tests run against fakes and
# can only prove the app's own logic. Everything that makes this flow
# fragile lives outside them — that the recovery mail carries a six-digit
# token and no link, that verifyOTP accepts it, and above all that
# updateUser is allowed immediately afterwards even though
# "Secure password change" is on (supabase/config.toml mirrors that
# dashboard setting, so this runs under production's rules). That last one
# is the reason the flow could quietly stop working after a Supabase
# upgrade, and nothing else in CI would notice.
#
# The mail template is supabase/templates/recovery.html — the versioned
# copy of the dashboard template. If someone changes the dashboard back to
# a link, this check keeps passing (it only sees the local copy); that
# blind spot is the operator's, not CI's, and is noted in CLAUDE.md.
set -euo pipefail

URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
MAIL="${MAILPIT_URL:-http://127.0.0.1:54324}"
KEY="${SUPABASE_KEY:-$(supabase status -o json 2>/dev/null | jq -r '.ANON_KEY')}"
if [ -z "$KEY" ] || [ "$KEY" = "null" ]; then
  echo "::error::Kein anon-Key — läuft der lokale Stack (supabase start)?"
  exit 1
fi

EMAIL="resettest-$RANDOM$RANDOM@test.de"
USERNAME="resettest$RANDOM"
OLD='AltesPilz#2026!'
NEW='NeuesPilz#2026!'
hdr=(-H "apikey: $KEY" -H "Content-Type: application/json")

fail() { echo "::error::Passwort-Reset-Prüfung fehlgeschlagen: $1"; exit 1; }

# Holt eine Mail an $EMAIL, deren Betreff das Muster enthält. Nach Betreff
# statt „die neueste": Mit Bestätigungspflicht liegen zwei Mails im
# Postfach, und die falsche zu nehmen macht den Test zum Zufallsspiel.
fetch_mail() {
  local pattern="$1" id=""
  for _ in $(seq 1 30); do
    id=$(curl -s "$MAIL/api/v1/search?query=to:$EMAIL" \
      | jq -r --arg p "$pattern" \
        '[.messages[] | select(.Subject | test($p))] | .[0].ID // empty')
    [ -n "$id" ] && break
    sleep 1
  done
  [ -n "$id" ] || return 1
  curl -s "$MAIL/api/v1/message/$id" | jq -r '.HTML'
}

# Prüft, dass eine Mail den Code zeigt und keinen Link — der wäre an das
# anfordernde Gerät gebunden (PKCE) und stürbe im Browser.
code_from() {
  local body="$1" what="$2" code
  code=$(printf '%s' "$body" | grep -oE '[0-9]{6}' | head -1)
  [ -n "$code" ] || fail "kein sechsstelliger Code in der $what — zeigt die Vorlage {{ .Token }}?"
  if printf '%s' "$body" | grep -qi 'auth/v1/verify'; then
    fail "die $what enthält einen Link — die Vorlage darf nur den Code zeigen"
  fi
  printf '%s' "$code"
}

signup=$(curl -s "$URL/auth/v1/signup" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$OLD\",\"data\":{\"username\":\"$USERNAME\"}}")
grep -q '"id"' <<<"$signup" || fail "Konto konnte nicht angelegt werden: $signup"
# Mit Bestätigungspflicht darf signUp KEINE Sitzung liefern — genau darauf
# stützt sich der Registrieren-Screen (Issue #129).
grep -q '"access_token"' <<<"$signup" \
  && fail "signUp lieferte eine Sitzung — ist enable_confirmations aus? Der Registrieren-Screen erwartet die Bestätigung."
echo "✓ Testkonto angelegt, noch ohne Sitzung"

confirm_body=$(fetch_mail 'bestätige|Willkommen') \
  || fail "keine Bestätigungsmail eingetroffen (Mailpit unter $MAIL)"
confirm_code=$(code_from "$confirm_body" "Bestätigungsmail")
echo "✓ Bestätigungsmail enthält einen Code und keinen Link"

confirmed=$(curl -s "$URL/auth/v1/verify" "${hdr[@]}" \
  -d "{\"type\":\"signup\",\"email\":\"$EMAIL\",\"token\":\"$confirm_code\"}" \
  | jq -r '.access_token // empty')
[ -n "$confirmed" ] || fail "Bestätigungs-Code wurde nicht akzeptiert"
echo "✓ Adresse bestätigt, Sitzung kam direkt mit"

status=$(curl -s -o /dev/null -w '%{http_code}' "$URL/auth/v1/recover" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\"}")
[ "$status" = "200" ] || fail "recover antwortete mit HTTP $status"
echo "✓ Reset-Code angefordert"

body=$(fetch_mail 'zurücksetzen|Zurücksetzen') \
  || fail "keine Reset-Mail eingetroffen (Mailpit unter $MAIL)"
code=$(code_from "$body" "Reset-Mail")
echo "✓ Reset-Mail enthält einen Code und keinen Link"

verify=$(curl -s "$URL/auth/v1/verify" "${hdr[@]}" \
  -d "{\"type\":\"recovery\",\"email\":\"$EMAIL\",\"token\":\"$code\"}")
token=$(jq -r '.access_token // empty' <<<"$verify")
[ -n "$token" ] || fail "Code wurde nicht akzeptiert: $verify"
echo "✓ Code eingelöst"

status=$(curl -s -o /tmp/reset_update.out -w '%{http_code}' -X PUT "$URL/auth/v1/user" \
  "${hdr[@]}" -H "Authorization: Bearer $token" -d "{\"password\":\"$NEW\"}")
[ "$status" = "200" ] \
  || fail "neues Passwort abgelehnt (HTTP $status): $(cat /tmp/reset_update.out). Gilt die Recovery-Sitzung nicht mehr als frische Anmeldung? Dann braucht die App reauthenticate() (Issue #109)."
echo "✓ Neues Passwort gesetzt, obwohl secure_password_change an ist"

new=$(curl -s "$URL/auth/v1/token?grant_type=password" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$NEW\"}" | jq -r '.access_token // empty')
[ -n "$new" ] || fail "Anmeldung mit dem neuen Passwort schlug fehl"
old=$(curl -s "$URL/auth/v1/token?grant_type=password" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$OLD\"}" | jq -r '.error_code // empty')
[ "$old" = "invalid_credentials" ] || fail "das alte Passwort gilt noch ($old)"
echo "✓ Neues Passwort gilt, altes nicht mehr"

# Der Fehlercode, auf den resetErrorMessage() in lib/core/errors.dart baut.
bad=$(curl -s "$URL/auth/v1/verify" "${hdr[@]}" \
  -d "{\"type\":\"recovery\",\"email\":\"$EMAIL\",\"token\":\"000000\"}" \
  | jq -r '.error_code // empty')
[ "$bad" = "otp_expired" ] \
  || fail "falscher Code liefert '$bad' statt 'otp_expired' — die Meldung in lib/core/errors.dart passt dann nicht mehr"
echo "✓ Falscher Code wird als otp_expired abgelehnt"

# --- Passwort ändern durch Angemeldete (Issue #127) -------------------------
# AuthRepository.changePassword meldet sich zuerst mit dem aktuellen Passwort
# neu an und ändert danach — genau diese Reihenfolge steht hier. Sie ist der
# ganze Trick: „Secure password change" verlangt eine frische
# Authentifizierung, und die frische Anmeldung liefert sie. Kürzt jemand den
# Schritt weg, fällt es live als 403 auf und sonst nirgends.
#
# Bewusst NICHT geprüft: dass eine „alte" Sitzung abgelehnt wird. Jede
# Sitzung, die dieses Skript erzeugen kann, ist frisch — der Test wäre ein
# Zufallsgenerator.
THIRD='DrittesPilz#2026!'
status=$(curl -s -o /tmp/change_update.out -w '%{http_code}' -X PUT "$URL/auth/v1/user" \
  "${hdr[@]}" -H "Authorization: Bearer $new" -d "{\"password\":\"$THIRD\"}")
[ "$status" = "200" ] \
  || fail "Passwortwechsel nach frischer Anmeldung abgelehnt (HTTP $status): $(cat /tmp/change_update.out). Dann reicht signInWithPassword nicht mehr als frische Authentifizierung und AuthRepository.changePassword braucht reauthenticate() (Issue #127)."
echo "✓ Passwortwechsel nach frischer Anmeldung angenommen"

third=$(curl -s "$URL/auth/v1/token?grant_type=password" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$THIRD\"}" | jq -r '.access_token // empty')
[ -n "$third" ] || fail "Anmeldung mit dem geänderten Passwort schlug fehl"
gone=$(curl -s "$URL/auth/v1/token?grant_type=password" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$NEW\"}" | jq -r '.error_code // empty')
[ "$gone" = "invalid_credentials" ] \
  || fail "das vorige Passwort gilt nach dem Wechsel noch ($gone)"
echo "✓ Geändertes Passwort gilt, das vorige nicht mehr"

# Nur zur Information: Ob GoTrue ein unverändertes Passwort mit
# `same_password` ablehnt, hängt an der Plattform-Einstellung. Die App bildet
# den Code ab (changePasswordErrorMessage) — hier nur protokollieren, statt
# einen Lauf daran scheitern zu lassen.
same=$(curl -s -X PUT "$URL/auth/v1/user" "${hdr[@]}" \
  -H "Authorization: Bearer $third" -d "{\"password\":\"$THIRD\"}" \
  | jq -r '.error_code // "akzeptiert"')
echo "ℹ Unverändertes Passwort meldet: $same (App erwartet same_password)"

echo "Registrierung, Passwort-Reset und Passwortwechsel laufen end-to-end gegen echtes GoTrue."
