-- Patch 016: Wiedervorlage ohne Doppel (Issue #267).
--
-- Der Ausgangskorb schreibt einen Fund, der ohne Empfang entstanden ist,
-- beim nächsten Netz nach. Dabei gibt es einen Fall, der ohne Hilfe aus
-- der Datenbank nicht lösbar ist: Die Verbindung bricht NACH dem
-- erfolgreichen Insert weg, aber bevor die Antwort ankommt. Der Client
-- sieht einen Fehlschlag, der Server hat die Zeile — und der nächste
-- Anlauf legt sie ein zweites Mal an. Im Wald mit einem Balken ist das
-- kein Randfall, sondern der Normalfall.
--
-- Die Lösung ist eine vom CLIENT vergebene Kennung je Auftrag: Sie
-- entsteht beim Eintragen, überlebt in der Warteschlange auf dem Gerät
-- und bleibt über alle Wiederholungen dieselbe. Der Unique-Index macht
-- den zweiten Insert damit zu einem Fehler mit klarer Bedeutung (23505:
-- „gab es schon"), statt zu einer stillen Dublette.
--
-- Warum je BESITZER bzw. AUTOR eindeutig und nicht global: Die Kennung
-- kommt vom Gerät. Global eindeutig hieße, dass ein fremdes Gerät mir
-- durch geschickt geratene Werte das Anlegen verbauen könnte; so reicht
-- die Eindeutigkeit genau so weit, wie sie gebraucht wird.
--
-- Partieller Index (`where client_id is not null`), weil die Spalte für
-- alle Zeilen leer bleibt, die nicht über den Korb kamen — das ist die
-- große Mehrheit, und mehrere NULLs müssen nebeneinander erlaubt sein.
--
-- KEIN Bump von minimum_supported_version: additiv und nullable. Ein
-- älterer Client sendet die Spalte nicht und schreibt weiter wie bisher;
-- er hat dann eben keinen Dublettenschutz, den er ohne Korb auch nicht
-- braucht.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- "Schema Check").

alter table public.spots
  add column client_id uuid;

alter table public.finds
  add column client_id uuid;

create unique index spots_owner_client_id_key
  on public.spots (owner_id, client_id)
  where client_id is not null;

create unique index finds_author_client_id_key
  on public.finds (author_id, client_id)
  where client_id is not null;

-- PostgREST-Schema-Cache sofort neu laden (neue Spalten), damit der
-- direkt anschließende Schema-Check nicht gegen die alte Oberfläche
-- prüft.
notify pgrst, 'reload schema';
