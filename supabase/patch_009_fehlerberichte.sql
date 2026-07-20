-- Patch 009: Fehlerberichte aus dem Feld.
--
-- Android Vitals in der Play Console zeigt Abstürze und ANRs von selbst —
-- aber nur harte Abstürze, nur auf Android und nur bei Play-Installationen.
-- Die eigentliche Blindstelle sind die GEFANGENEN Fehler: `logError` zeigt
-- eine freundliche SnackBar, die App läuft weiter, und niemand erfährt je,
-- dass ein Query gescheitert ist. Genau die landen hier.
--
-- Bewusst in Supabase statt bei einem Crash-Dienst: kein zusätzlicher
-- Auftragsverarbeiter, kein neuer Eintrag im Data-Safety-Formular, die Daten
-- liegen dort, wo die App ohnehin ihre Daten hat.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- "Schema Check").

create table if not exists public.error_reports (
  id uuid primary key default gen_random_uuid(),
  -- Nullable: die wertvollsten Fehler passieren VOR der Anmeldung
  -- (Login, Registrierung). Bei gelöschtem Konto verschwindet der Bericht
  -- mit — die Zusage aus der Konto-Löschung soll ohne Ausnahme gelten.
  user_id uuid references public.profiles(id) on delete cascade,
  -- Aufrufkontext aus logError, z. B. "Spot speichern".
  context text not null check (char_length(context) between 1 and 100),
  -- Laufzeittyp des Fehlers, z. B. "PostgrestException".
  error_type text not null check (char_length(error_type) <= 100),
  -- Fehlertext, in der App gekürzt. Längenlimit auch hier, damit die
  -- Tabelle nicht als Ablage missbraucht werden kann.
  message text check (char_length(message) <= 1000),
  stack text check (char_length(stack) <= 4000),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);
create index if not exists error_reports_created_idx
  on public.error_reports (created_at desc);

alter table public.error_reports enable row level security;

-- Schreiben darf jeder — auch anon, sonst fehlen genau die Fehler aus
-- Login und Registrierung. Eine fremde user_id lässt sich dabei nicht
-- unterschieben: entweder null oder die eigene.
drop policy if exists er_insert on public.error_reports;
create policy er_insert on public.error_reports for insert
  with check (user_id is null or user_id = auth.uid());

-- Lesen darf NIEMAND über die API — es gibt bewusst keine select-Policy.
-- Auswertung läuft über das Dashboard bzw. den service_role-Key.
grant insert on public.error_reports to anon, authenticated;
