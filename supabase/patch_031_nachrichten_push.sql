-- Patch 031: Benachrichtigung bei neuen Nachrichten (#564, Stufe 2).
--
-- > Soll eine neue Nachricht eine Benachrichtigung auslösen? — Ja, mit
-- > Text. (Betreiber, 2026-09-23)
--
-- DAS KIPPT EINE ZUSAGE, bewusst: Bisher enthielt eine Push nie etwas,
-- das eine Fundstelle verraten könnte — die App erzeugte nur neutrale
-- Sätze. Ein Nachrichtentext stammt von einem Menschen und kann alles
-- enthalten, und er läuft über Googles Server. Datenschutzerklärung und
-- Profil-Schalter sagen das seit diesem Patch ausdrücklich; für alles,
-- was die App selbst meldet, gilt die alte Zusage weiter.
--
-- EIGENE WARTESCHLANGE statt `push_outbox`: Deren Schlüssel ist
-- (Empfänger, Art, Spot), mit einem Spot als Pflicht-Fremdschlüssel —
-- eine Nachricht hat keinen. Die Zeile hängt per Cascade an der
-- Nachricht: Wer sie in der Minute bis zum Versand zurücknimmt oder die
-- Freundschaft beendet (Trigger aus Patch 030), löst keine Meldung aus.
--
-- Der Versand bleibt EIN Job (`push_flush`, jede Minute) und EIN Aufruf
-- von `send-push`; die Funktion wird hier neu angelegt, ihr alter Teil
-- (Funde, Spots) ist Zeichen für Zeichen unverändert.
--
-- KEIN Bump von minimum_supported_version: rein additiv; ältere Apps
-- ignorieren das zusätzliche `data.route` einer Meldung.
create table app_internal.push_messages (
  message_id uuid primary key
    references public.buddy_messages(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table app_internal.push_messages enable row level security;
revoke all on app_internal.push_messages from public, anon, authenticated;

create or replace function app_internal.push_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into app_internal.push_messages (message_id) values (new.id);
  return new;
end;
$$;
revoke all on function app_internal.push_on_message() from public, anon, authenticated;
create trigger push_on_message_trg after insert on public.buddy_messages
  for each row execute function app_internal.push_on_message();

create or replace function app_internal.push_flush()
returns integer
language plpgsql security definer
set search_path = public, app_internal, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
  payload jsonb;
  message_payload jsonb;
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
    delete from app_internal.push_messages;
    return 0;
  end if;

  with due as (
    delete from app_internal.push_outbox
     where due_at <= now()
    returning recipient_id, kind, spot_id
  ),
  -- Je Empfänger EINE Nachricht, auch wenn mehrere Spots fällig sind:
  -- „drei Meldungen gleichzeitig" ist die Art, wie Benachrichtigungen
  -- lästig werden.
  grouped as (
    select recipient_id,
           count(*) filter (where kind = 'buddy_find') as finds,
           count(*) filter (where kind = 'new_spot') as spots,
           count(distinct spot_id) filter (where kind = 'buddy_find')
             as find_spots
      from due group by recipient_id
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', case
             when g.finds > 0 and g.spots > 0
               then 'Deine Buddys waren unterwegs'
             when g.finds > 1
               then g.finds || ' neue Funde bei deinen Buddys'
             when g.finds = 1 then 'Neuer Fund bei einem Buddy'
             when g.spots > 1
               then g.spots || ' neue Spots von deinen Buddys'
             else 'Ein Buddy hat einen neuen Spot geöffnet'
           end,
           -- Der Rumpf trägt die zweite Dimension, wo es eine gibt. Wo
           -- nicht, sagt er, was ein Tipp bringt — mehr bleibt ohne
           -- Namen und Arten nicht übrig, und beim ersten Mal ist es
           -- nicht selbstverständlich.
           'body', case
             when g.finds > 0 and g.spots > 0 then
               g.finds || (case when g.finds = 1 then ' neuer Fund'
                                else ' neue Funde' end) || ' und ' ||
               g.spots || (case when g.spots = 1 then ' neuer Spot'
                                else ' neue Spots' end)
             when g.find_spots > 1 then 'An ' || g.find_spots || ' Spots'
             when g.finds > 1 then 'An einem Spot'
             else 'Tippen zeigt dir die Stelle auf der Karte'
           end))
    into payload
    from grouped g
    join public.push_devices d on d.user_id = g.recipient_id;

  -- Nachrichten (Patch 031): OHNE Entprellung — eine Nachricht will
  -- gelesen werden, solange sie aktuell ist; der Minutentakt fasst
  -- trotzdem zusammen, was in derselben Minute kam. Je Empfänger UND
  -- Absender eine Meldung: der Name als Titel, die NEUESTE Nachricht als
  -- Text, gekürzt. MIT Text — Betreiber-Entscheidung in #564, die
  -- Datenschutzerklärung sagt es. Das Ziel in der App reist als `route`.
  -- Eine Nachricht, die vor dem Lauf zurückgenommen oder mit der
  -- Freundschaft gelöscht wurde, ist per Cascade schon aus der
  -- Warteschlange — sie löst keine Meldung mehr aus.
  with due_msgs as (
    delete from app_internal.push_messages q
     using public.buddy_messages m
     where q.message_id = m.id
    returning m.sender_id, m.recipient_id, m.body, m.created_at
  ),
  per_sender as (
    select recipient_id, sender_id, count(*) as n,
           (array_agg(body order by created_at desc))[1] as last_body
      from due_msgs group by recipient_id, sender_id
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', coalesce(p.username, 'Buddy') ||
             case when s.n > 1 then ' · ' || s.n || ' Nachrichten'
                  else '' end,
           'body', case when char_length(s.last_body) > 180
                        then left(s.last_body, 179) || '…'
                        else s.last_body end,
           'route', '/friends/chat/' || s.sender_id))
    into message_payload
    from per_sender s
    join public.push_devices d on d.user_id = s.recipient_id
    left join public.profiles p on p.id = s.sender_id;

  payload := coalesce(payload, '[]'::jsonb) ||
             coalesce(message_payload, '[]'::jsonb);
  if jsonb_array_length(payload) = 0 then return 0; end if;
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
