-- Patch 010: RLS für public.applied_patches (Supabase-Advisor,
-- Meldung „rls_disabled_in_public" vom 20.07.2026).
--
-- Die Tabelle ist reines Migrations-Tracking und gehört tool/db_migrate.sh,
-- das sie beim Bootstrap selbst anlegt — als einzige Tabelle außerhalb von
-- schema.sql/Patches, und genau deshalb rutschte sie ohne RLS durch. Gelesen
-- und beschrieben wird sie ausschließlich über die direkte DB-Verbindung
-- (Session-Pooler, Rolle postgres), die weder RLS noch Grants braucht.
--
-- Über die REST-API war sie bislang mit dem Publishable Key voll les- UND
-- schreibbar. Das Leck ist nicht die Patch-Historie (die steht öffentlich im
-- Repo), sondern die Schreibbarkeit: gelöschte Zeilen ⇒ Patches laufen
-- erneut, untergeschobene Zeilen ⇒ Patches werden übersprungen.
--
-- RLS ohne Policies = niemand kommt über die API dran; das Revoke nimmt die
-- Tabelle zusätzlich ganz aus der API-Oberfläche (Standard-Grants von
-- Supabase). Der Bootstrap in tool/db_migrate.sh macht seit diesem Patch
-- dasselbe, damit Frischinstallationen nie wieder offen starten.
alter table public.applied_patches enable row level security;
revoke all on table public.applied_patches from anon, authenticated;
