-- Patch 036: fester search_path für drei Hilfsfunktionen.
--
-- Security Advisor, 2026-09-24: „Function Search Path Mutable" für
-- app_internal.feedback_photos_ok (Patch 033), push_due_at und
-- push_friends (Patch 018). Ohne festen Suchpfad löst eine Funktion
-- Namen über den search_path der AUFRUFENDEN Sitzung auf — wer dort ein
-- gleichnamiges Objekt vorschieben kann, lenkt die Funktion um. Alle drei
-- liegen in `app_internal` und sind über die API nicht erreichbar; das
-- Risiko ist klein, die Korrektur eine Zeile je Funktion.
--
-- **Leer, nicht `public`.** Die drei brauchen nichts aus dem Suchpfad:
-- `now()`, `unnest`, `cardinality` und `interval` liegen in pg_catalog,
-- das Postgres immer durchsucht, und `push_friends` schreibt
-- `public.friendships` ausgeschrieben. Ein leerer Pfad ist die engste
-- Wahl — und bricht laut, wenn später jemand einen unqualifizierten Namen
-- hineinschreibt, statt still das Falsche zu finden.
--
-- Nur Eigenschaften der Funktionen: kein neues Recht, kein Bump von
-- minimum_supported_version.
alter function app_internal.feedback_photos_ok(text[], uuid) set search_path = '';
alter function app_internal.push_due_at(timestamptz) set search_path = '';
alter function app_internal.push_friends(uuid) set search_path = '';
