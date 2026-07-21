-- Patch 011: SECURITY-DEFINER-Funktionen von der API-Oberfläche nehmen
-- (Supabase-Advisor: anon/authenticated_security_definer_function_executable,
-- Folge-Meldungen zur RLS-Warnung vom 20.07.2026).
--
-- Jede Funktion im public-Schema ist automatisch ein API-Endpunkt
-- (/rest/v1/rpc/<name>), und der Postgres-Default-Grant an PUBLIC macht sie
-- für anon UND authenticated aufrufbar. Das war für drei Gruppen zu viel:
--
-- 1. Policy-Helfer (are_friends, involved_in_friendship, owner_shares_*):
--    per direktem RPC konnte jeder Angemeldete (fremde UUIDs liefert die
--    Freundesuche) das Freundschaftsverhältnis beliebiger DRITTER abfragen
--    und fremde Freigabe-Einstellungen auslesen. EXECUTE entziehen geht
--    nicht: die Policies werten die Funktionen mit den Rechten der
--    anfragenden Rolle aus, ein Revoke bräche jedes select auf
--    spots/finds/profiles/live_locations. Stattdessen Umzug in ein nicht
--    exponiertes Schema — PostgREST kennt nur public. `alter function …
--    set schema` erhält die OID, und Policies referenzieren Funktionen
--    per OID: sie laufen unverändert weiter.
-- 2. search_profiles: für anon aufrufbar war das ein E-Mail-Orakel ohne
--    Konto (der exakte E-Mail-Vergleich verrät, ob eine Adresse registriert
--    ist) plus freie Username-Enumeration. Ab jetzt nur für authenticated —
--    die App ruft die Suche ohnehin nur angemeldet auf.
-- 3. handle_new_user: Trigger-Funktionen sind per RPC ohnehin nicht
--    ausführbar, die Grants waren schlicht unnötig. Der Trigger feuert
--    weiter — EXECUTE wird beim Anlegen des Triggers geprüft, nicht beim
--    Feuern.

create schema if not exists app_internal;
-- USAGE für die API-Rollen: die Policy-Auswertung ruft die Funktionen als
-- anon/authenticated auf. Exponiert wird das Schema dadurch nicht.
grant usage on schema app_internal to anon, authenticated;

-- Bedingt statt direkt: auf einer Frischinstallation legt das aktuelle
-- schema.sql die Helfer bereits in app_internal an — dieser Patch läuft
-- dort trotzdem und darf dann nicht an fehlendem public.<fn> scheitern.
do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('are_friends', 'involved_in_friendship',
                        'owner_shares_spots', 'owner_shares_details')
  loop
    execute format('alter function %s set schema app_internal', fn.sig);
  end loop;
end $$;

revoke all on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated;

revoke all on function public.handle_new_user() from public, anon, authenticated;

-- PostgREST-Schema-Cache sofort neu laden, damit der direkt anschließende
-- Schema-Check nicht gegen die alte RPC-Oberfläche prüft.
notify pgrst, 'reload schema';
