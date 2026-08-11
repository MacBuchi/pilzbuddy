-- Patch 019: Ein unkonfigurierter Versand staut nichts auf (Issue #277).
--
-- Patch 018 steigt aus, wenn die drei Vault-Geheimnisse fehlen — richtig,
-- damit zwischen Merge und Einrichtung kein scheiternder Cron-Job läuft.
-- Falsch war die REIHENFOLGE: Der Ausstieg lag vor dem Löschen der
-- fälligen Zeilen. Der Korb wuchs also, solange nichts eingerichtet war,
-- und der erste konfigurierte Lauf hätte einen Schwall abgefeuert —
-- Meldungen über Funde von vorgestern, alle auf einmal.
--
-- Eine Benachrichtigung ist verderbliche Ware. Was nicht rausgehen kann,
-- WÄHREND es aktuell ist, geht besser gar nicht raus. Deshalb räumt die
-- Funktion die fälligen Zeilen jetzt auch dann weg, wenn sie sie nicht
-- verschicken kann.
--
-- Warum ein neuer Patch statt einer Korrektur in 018: Der ist live schon
-- eingespielt (der Schema Check tut das aus dem PR heraus) und läuft dort
-- nie wieder. Eine Änderung an ihm käme nur noch in Frischinstallationen
-- an, und beide Welten drifteten still auseinander — genau das verhindert
-- `tool/patch_guard.sh`.

create or replace function app_internal.push_flush()
returns integer
language plpgsql security definer
set search_path = public, app_internal, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
  payload jsonb;
  sent integer;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'push_functions_url';
  select decrypted_secret into job_secret
    from vault.decrypted_secrets where name = 'push_job_secret';
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'push_service_key';

  -- Nicht eingerichtet: Fällige Zeilen trotzdem wegräumen und still
  -- zurück. Ohne das Löschen wüchse der Korb bis zur Einrichtung.
  if base_url is null or job_secret is null or service_key is null then
    delete from app_internal.push_outbox where due_at <= now();
    return 0;
  end if;

  with due as (
    delete from app_internal.push_outbox
     where due_at <= now()
    returning recipient_id, kind
  ),
  -- Je Empfänger EINE Nachricht, auch wenn mehrere Spots fällig sind:
  -- „drei Meldungen gleichzeitig" ist die Art, wie Benachrichtigungen
  -- lästig werden.
  grouped as (
    select recipient_id,
           count(*) filter (where kind = 'buddy_find') as finds,
           count(*) filter (where kind = 'new_spot') as spots
      from due group by recipient_id
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', 'PilzBuddy',
           'body', case
             when g.finds > 0 and g.spots > 0
               then 'Deine Pilzbuddies waren unterwegs.'
             when g.finds > 1 then 'Neue Funde bei deinen Pilzbuddies.'
             when g.finds = 1 then 'Neuer Fund bei einem Pilzbuddy.'
             when g.spots > 1 then 'Neue Spots von deinen Pilzbuddies.'
             else 'Ein Pilzbuddy hat einen neuen Spot geöffnet.'
           end))
    into payload
    from grouped g
    join public.push_devices d on d.user_id = g.recipient_id;

  if payload is null then return 0; end if;
  select jsonb_array_length(payload) into sent;

  -- Asynchron (pg_net): Die Antwort landet in `net._http_response`, der
  -- Cron-Lauf wartet nicht darauf. Ein fehlgeschlagener Versand ist
  -- verloren — bewusst: Eine Wiedervorlage für Benachrichtigungen
  -- brächte im Zweifel dieselbe Meldung ein zweites Mal, und das ist
  -- schlimmer als eine verpasste.
  perform net.http_post(
    url := base_url || '/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key,
      'x-push-secret', job_secret),
    body := jsonb_build_object('messages', payload));
  return sent;
end $$;

revoke all on function app_internal.push_flush() from public, anon, authenticated;
