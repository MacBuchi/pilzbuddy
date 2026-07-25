#!/usr/bin/env bash
# End-to-end check of the password reset against a real GoTrue in the local
# Supabase stack (started by the Schema Dry Run job): sign up → request a
# code → fetch the mail from Mailpit → redeem the code → set a new password
# → sign in with it.
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

signup=$(curl -s "$URL/auth/v1/signup" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$OLD\",\"data\":{\"username\":\"$USERNAME\"}}")
grep -q '"id"' <<<"$signup" || fail "Konto konnte nicht angelegt werden: $signup"
echo "✓ Testkonto angelegt"

status=$(curl -s -o /dev/null -w '%{http_code}' "$URL/auth/v1/recover" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\"}")
[ "$status" = "200" ] || fail "recover antwortete mit HTTP $status"
echo "✓ Reset-Code angefordert"

id=""
for _ in $(seq 1 30); do
  id=$(curl -s "$MAIL/api/v1/search?query=to:$EMAIL" | jq -r '.messages[0].ID // empty')
  [ -n "$id" ] && break
  sleep 1
done
[ -n "$id" ] || fail "keine Reset-Mail eingetroffen (Mailpit unter $MAIL)"
body=$(curl -s "$MAIL/api/v1/message/$id" | jq -r '.HTML')

code=$(printf '%s' "$body" | grep -oE '[0-9]{6}' | head -1)
[ -n "$code" ] || fail "kein sechsstelliger Code in der Mail — zeigt die Vorlage {{ .Token }}?"
# Ein Link in der Mail wäre der Weg, den die App bewusst NICHT geht: Er ist
# an das anfordernde Gerät gebunden (PKCE) und stirbt im Browser.
if printf '%s' "$body" | grep -qi 'auth/v1/verify'; then
  fail "die Reset-Mail enthält einen Link — die Vorlage muss nur den Code zeigen"
fi
echo "✓ Mail enthält einen Code und keinen Link"

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

echo "Passwort-Reset läuft end-to-end gegen echtes GoTrue."
