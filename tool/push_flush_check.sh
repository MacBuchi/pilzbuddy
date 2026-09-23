#!/usr/bin/env bash
# Ruft app_internal.push_flush() auf dem Wegwerf-Stack des Schema Dry
# Run WIRKLICH auf und prüft die Nutzlast, die an `send-push` ginge.
#
# **Warum es das braucht (#564, Patch 031):** PL/pgSQL prüft den Rumpf
# einer Funktion beim Anlegen kaum — ein falscher Spaltenname fällt erst
# beim AUFRUF auf. `push_flush` ruft in CI sonst niemand auf, live aber
# jede Minute der Cron-Job. Ein Fehler darin legte ALLE Benachrichtigungen
# still, auch die für Funde und Spots, und zwar lautlos: Der Job scheitert
# in `cron.job_run_details`, die App merkt nichts.
#
# **Es geht nichts hinaus.** Alles läuft in EINER Transaktion, die am
# Ende zurückgerollt wird; pg_net verschickt nur, was committet ist. Die
# Geheimnisse sind Platzhalter und die Adresse zeigt ins Leere.
#
# Braucht SUPABASE_DB_URL (lokaler Stack) und jq.
set -euo pipefail

DB="${SUPABASE_DB_URL:?SUPABASE_DB_URL fehlt}"
A=aaaaaaaa-0000-0000-0000-00000000000a
B=bbbbbbbb-0000-0000-0000-00000000000b

out=$(psql "$DB" -v ON_ERROR_STOP=1 -q -At <<SQL
begin;
select vault.create_secret('http://127.0.0.1:9/functions/v1', 'push_functions_url');
select vault.create_secret('dry-run', 'push_job_secret');
select vault.create_secret('dry-run', 'push_service_key');
insert into auth.users (id, email, aud, role, instance_id) values
  ('$A', 'a@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('$B', 'b@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');
insert into public.profiles (id, username) values ('$A', 'anna'), ('$B', 'bert')
  on conflict (id) do update set username = excluded.username;
insert into public.friendships (requester_id, addressee_id, status)
  values ('$A', '$B', 'accepted');
insert into public.push_devices (token, user_id, platform)
  values ('tok-bert', '$B', 'android');
-- Drei Nachrichten von Anna an Bert; die mittlere wird vor dem Lauf
-- zurückgenommen (Cascade aus der Warteschlange). Zeitpunkte ausdrücklich,
-- sonst entschiede bei gleichem now() der Zufall, welche die neueste ist.
insert into public.buddy_messages (id, sender_id, recipient_id, body, created_at)
  values ('11111111-0000-0000-0000-000000000001', '$A', '$B', 'alt', now() - interval '3 minutes'),
         ('11111111-0000-0000-0000-000000000002', '$A', '$B', 'zurückgenommen', now() - interval '2 minutes'),
         ('11111111-0000-0000-0000-000000000003', '$A', '$B', repeat('x', 200), now() - interval '1 minute');
delete from public.buddy_messages where id = '11111111-0000-0000-0000-000000000002';
select app_internal.push_flush();
select convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;
select count(*) from app_internal.push_messages;
rollback;
SQL
)

# Die Ausgabe: Rückgabe von push_flush, dann die Nutzlast, dann der Rest
# der Warteschlange (die create_secret-Zeilen stehen davor).
lines=$(printf '%s\n' "$out" | tail -n 3)
sent=$(printf '%s\n' "$lines" | sed -n 1p)
body=$(printf '%s\n' "$lines" | sed -n 2p)
left=$(printf '%s\n' "$lines" | sed -n 3p)

fail=0
expect() {
  if [ "$2" != "$3" ]; then
    echo "::error::push_flush: $1 — erwartet '$3', bekommen '$2'"
    fail=1
  else
    echo "✓ $1"
  fi
}

expect "eine Meldung verschickt" "$sent" "1"
msg=$(printf '%s' "$body" | jq -c '.messages[0]')
expect "an Berts Gerät" "$(jq -r .token <<<"$msg")" "tok-bert"
expect "Titel: Name und Zahl" "$(jq -r .title <<<"$msg")" "anna · 2 Nachrichten"
expect "Text: die NEUESTE, auf 180 Zeichen gekürzt" \
  "$(jq -r .body <<<"$msg")" "$(printf 'x%.0s' $(seq 1 179))…"
expect "Ziel: der Verlauf mit Anna" "$(jq -r .route <<<"$msg")" "/friends/chat/$A"
expect "Warteschlange danach leer" "$left" "0"

exit $fail
