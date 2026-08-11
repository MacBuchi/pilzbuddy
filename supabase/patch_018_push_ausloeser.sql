-- Patch 018: Wann eine Push-Benachrichtigung entsteht (Issue #277, Teil 2).
--
-- Patch 017 hat das Geräteregister angelegt und `send-push` konnte eine
-- Testnachricht schicken. Hier kommt der Anlass dazu: ein Buddy trägt an
-- einem Spot einen Fund ein, oder er legt einen neuen an.
--
-- **Wer etwas erfährt, ist NICHT neu entschieden.** Die Empfänger sind
-- exakt die, die den Vorgang ohnehin sehen dürfen — dieselben
-- Bedingungen wie in den Policies aus Patch 014 (`are_friends`,
-- `not sharing_excluded`, `owner_shares_spots`, bei fremden Blicken auf
-- eigene Funde zusätzlich `owner_shares_details`). Eine Meldung über
-- etwas, das man in der App nicht finden kann, wäre schlimmer als keine.
--
-- **Warum ein Korb und kein direkter Aufruf beim Insert.** Zehn Funde
-- auf einem Waldgang dürfen nicht zehn Meldungen sein. Der Auslöser legt
-- deshalb nur eine Zeile ab und schiebt ihre Fälligkeit vor sich her;
-- erst wenn Ruhe eingekehrt ist, geht eine einzige Meldung raus. Das
-- passt auch zum Ausgangskorb der App (#267): Ein Fund aus dem Funkloch
-- löst aus, wenn die Zeile WIRKLICH landet, nicht wenn jemand
-- „gespeichert" getippt hat.
--
-- KEIN Bump von minimum_supported_version: Für die App ändert sich
-- nichts, sie liest keine dieser Tabellen.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- „Schema Check").

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- ------------------------------------------------------------- Der Korb
--
-- Der Schlüssel ist (Empfänger, Art, Spot): Ein zweiter Fund am selben
-- Spot trifft dieselbe Zeile und schiebt nur die Fälligkeit — genau das
-- ist das Entprellen. Der Spot steht drin, damit zwei verschiedene Spots
-- getrennt melden; sein Name wandert NIE in eine Nutzlast.
create table public.push_outbox (
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('buddy_find', 'new_spot')),
  spot_id uuid not null references public.spots(id) on delete cascade,
  -- Wann frühestens rausgehen darf. Jeder weitere Anlass schiebt es vor
  -- sich her …
  due_at timestamptz not null,
  -- … aber nicht endlos: `created_at` ist die Reißleine. Wer drei Stunden
  -- am Stück Funde einträgt, dessen Buddy soll trotzdem etwas erfahren.
  created_at timestamptz not null default now(),
  primary key (recipient_id, kind, spot_id)
);

create index push_outbox_due_idx on public.push_outbox (due_at);

alter table public.push_outbox enable row level security;

-- Bewusst OHNE Policy, wie `error_reports`: Über die API liest und
-- schreibt hier niemand. Die Trigger laufen als security definer, der
-- Versender mit service_role — beide umgehen RLS. Eine Policy wäre eine
-- Tür, die niemand braucht.

-- ------------------------------------------------------- Die Fälligkeit
--
-- Fünf Minuten Ruhe, gedeckelt auf eine halbe Stunde ab dem ersten
-- Anlass. Die Zahlen stehen hier an EINER Stelle, damit sie nicht
-- zwischen den beiden Triggern auseinanderlaufen.
create or replace function app_internal.push_due_at(first_seen timestamptz)
returns timestamptz
language sql immutable as $$
  select least(now() + interval '5 minutes', first_seen + interval '30 minutes');
$$;

-- --------------------------------------------------------- Die Auslöser

-- Ein Fund ist eingetragen worden. Zwei Fälle, und sie haben
-- verschiedene Empfänger:
--
--   1. Ein Buddy trägt an einem FREMDEN Spot ein  -> der Besitzer erfährt
--      es (Spiegel von `finds_owner_select`).
--   2. Jemand trägt am EIGENEN Spot ein           -> seine Buddys
--      erfahren es (Spiegel von `finds_friend_select`, inklusive des
--      Detail-Gates: Wer seine Funde nicht teilt, meldet auch nichts).
--
-- Leergänge (`blank`, #211) lösen bewusst NICHTS aus: „Ich war da und
-- habe nichts gefunden" ist für einen Buddy keine Nachricht wert.
create or replace function app_internal.push_on_find()
returns trigger
language plpgsql security definer
set search_path = public, app_internal as $$
declare
  spot public.spots%rowtype;
begin
  if new.blank then return new; end if;
  select * into spot from public.spots where id = new.spot_id;
  if not found then return new; end if;

  if new.author_id <> spot.owner_id then
    if app_internal.are_friends(spot.owner_id, new.author_id)
       and not spot.sharing_excluded
       and app_internal.owner_shares_spots(spot.owner_id) then
      insert into public.push_outbox (recipient_id, kind, spot_id, due_at)
        values (spot.owner_id, 'buddy_find', spot.id,
                app_internal.push_due_at(now()))
        on conflict (recipient_id, kind, spot_id) do update
          set due_at = app_internal.push_due_at(push_outbox.created_at);
    end if;
    return new;
  end if;

  if spot.sharing_excluded
     or not app_internal.owner_shares_spots(spot.owner_id)
     or not app_internal.owner_shares_details(spot.owner_id) then
    return new;
  end if;
  insert into public.push_outbox (recipient_id, kind, spot_id, due_at)
    select f.friend_id, 'buddy_find', spot.id, app_internal.push_due_at(now())
      from app_internal.push_friends(spot.owner_id) f
    on conflict (recipient_id, kind, spot_id) do update
      set due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;

-- Ein neuer Spot. Empfänger sind die Buddys, die ihn sehen dürfen —
-- Spiegel der spots-Policy. Kein Detail-Gate: Es geht um den Spot, nicht
-- um seine Funde.
create or replace function app_internal.push_on_spot()
returns trigger
language plpgsql security definer
set search_path = public, app_internal as $$
begin
  if new.sharing_excluded
     or not app_internal.owner_shares_spots(new.owner_id) then
    return new;
  end if;
  insert into public.push_outbox (recipient_id, kind, spot_id, due_at)
    select f.friend_id, 'new_spot', new.id, app_internal.push_due_at(now())
      from app_internal.push_friends(new.owner_id) f
    on conflict (recipient_id, kind, spot_id) do nothing;
  return new;
end $$;

-- Die angenommenen Freundschaften einer Person, in eine Richtung
-- aufgelöst. Eigene Funktion, weil beide Trigger sie brauchen und die
-- Richtung sonst zweimal dastünde.
create or replace function app_internal.push_friends(person uuid)
returns table (friend_id uuid)
language sql stable as $$
  select case when requester_id = person then addressee_id else requester_id end
    from public.friendships
   where status = 'accepted'
     and (requester_id = person or addressee_id = person);
$$;

create trigger push_on_find_trg after insert on public.finds
  for each row execute function app_internal.push_on_find();

create trigger push_on_spot_trg after insert on public.spots
  for each row execute function app_internal.push_on_spot();

-- ---------------------------------------------------------- Der Versand
--
-- Holt die fälligen Zeilen, macht daraus Nachrichten je Gerät und ruft
-- `send-push`. Die drei Geheimnisse stehen im VAULT und NICHT hier —
-- ein Patch liegt öffentlich im Repo. Von Hand anzulegen (einmalig, im
-- SQL-Editor des Dashboards):
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1',
--                              'push_functions_url');
--   select vault.create_secret('<PUSH_JOB_SECRET>', 'push_job_secret');
--   select vault.create_secret('<SERVICE_ROLE_KEY>', 'push_service_key');
--
-- **Fehlt eines davon, tut die Funktion NICHTS** — sie wirft nicht. Der
-- Patch spielt beim Merge ein, die Geheimnisse kommen von Hand: Ohne
-- diese Nachsicht liefe ab dem Merge jede Minute ein scheiternder
-- Cron-Job in der Produktion. So schaltet sich der Versand in dem
-- Moment ein, in dem die Geheimnisse stehen.
--
-- Der Text ist ABSICHTLICH nichtssagend: keine Koordinaten, kein
-- Spot-Name, kein Benutzername. Eine Push läuft über Googles Server.
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
  if base_url is null or job_secret is null or service_key is null then
    return 0;
  end if;

  with due as (
    delete from public.push_outbox
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
revoke all on function app_internal.push_due_at(timestamptz) from public, anon, authenticated;
revoke all on function app_internal.push_friends(uuid) from public, anon, authenticated;

-- Jede Minute. Der Takt bestimmt nur die Verzögerung NACH der
-- Entprell-Frist; teuer ist er nicht, weil ohne fällige Zeilen nichts
-- passiert.
select cron.schedule('push-flush', '* * * * *',
                     $cron$select app_internal.push_flush()$cron$);

notify pgrst, 'reload schema';
