-- Patch 032: Aliase für Buddys (#567).
--
-- > Man sollte für seine Buddies ein Alias vergeben können — wenn ein
-- > Buddy seinen Namen ändert, möchte ich noch wissen, wer es war.
-- > (Betreiber; „auf allen Geräten", 2026-09-23)
--
-- NUR FÜR DEN, DER IHN VERGIBT. Ein Alias ist eine private Notiz über
-- eine andere Person; der Buddy erfährt nie davon. Alle vier Policies
-- fragen `owner_id = auth.uid()`, anon hat gar keinen Grant.
--
-- NUR FÜR BESTÄTIGTE BUDDYS (`are_friends` beim Anlegen und Ändern) —
-- sonst ließe sich jedem Konto aus der Namenssuche ein Etikett anheften.
--
-- ENDE DER FREUNDSCHAFT LÖSCHT DEN ALIAS, beider Seiten (Trigger unten,
-- Definer wie `messages_on_unfriend`: die delete-Policy erlaubt jedem
-- nur die EIGENEN). Ohne Freundschaft taucht der Name ohnehin nirgends
-- mehr auf, und eine Notiz über jemanden, der kein Buddy mehr ist,
-- hätte keinen Zweck, der ihr Aufbewahren rechtfertigt (Betreiber).
--
-- Beide Personen auf auth.users, nicht auf profiles — dieselbe
-- Vorsicht wie bei Kudos, Meldungen und Nachrichten (PGRST201).
--
-- DIE PUSH ZIEHT MIT: `push_flush` wird neu angelegt und setzt als
-- Titel einer Nachrichten-Meldung den Alias des EMPFÄNGERS ein. Der
-- Rest der Funktion ist Zeichen für Zeichen der aus Patch 031.
--
-- KEIN Bump von minimum_supported_version: rein additiv.
create table public.friend_aliases (
  owner_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  alias text not null check (char_length(btrim(alias)) between 1 and 40),
  updated_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);
-- Für das Cascade beim Löschen des BUDDY-Kontos.
create index friend_aliases_friend_idx on public.friend_aliases (friend_id);

alter table public.friend_aliases enable row level security;
-- ERST alles weg: Die Legacy-Vorgabe `auto_expose_new_tables` gäbe anon
-- sonst Rechte (bis 2026-10-30, config.toml).
revoke all on public.friend_aliases from anon, authenticated;
grant select, insert, update, delete on public.friend_aliases to authenticated;

create policy fa_select on public.friend_aliases for select
  using (owner_id = auth.uid());
create policy fa_insert on public.friend_aliases for insert
  with check (owner_id = auth.uid()
    and app_internal.are_friends(owner_id, friend_id));
create policy fa_update on public.friend_aliases for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid()
    and app_internal.are_friends(owner_id, friend_id));
create policy fa_delete on public.friend_aliases for delete
  using (owner_id = auth.uid());

create or replace function app_internal.aliases_on_unfriend()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from friend_aliases a
  where (a.owner_id = old.requester_id and a.friend_id = old.addressee_id)
     or (a.owner_id = old.addressee_id and a.friend_id = old.requester_id);
  return old;
end;
$$;
revoke all on function app_internal.aliases_on_unfriend() from public, anon, authenticated;
create trigger friendships_delete_aliases
  after delete on public.friendships
  for each row execute function app_internal.aliases_on_unfriend();

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
           -- Der Alias, den der EMPFÄNGER vergeben hat (Patch 032) —
           -- sonst stünde in der Meldung ein anderer Name als in der App.
           'title', coalesce(a.alias, p.username, 'Buddy') ||
             case when s.n > 1 then ' · ' || s.n || ' Nachrichten'
                  else '' end,
           'body', case when char_length(s.last_body) > 180
                        then left(s.last_body, 179) || '…'
                        else s.last_body end,
           'route', '/friends/chat/' || s.sender_id))
    into message_payload
    from per_sender s
    join public.push_devices d on d.user_id = s.recipient_id
    left join public.profiles p on p.id = s.sender_id
    left join public.friend_aliases a
      on a.owner_id = s.recipient_id and a.friend_id = s.sender_id;

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
