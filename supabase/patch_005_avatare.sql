-- Patch 005: Pilz-Avatare für Profile.
-- Im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.
alter table public.profiles add column avatar int not null default 0;
drop function public.search_profiles(text);
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
