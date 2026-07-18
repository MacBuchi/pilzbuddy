-- Patch 001: Benutzernamen bei offenen Freundschaftsanfragen sichtbar machen.
-- Im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.
-- (Nur nötig, wenn schema.sql vor diesem Patch eingespielt wurde.)

create or replace function public.involved_in_friendship(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where (requester_id = a and addressee_id = b)
       or (requester_id = b and addressee_id = a));
$$;

drop policy profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or public.involved_in_friendship(id, auth.uid()));
