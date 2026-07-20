-- Patch 008: Konto-Löschung durch den Nutzer selbst.
--
-- Google Play verlangt für Apps mit Registrierung eine Löschmöglichkeit in
-- der App und über eine Web-URL. Fachlich reicht dafür EINE Zeile: alle
-- Tabellen hängen über `on delete cascade` an public.profiles, und profiles
-- hängt genauso an auth.users. Das Löschen des Auth-Users räumt damit
-- Spots, Funde, Freundschaften (beide Richtungen), Live-Standort und
-- Feedback automatisch mit ab.
--
-- security definer, weil auth.users dem Rollen-Eigentümer supabase_auth_admin
-- gehört und ein normaler Nutzer dort nichts löschen darf. Die Funktion
-- löscht ausschließlich das eigene Konto — auth.uid() kommt aus dem JWT und
-- ist nicht vom Aufrufer setzbar. Deshalb braucht sie auch keinen Parameter:
-- eine id als Argument wäre eine Einladung, fremde Konten zu löschen.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- "Schema Check").

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
-- Fester search_path: sonst könnte ein untergeschobenes Schema die
-- Bedeutung von `auth.users` verändern (klassische Falle bei definer-Rechten).
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;

-- Nur angemeldete Nutzer. anon darf die Funktion nicht einmal aufrufen —
-- der Schema-Check prüft genau das (403 statt "Funktion nicht gefunden").
revoke all on function public.delete_own_account() from public;
revoke all on function public.delete_own_account() from anon;
grant execute on function public.delete_own_account() to authenticated;
