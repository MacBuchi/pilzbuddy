-- Patch 015: „Nichts gefunden" als eigener Eintrag (Issue #211).
--
-- Die App kennt bisher nur Erfolge. Für die Pilzampel
-- (docs/pilzampel-konzept.md) ist das die entscheidende Lücke: Wetterdaten
-- lassen sich rückwirkend rekonstruieren (Issue #199), ein „war da, nichts
-- da" nicht — das entsteht nur, wenn es jemand in dem Moment einträgt.
--
-- Ein Leergang ist ein Fund ohne Fund und bleibt deshalb in `finds`: So
-- erbt er die komplette RLS (finds_author_all, finds_owner_select,
-- finds_friend_select), die Autor-Kaskade und die Buddy-Freigabe aus
-- Patch 014. Ein eigener Tisch müsste all das nachbauen UND dauerhaft
-- synchron halten.
--
-- Er trägt bewusst WEDER Art NOCH Anzahl: Die Aussage gilt dem Ort, nicht
-- einer Art („keine Steinpilze" wäre eine andere, viel schwächere Aussage
-- — man sucht im Wald nicht sortenrein). Der Check-Constraint hält das
-- fest, damit die Bedeutung nicht über die Jahre verwässert.
--
-- KEIN Bump von minimum_supported_version: Die Spalte ist additiv, alte
-- Clients ignorieren sie im finds(*)-Embed und füllen sie beim Insert per
-- Default. Ein alter Client zeigt einen Leergang als „Fund" und zählt ihn
-- in der Statistik mit — das trifft nur, wer parallel eine alte
-- Installation benutzt, und der Update-Banner räumt es von selbst ab.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- "Schema Check").

alter table public.finds
  add column blank boolean not null default false;

-- Die Bedeutung, als Constraint. `not blank or …` statt einer Implikation
-- geschrieben, weil Postgres kein `implies` kennt — gemeint ist: WENN
-- blank, DANN weder Art noch Anzahl.
alter table public.finds
  add constraint finds_blank_leer
  check (not blank or (species is null and count is null));

-- PostgREST-Schema-Cache sofort neu laden (neue Spalte), damit der direkt
-- anschließende Schema-Check nicht gegen die alte Oberfläche prüft.
notify pgrst, 'reload schema';
