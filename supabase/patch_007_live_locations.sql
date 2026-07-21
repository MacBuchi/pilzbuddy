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
-- Rückwirkend angepasst mit Patch 011: are_friends liegt seitdem in
-- app_internal statt public. In die Live-DB ging dieser Patch 2026-07-19
-- noch mit public.are_friends — die Policy dort folgte dem Umzug per OID
-- automatisch. Die Änderung hier braucht nur die Frischinstallation, bei
-- der dieser Patch NACH dem aktuellen schema.sql erneut läuft und
-- public.are_friends nicht mehr existiert.
create policy ll_friend_select on public.live_locations for select
  using (user_id <> auth.uid()
     and app_internal.are_friends(user_id, auth.uid())
     and expires_at > now());
