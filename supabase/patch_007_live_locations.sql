-- Patch 007: Zeitlich begrenztes Live-Standort-Teilen mit Freunden.
-- Eine Zeile pro Nutzer (Upsert bei jeder Positionsänderung); Freunde
-- sehen die Zeile nur, solange expires_at in der Zukunft liegt. RLS nutzt
-- die vorhandene are_friends-Funktion. Wird automatisch eingespielt
-- (tool/db_migrate.sh über den Pflicht-Check "Schema Check").
create table if not exists public.live_locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index if not exists live_locations_expires_idx
  on public.live_locations (expires_at);

alter table public.live_locations enable row level security;

drop policy if exists ll_owner_all on public.live_locations;
create policy ll_owner_all on public.live_locations for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists ll_friend_select on public.live_locations;
create policy ll_friend_select on public.live_locations for select
  using (user_id <> auth.uid()
     and public.are_friends(user_id, auth.uid())
     and expires_at > now());
