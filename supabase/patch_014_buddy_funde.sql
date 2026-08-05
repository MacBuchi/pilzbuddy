-- Patch 014: Pilz-Buddies dürfen Funde an geteilten Spots eintragen
-- (Issue #190).
--
-- Bisher gehörte ein Fund implizit dem Spot-Besitzer: finds hat kein
-- Nutzerfeld, und finds_owner_all läuft über spots.owner_id. Ab jetzt
-- gehört jeder Fund seinem EINTRAGER (author_id), und Freunde dürfen an
-- geteilten Spots Funde anlegen — Schreibrecht exakt unter den
-- Bedingungen, unter denen sie den Spot sehen (are_friends + not
-- sharing_excluded + owner_shares_spots). Endet die Freigabe
-- (Entfreunden, globaler Schalter, Spot-Ausschluss), sieht jeder nur
-- noch die eigenen Funde — symmetrisch, per RLS versteckt statt
-- gelöscht; erneute Freundschaft stellt beides wieder her. Funde
-- DRITTER Buddies bleiben verborgen: Ein Freund sieht am Spot nur die
-- Funde des Spot-Besitzers (mit dessen owner_shares_details-Gate wie
-- bisher) und seine eigenen — Fund-Daten wandern nie zu Nicht-Freunden.
--
-- KEIN Bump von minimum_supported_version: Alte Clients laufen
-- unverändert weiter — die neue Spalte im finds(*)-Embed ignoriert ihr
-- Find.fromJson, ihre Inserts füllt der Spalten-Default, und dass ein
-- Besitzer auf altem Client Buddy-Funde ohne Zuschreibung sieht, ist
-- kosmetisch.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- "Schema Check").

-- 1) Autor-Spalte. Der Default steht in DERSELBEN Anweisung: Sobald der
--    Patch committet ist, füllen sich Inserts alter Clients (die keine
--    author_id senden) von selbst. Für die Migration selbst ist der
--    Default egal — auth.uid() ist außerhalb eines API-Requests null,
--    die Bestandszeilen füllt der Backfill darunter. Der Constraint-Name
--    ist API-Vertrag: schema_check.sh und die App embedden den Autor
--    über profiles!finds_author_id_fkey. on delete cascade wie überall:
--    Konto-Löschung räumt auch Funde an fremden Spots mit ab.
alter table public.finds
  add column author_id uuid
    constraint finds_author_id_fkey
    references public.profiles(id) on delete cascade
    default auth.uid();

-- 2) Bestand: Bis zu diesem Patch konnte nur der Spot-Besitzer Funde
--    anlegen — der Eintrager IST also der Besitzer.
update public.finds f
  set author_id = s.owner_id
  from public.spots s
  where s.id = f.spot_id
    and f.author_id is null;

alter table public.finds alter column author_id set not null;

-- 3) Die neuen Policies und die Lösch-Kaskade filtern über den Autor.
create index finds_author_idx on public.finds (author_id);

-- 4) Policies neu, drop + create statt alter: Die Semantik wechselt von
--    „Besitzer des Spots" auf „Autor des Funds" — ein neuer Satz ist
--    ehrlicher als ein umgebogener alter.
drop policy finds_owner_all on public.finds;
drop policy finds_friend_select on public.finds;

-- Eigene Funde: voller Zugriff, überall — auch wenn die Freigabe später
-- endet (jeder behält die eigenen Funde). Der with check bindet das
-- ANLEGEN an die Sichtbarkeit des Spots: eigener Spot oder volle
-- Freigabe-Beziehung zum Besitzer. Die Bedingungen stehen absichtlich
-- ausgeschrieben, obwohl die spots-RLS im Subselect ohnehin greift —
-- eine später großzügigere spots-Sichtbarkeit soll das Schreibrecht
-- nicht stillschweigend mitweiten.
create policy finds_author_all on public.finds for all
  using (author_id = auth.uid())
  with check (author_id = auth.uid()
    and exists (select 1 from public.spots s
                where s.id = spot_id
                  and (s.owner_id = auth.uid()
                    or (app_internal.are_friends(s.owner_id, auth.uid())
                        and not s.sharing_excluded
                        and app_internal.owner_shares_spots(s.owner_id)))));

-- Der Spot-Besitzer sieht fremde Funde auf seinen Spots nur, solange
-- die Freigabe-Beziehung zum AUTOR besteht — symmetrisch zur Sicht des
-- Freundes auf den Spot: dieselbe Freundschaft, derselbe globale
-- Schalter (hier der EIGENE), derselbe Spot-Ausschluss. Kein
-- owner_shares_details-Gate: Der Autor hat den Fund wissentlich auf
-- diesen Spot geschrieben.
create policy finds_owner_select on public.finds for select
  using (author_id <> auth.uid()
    and exists (select 1 from public.spots s
                where s.id = spot_id
                  and s.owner_id = auth.uid()
                  and not s.sharing_excluded)
    and app_internal.are_friends(author_id, auth.uid())
    and app_internal.owner_shares_spots(auth.uid()));

-- Wie bisher: Freunde sehen Fund-Details nur mit Detail-Freigabe des
-- Besitzers — NEU beschränkt auf dessen EIGENE Funde (author_id =
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

-- PostgREST-Schema-Cache sofort neu laden (neue Spalte + neuer FK fürs
-- author-Embed), damit der direkt anschließende Schema-Check nicht gegen
-- die alte Oberfläche prüft.
notify pgrst, 'reload schema';
