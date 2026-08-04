-- Patch 013: Benutzernamen auch über Groß-/Kleinschreibung hinweg
-- einmalig machen (Issue #194).
--
-- `username text unique not null` gilt seit dem ersten Schema, ist aber
-- case-sensitiv: „Marcus" und „marcus" dürfen nebeneinander existieren.
-- Die Freundessuche (search_profiles) matcht per ilike auf das
-- Namens-Präfix — der Name ist also eine suchbare Identität, und zwei
-- nur in der Schreibung verschiedene Konten wären für Suchende dasselbe
-- Konto. Der bestehende Constraint bleibt stehen (Wegräumen wäre Churn
-- ohne Nutzen); dieser Index verschärft ihn.
--
-- Gibt es live bereits solche Duplikate, schlägt CREATE INDEX fehl und
-- der Schema Check bleibt rot — das ist gewollt: Dann wird EIN Konto
-- umbenannt statt still ein Zustand legalisiert, den die App ab jetzt
-- verhindert.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- "Schema Check").

create unique index profiles_username_lower_key
  on public.profiles (lower(username));
