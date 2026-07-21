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

create table public.spots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text,
  lat double precision not null,
  lng double precision not null,
  sharing_excluded boolean not null default false,      -- einzelner Spot von der Freigabe ausgeschlossen
  created_at timestamptz not null default now()
);
create index spots_owner_idx on public.spots (owner_id);

create table public.finds (
  id uuid primary key default gen_random_uuid(),
  spot_id uuid not null references public.spots(id) on delete cascade,
  species text,
  count int check (count is null or count > 0),
  found_on date not null default current_date,
  note text,
  created_at timestamptz not null default now()
);
create index finds_spot_idx on public.finds (spot_id, found_on desc);

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

-- finds: Besitzer hat Vollzugriff über den Spot
create policy finds_owner_all on public.finds for all
  using (exists (select 1 from public.spots s
                 where s.id = spot_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.spots s
                 where s.id = spot_id and s.owner_id = auth.uid()));
-- finds: Freunde sehen Details NUR wenn der Besitzer Details teilt
create policy finds_friend_select on public.finds for select
  using (exists (select 1 from public.spots s
                 where s.id = spot_id
                   and s.owner_id <> auth.uid()
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
