-- PilzBuddy — Supabase-Schema
-- Komplett im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.

-- ============================================================
-- Tabellen
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar int not null default 0,               -- Index im Pilz-Avatar-Katalog
  share_spots_default boolean not null default true,   -- "Alle Spots mit Freunden teilen"
  share_details boolean not null default true,          -- auch Art/Anzahl/Datum teilen, nicht nur Standort
  created_at timestamptz not null default now()
);
-- Einmalig auch über Groß-/Kleinschreibung hinweg (Patch 013): Die
-- Freundessuche matcht per ilike auf das Namens-Präfix, „Marcus" und
-- „marcus" wären für Suchende dasselbe Konto.
create unique index profiles_username_lower_key
  on public.profiles (lower(username));

create table public.spots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text,
  lat double precision not null,
  lng double precision not null,
  sharing_excluded boolean not null default false,      -- einzelner Spot von der Freigabe ausgeschlossen
  created_at timestamptz not null default now(),
  -- Vom Gerät vergebene Kennung des Auftrags aus dem Ausgangskorb
  -- (Patch 016): macht die Wiedervorlage nach einem abgerissenen Insert
  -- idempotent. Leer bei allem, was nicht über den Korb kam.
  client_id uuid
);
create index spots_owner_idx on public.spots (owner_id);
-- Zweimal derselbe Auftrag ⇒ 23505 statt Dublette. Partiell, weil die
-- Spalte für die große Mehrheit der Zeilen leer bleibt.
create unique index spots_owner_client_id_key
  on public.spots (owner_id, client_id)
  where client_id is not null;

create table public.finds (
  id uuid primary key default gen_random_uuid(),
  spot_id uuid not null references public.spots(id) on delete cascade,
  -- Jeder Fund gehört seinem Eintrager (Patch 014): Buddies dürfen an
  -- geteilten Spots Funde anlegen. Default auth.uid(), weil ältere
  -- Clients keine author_id senden; der Constraint-Name ist API-Vertrag
  -- (App und schema_check.sh embedden profiles!finds_author_id_fkey).
  author_id uuid not null default auth.uid()
    constraint finds_author_id_fkey
    references public.profiles(id) on delete cascade,
  species text,
  count int check (count is null or count > 0),
  found_on date not null default current_date,
  note text,
  created_at timestamptz not null default now(),
  -- „Nichts gefunden" (Patch 015): ein Fund ohne Fund — die Aussage gilt
  -- dem Ort, nicht einer Art. Weder Art noch Anzahl, sonst würde daraus
  -- über die Jahre ein schwächeres „keine Steinpilze".
  blank boolean not null default false,
  -- Siehe spots.client_id (Patch 016).
  client_id uuid,
  constraint finds_blank_leer
    check (not blank or (species is null and count is null))
);
create index finds_spot_idx on public.finds (spot_id, found_on desc);
create index finds_author_idx on public.finds (author_id);
create unique index finds_author_client_id_key
  on public.finds (author_id, client_id)
  where client_id is not null;

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  check (requester_id <> addressee_id)
);
-- verhindert doppelte Paare in beiden Richtungen
create unique index friendships_pair_uidx on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
-- RLS-Policies und are_friends filtern über diese Spalten (Patch 006)
create index friendships_requester_idx on public.friendships (requester_id);
create index friendships_addressee_idx on public.friendships (addressee_id);

-- Zeitlich begrenztes Live-Standort-Teilen: genau eine Zeile pro Nutzer
-- (Upsert bei jeder Positionsänderung). Freunde sehen die Zeile nur, solange
-- expires_at in der Zukunft liegt; „Teilen beenden" löscht sie.
create table public.live_locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null
);
-- Die Freundes-Select-Policy filtert über expires_at.
create index live_locations_expires_idx on public.live_locations (expires_at);

-- Feature-Wünsche / Feedback aus der App. Der Feedback-Bot
-- (.github/workflows/feedback.yml) macht daraus GitHub-Issues bzw.
-- Pilzart-PRs und setzt processed_at.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check (char_length(message) between 3 and 2000),
  type text not null default 'feature' check (type in ('feature', 'species', 'bug')),
  species_name text,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Gefangene Fehler aus dem Feld (Patch 009). Android Vitals sieht nur harte
-- Abstürze auf Play-Installationen — die abgefangenen Fehler, bei denen die
-- App mit einer SnackBar weiterläuft, landen hier. Absichtlich ohne
-- Nutzdaten: kein Standort, keine Namen.
create table public.error_reports (
  id uuid primary key default gen_random_uuid(),
  -- Nullable: die wertvollsten Fehler passieren vor der Anmeldung.
  user_id uuid references public.profiles(id) on delete cascade,
  context text not null check (char_length(context) between 1 and 100),
  error_type text not null check (char_length(error_type) <= 100),
  message text check (char_length(message) <= 1000),
  stack text check (char_length(stack) <= 4000),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);
create index error_reports_created_idx
  on public.error_reports (created_at desc);

-- Server-seitige App-Konfiguration (Patch 012). Einzeilige Tabelle: der
-- check lässt nur id = true zu. minimum_supported_version sperrt Clients
-- aus, die zu alt für das aktuelle Schema sind — jede Breaking-Migration
-- setzt den Wert im selben PR hoch (Issue #80).
create table public.app_config (
  id boolean primary key default true check (id),
  minimum_supported_version text not null default '0.0.0'
    check (minimum_supported_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  updated_at timestamptz not null default now()
);
insert into public.app_config (id) values (true);

-- Wohin eine Push-Benachrichtigung geht (#277, Patch 017). Eine Zeile je
-- Gerät; der Token ist der Schlüssel, weil FCM-Token global eindeutig
-- sind. Eine Zeile IST die Zustimmung — es gibt bewusst keine Spalte
-- „aktiv", die dasselbe ein zweites Mal behaupten könnte.
create table public.push_devices (
  token text primary key,
  user_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('android', 'web')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index push_devices_user_idx on public.push_devices (user_id);

-- Der Anlass, aus dem eine Meldung wird (#277, Patch 018). Der Schlüssel
-- ist (Empfänger, Art, Spot): Ein zweiter Fund am selben Spot trifft
-- dieselbe Zeile und schiebt nur die Fälligkeit — so werden aus zehn
-- Funden auf einem Waldgang nicht zehn Meldungen.
create table public.push_outbox (
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('buddy_find', 'new_spot')),
  spot_id uuid not null references public.spots(id) on delete cascade,
  due_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (recipient_id, kind, spot_id)
);
create index push_outbox_due_idx on public.push_outbox (due_at);

-- ============================================================
-- Profil automatisch bei Registrierung anlegen
-- (Username kommt aus den Signup-Metadaten der App)
-- ============================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'username',
                   'pilzfreund_' || substr(new.id::text, 1, 8)));
  return new;
end $$;

-- Nur der Trigger ruft die Funktion — die Default-Grants an die API-Rollen
-- sind unnötig (EXECUTE wird beim Anlegen des Triggers geprüft, nicht beim
-- Feuern).
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================
-- Hilfsfunktionen (SECURITY DEFINER, damit RLS-Policies andere
-- Tabellen lesen können, ohne zu rekursieren)
--
-- Bewusst NICHT in public: PostgREST exponiert jede Funktion im
-- public-Schema als /rest/v1/rpc/-Endpunkt für anon+authenticated.
-- EXECUTE entziehen geht nicht — die Policies werten die Funktionen
-- mit den Rechten der anfragenden Rolle aus. Deshalb liegen sie in
-- app_internal, das die API nie sieht (Patch 011).
-- ============================================================

create schema if not exists app_internal;
grant usage on schema app_internal to anon, authenticated;

create or replace function app_internal.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b)
        or (requester_id = b and addressee_id = a)));
$$;

-- Auch offene Anfragen zählen — nötig, damit man den Namen des
-- Absenders einer Freundschaftsanfrage sehen kann.
create or replace function app_internal.involved_in_friendship(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where (requester_id = a and addressee_id = b)
       or (requester_id = b and addressee_id = a));
$$;

create or replace function app_internal.owner_shares_spots(owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select share_spots_default from profiles where id = owner;
$$;

create or replace function app_internal.owner_shares_details(owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select share_details from profiles where id = owner;
$$;

-- Freundesuche: exakte E-Mail oder Username-Präfix; gibt nie E-Mails zurück.
create or replace function public.search_profiles(query text)
returns table (id uuid, username text, display_name text, avatar int)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name, p.avatar
  from profiles p
  left join auth.users u on u.id = p.id
  where p.id <> auth.uid()
    and (lower(u.email) = lower(query) or p.username ilike query || '%')
  limit 10;
$$;
-- Nur für Angemeldete: für anon wäre der exakte E-Mail-Vergleich ein
-- E-Mail-Orakel (verrät ohne Konto, ob eine Adresse registriert ist).
revoke all on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated;

-- Konto-Löschung durch den Nutzer selbst (Play-Anforderung, Patch 008).
-- Alle Tabellen hängen per `on delete cascade` an profiles und profiles an
-- auth.users — das Löschen des Auth-Users räumt daher alles mit ab.
-- Kein Parameter: auth.uid() kommt aus dem JWT, eine übergebene id wäre eine
-- Einladung, fremde Konten zu löschen.
create or replace function public.delete_own_account()
returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_own_account() from public;
revoke all on function public.delete_own_account() from anon;
grant execute on function public.delete_own_account() to authenticated;

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.profiles       enable row level security;
alter table public.spots          enable row level security;
alter table public.finds          enable row level security;
alter table public.friendships    enable row level security;
alter table public.live_locations enable row level security;
alter table public.feedback       enable row level security;
alter table public.error_reports  enable row level security;
alter table public.app_config     enable row level security;
alter table public.push_devices   enable row level security;
alter table public.push_outbox    enable row level security;

-- app_config: lesen darf jeder, auch anon — die Mindestversion wird beim
-- Start und damit vor der Anmeldung geprüft. Geändert wird der Wert über
-- einen Patch, deshalb kein insert/update/delete-Grant.
create policy app_config_read on public.app_config for select using (true);
grant select on public.app_config to anon, authenticated;

-- push_devices: nur die eigenen Geräte, in beide Richtungen. Ohne das
-- `with check` könnte jemand ein Token auf ein fremdes Konto schreiben
-- und dessen Meldungen mitbekommen. Für den Versender gibt es bewusst
-- KEINE Policy — er liest mit service_role und umgeht RLS; eine Policy
-- wäre die Einladung, den Weg später über einen schwächeren Schlüssel zu
-- gehen.
create policy push_devices_own_all on public.push_devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- push_outbox: bewusst OHNE Policy, wie error_reports. Über die API liest
-- und schreibt hier niemand — die Trigger laufen als security definer,
-- der Versender mit service_role. Eine Policy wäre eine Tür, die niemand
-- braucht.

-- error_reports: schreiben darf jeder, auch anon — sonst fehlen genau die
-- Fehler aus Login und Registrierung. Eine fremde user_id lässt sich nicht
-- unterschieben. LESEN darf niemand über die API: es gibt bewusst keine
-- select-Policy, die Auswertung läuft über das Dashboard.
create policy er_insert on public.error_reports for insert
  with check (user_id is null or user_id = auth.uid());
grant insert on public.error_reports to anon, authenticated;

-- feedback: eigene Wünsche einreichen und nachlesen
create policy feedback_insert on public.feedback for insert
  with check (user_id = auth.uid());
create policy feedback_select_own on public.feedback for select
  using (user_id = auth.uid());

-- profiles: ich selbst + alle, mit denen eine (auch offene) Freundschaft
-- besteht (Suche läuft über search_profiles)
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or app_internal.involved_in_friendship(id, auth.uid()));
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- spots: Besitzer hat Vollzugriff
create policy spots_owner_all on public.spots for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- spots: Freunde sehen geteilte, nicht ausgeschlossene Spots (nur Standort-Ebene)
create policy spots_friend_select on public.spots for select
  using (owner_id <> auth.uid()
     and app_internal.are_friends(owner_id, auth.uid())
     and not sharing_excluded
     and app_internal.owner_shares_spots(owner_id));

-- finds: Jeder Fund gehört seinem EINTRAGER (Patch 014). Eigene Funde:
-- voller Zugriff, überall — auch wenn die Freigabe später endet (jeder
-- behält die eigenen Funde). Der with check bindet das ANLEGEN an die
-- Sichtbarkeit des Spots: eigener Spot oder volle Freigabe-Beziehung
-- zum Besitzer. Die Bedingungen stehen absichtlich ausgeschrieben,
-- obwohl die spots-RLS im Subselect ohnehin greift — eine später
-- großzügigere spots-Sichtbarkeit soll das Schreibrecht nicht
-- stillschweigend mitweiten.
create policy finds_author_all on public.finds for all
  using (author_id = auth.uid())
  with check (author_id = auth.uid()
    and exists (select 1 from public.spots s
                where s.id = spot_id
                  and (s.owner_id = auth.uid()
                    or (app_internal.are_friends(s.owner_id, auth.uid())
                        and not s.sharing_excluded
                        and app_internal.owner_shares_spots(s.owner_id)))));
-- finds: Der Spot-Besitzer sieht fremde Funde nur, solange die
-- Freigabe-Beziehung zum AUTOR besteht — symmetrisch zur Sicht des
-- Freundes auf den Spot. Kein owner_shares_details-Gate: Der Autor hat
-- den Fund wissentlich auf diesen Spot geschrieben.
create policy finds_owner_select on public.finds for select
  using (author_id <> auth.uid()
    and exists (select 1 from public.spots s
                where s.id = spot_id
                  and s.owner_id = auth.uid()
                  and not s.sharing_excluded)
    and app_internal.are_friends(author_id, auth.uid())
    and app_internal.owner_shares_spots(auth.uid()));
-- finds: Freunde sehen Fund-Details nur mit Detail-Freigabe des
-- Besitzers — beschränkt auf dessen EIGENE Funde (author_id =
-- s.owner_id): Funde dritter Buddies wandern nie zu Nicht-Freunden.
-- Die eigenen Funde am Freundes-Spot liefert finds_author_all.
create policy finds_friend_select on public.finds for select
  using (exists (select 1 from public.spots s
                 where s.id = spot_id
                   and s.owner_id <> auth.uid()
                   and author_id = s.owner_id
                   and app_internal.are_friends(s.owner_id, auth.uid())
                   and not s.sharing_excluded
                   and app_internal.owner_shares_spots(s.owner_id)
                   and app_internal.owner_shares_details(s.owner_id)));

-- friendships
create policy fr_select on public.friendships for select
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy fr_insert on public.friendships for insert
  with check (requester_id = auth.uid() and status = 'pending');
create policy fr_accept on public.friendships for update
  using (addressee_id = auth.uid() and status = 'pending')
  with check (status = 'accepted');
create policy fr_delete on public.friendships for delete   -- ablehnen / zurückziehen / entfreunden
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- live_locations: eigene Zeile voll verwalten (upsert/löschen/lesen),
-- Freunde sehen sie nur, solange die Freigabe nicht abgelaufen ist.
create policy ll_owner_all on public.live_locations for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ll_friend_select on public.live_locations for select
  using (user_id <> auth.uid()
     and app_internal.are_friends(user_id, auth.uid())
     and expires_at > now());

-- ---------------------------------------------------------------------------
-- Patch-Buchführung
-- ---------------------------------------------------------------------------
-- Dieselbe Tabelle legt auch tool/db_migrate.sh an (`if not exists`) — sie
-- muss dort stehen, weil die Live-Datenbank diese Datei nie im Ganzen sieht.
create table if not exists public.applied_patches (
  filename text primary key,
  applied_at timestamptz not null default now()
);
alter table public.applied_patches enable row level security;
revoke all on table public.applied_patches from anon, authenticated;

-- Diese Datei bildet den Stand NACH den folgenden Patches ab. Sie werden
-- deshalb nur eingetragen, nicht ausgeführt: Ein erneuter Lauf über ein
-- Schema, das ihr Ergebnis schon enthält, verlangte von jedem alten Patch
-- auf Dauer Idempotenz — und zwang dazu, alte Patches nachträglich zu
-- ändern, sobald ein neuerer ihre Voraussetzungen verschob (so geschehen
-- bei patch_007, als patch_011 die Helfer nach app_internal zog). Genau das
-- ist gefährlich: Live läuft ein bereits eingespielter Patch nie wieder, die
-- Änderung landet also ausschließlich in Frischinstallationen, und beide
-- Welten driften still auseinander.
--
-- Folge: Ein neuer patch_NNN gehört im selben PR HIER in die Liste und in
-- die Struktur oben. `tool/patch_guard.sh` erzwingt beides.
-- ============================================================
-- Push: Auslöser und Versand (#277, Patch 018)
-- ============================================================
--
-- Wer benachrichtigt wird, ist NICHT neu entschieden: Es sind exakt die,
-- die den Vorgang ohnehin sehen dürfen — dieselben Bedingungen wie in
-- den Policies oben. Eine Meldung über etwas, das man in der App nicht
-- finden kann, wäre schlimmer als keine.

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- ------------------------------------------------------------- Der Korb
--
-- Der Schlüssel ist (Empfänger, Art, Spot): Ein zweiter Fund am selben
-- Spot trifft dieselbe Zeile und schiebt nur die Fälligkeit — genau das
-- ist das Entprellen. Der Spot steht drin, damit zwei verschiedene Spots
-- getrennt melden; sein Name wandert NIE in eine Nutzlast.

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

insert into public.applied_patches (filename) values
  ('patch_001_anfragen_namen.sql'),
  ('patch_002_feedback.sql'),
  ('patch_003_feedback_typen.sql'),
  ('patch_004_feedback_bug.sql'),
  ('patch_005_avatare.sql'),
  ('patch_006_friendship_indexe.sql'),
  ('patch_007_live_locations.sql'),
  ('patch_008_konto_loeschen.sql'),
  ('patch_009_fehlerberichte.sql'),
  ('patch_010_applied_patches_rls.sql'),
  ('patch_011_interne_funktionen.sql'),
  ('patch_012_mindestversion.sql'),
  ('patch_013_username_gross_klein.sql'),
  ('patch_014_buddy_funde.sql'),
  ('patch_015_leergang.sql'),
  ('patch_016_client_id.sql'),
  ('patch_017_push_geraete.sql'),
  ('patch_018_push_ausloeser.sql')
on conflict do nothing;
