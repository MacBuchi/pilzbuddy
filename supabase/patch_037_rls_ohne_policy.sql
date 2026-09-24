-- Patch 037: ausdrückliche Sperr-Policies für drei Tabellen ohne Policy.
--
-- Security Advisor, 2026-09-24: „RLS Enabled No Policy" (INFO) für
-- public.applied_patches, app_internal.push_outbox und
-- app_internal.push_messages. Gemeint war das von Anfang an so — kein
-- Client soll dort lesen oder schreiben; RLS ohne Policy verweigert
-- ohnehin alles. Bisher hieß die Regel, den Fund im Dashboard zu
-- dismissen, aber **das Dashboard kann das nicht** (Betreiber,
-- 2026-09-24). Ein Fund, der für immer stehen bleibt, übertönt die
-- echten; deshalb steht die Absicht jetzt als Policy da.
--
-- **`using (false)` ändert am Zugriff nichts**: Für anon und
-- authenticated war schon alles verweigert, und wer die Tabellen
-- wirklich benutzt — tool/db_migrate.sh über die DB-URL, die
-- Definer-Trigger und push_flush —, läuft als Eigentümer und umgeht RLS.
-- Kein neues Recht, kein Bump von minimum_supported_version.
create policy applied_patches_no_client on public.applied_patches
  for all to anon, authenticated using (false) with check (false);
create policy push_outbox_no_client on app_internal.push_outbox
  for all to anon, authenticated using (false) with check (false);
create policy push_messages_no_client on app_internal.push_messages
  for all to anon, authenticated using (false) with check (false);
