-- PilzBuddy — Supabase-Schema
-- Komplett im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.

-- ============================================================
-- Tabellen
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
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

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================
-- Hilfsfunktionen (SECURITY DEFINER, damit RLS-Policies andere
-- Tabellen lesen können, ohne zu rekursieren)
-- ============================================================

create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b)
        or (requester_id = b and addressee_id = a)));
$$;

-- Auch offene Anfragen zählen — nötig, damit man den Namen des
-- Absenders einer Freundschaftsanfrage sehen kann.
create or replace function public.involved_in_friendship(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where (requester_id = a and addressee_id = b)
       or (requester_id = b and addressee_id = a));
$$;

create or replace function public.owner_shares_spots(owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select share_spots_default from profiles where id = owner;
$$;

create or replace function public.owner_shares_details(owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select share_details from profiles where id = owner;
$$;

-- Freundesuche: exakte E-Mail oder Username-Präfix; gibt nie E-Mails zurück.
create or replace function public.search_profiles(query text)
returns table (id uuid, username text, display_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name
  from profiles p
  left join auth.users u on u.id = p.id
  where p.id <> auth.uid()
    and (lower(u.email) = lower(query) or p.username ilike query || '%')
  limit 10;
$$;

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.profiles    enable row level security;
alter table public.spots       enable row level security;
alter table public.finds       enable row level security;
alter table public.friendships enable row level security;

-- profiles: ich selbst + alle, mit denen eine (auch offene) Freundschaft
-- besteht (Suche läuft über search_profiles)
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or public.involved_in_friendship(id, auth.uid()));
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- spots: Besitzer hat Vollzugriff
create policy spots_owner_all on public.spots for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- spots: Freunde sehen geteilte, nicht ausgeschlossene Spots (nur Standort-Ebene)
create policy spots_friend_select on public.spots for select
  using (owner_id <> auth.uid()
     and public.are_friends(owner_id, auth.uid())
     and not sharing_excluded
     and public.owner_shares_spots(owner_id));

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
                   and public.are_friends(s.owner_id, auth.uid())
                   and not s.sharing_excluded
                   and public.owner_shares_spots(s.owner_id)
                   and public.owner_shares_details(s.owner_id)));

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
