-- Patch 012: Mindestversion, um veraltete Clients auszusperren (Issue #80).
--
-- Der Schema Check garantiert nur, dass die AKTUELLE App zum Live-Schema
-- passt. Benennt eine Migration etwas um, das ein älterer Client noch
-- abfragt, bricht dieser Client still im Feld — der PostgREST-Fehler landet
-- in der generischen „Internet verfügbar?"-SnackBar. Der Update-Banner ist
-- nur ein Hinweis; einmal weggetippt bleibt der Nutzer beliebig lange auf
-- der alten Version.
--
-- Ab hier hat jede Breaking-Migration ein Verfahren: minimum_supported_version
-- im selben PR hochsetzen (per Patch, NICHT von Hand im Dashboard — nur so
-- läuft der Aussperr-Schutz in tool/schema_check.sh darüber).
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- "Schema Check").

create table if not exists public.app_config (
  -- Einzeilige Tabelle: der check lässt nur die Zeile mit id = true zu.
  id boolean primary key default true check (id),
  minimum_supported_version text not null default '0.0.0'
    check (minimum_supported_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  updated_at timestamptz not null default now()
);

-- Die Zeile muss existieren, sonst liest die App null und sperrt nie.
insert into public.app_config (id) values (true) on conflict (id) do nothing;

alter table public.app_config enable row level security;

-- Lesen darf jeder, auch anon: die Prüfung läuft beim Start und damit VOR
-- der Anmeldung — ein zu alter Client könnte die Sperre sonst gar nicht
-- anzeigen. Der Inhalt ist eine Versionsnummer, kein Geheimnis.
drop policy if exists app_config_read on public.app_config;
create policy app_config_read on public.app_config for select using (true);

-- Nur lesen: geändert wird der Wert über einen Patch, nicht über die API.
grant select on public.app_config to anon, authenticated;
