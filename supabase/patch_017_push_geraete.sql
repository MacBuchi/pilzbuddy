-- Patch 017: Wohin eine Push-Benachrichtigung geht (Issue #277).
--
-- Eine Zeile je Gerät. Der Primärschlüssel ist der TOKEN, nicht
-- (user_id, token): FCM-Token sind global eindeutig, eine Kollision
-- zwischen Konten ist konstruktiv unmöglich. Und ein Token gehört zu
-- genau EINEM Konto — meldet sich am selben Gerät jemand anders an, muss
-- die alte Zeile weichen statt danebenzustehen, sonst bekäme der
-- Vorbesitzer weiter Meldungen über fremde Funde. Genau das erledigt der
-- `on conflict (token) do update` der App.
--
-- Was hier bewusst NICHT steht: wofür jemand Meldungen will. Der
-- Opt-in-Schalter ist eine Geräte-Einstellung und bleibt in den lokalen
-- Prefs — eine Zeile hier IST die Zustimmung, ihr Fehlen der Widerruf.
-- Eine zusätzliche Spalte „aktiv" wäre eine zweite Wahrheit darüber.
--
-- KEIN Bump von minimum_supported_version: Es wird nichts entfernt oder
-- umbenannt. Ältere Clients kennen die Tabelle schlicht nicht und
-- bekommen keine Benachrichtigungen.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- „Schema Check").

create table public.push_devices (
  token text primary key,
  -- Der Default macht das Anlegen zu einem Einzeiler und verhindert
  -- zugleich, dass jemand eine Zeile auf ein fremdes Konto schreibt —
  -- die Policy unten prüft es trotzdem, weil ein Default überschreibbar
  -- ist. on delete cascade wie überall: Konto-Löschung räumt die Geräte
  -- mit ab (public.delete_own_account, Patch 008).
  user_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  -- Web und Android brauchen beim Versand verschiedene Nutzlasten; ohne
  -- die Angabe müsste der Versender raten.
  platform text not null check (platform in ('android', 'web')),
  created_at timestamptz not null default now(),
  -- Jede Registrierung schiebt den Wert vor. FCM-Token verfallen still;
  -- eine Zeile, die seit Monaten nicht mehr angefasst wurde, ist mit
  -- hoher Wahrscheinlichkeit tot und kann später aufgeräumt werden.
  last_seen_at timestamptz not null default now()
);

create index push_devices_user_idx on public.push_devices (user_id);

alter table public.push_devices enable row level security;

-- Nur die eigenen Geräte, und zwar in beide Richtungen: `using` fürs
-- Lesen und Löschen, `with check` fürs Anlegen und Ändern. Ohne das
-- `with check` könnte jemand ein Token auf ein fremdes Konto schreiben
-- und würde dessen Meldungen mitbekommen.
create policy push_devices_own_all on public.push_devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Der Versender liest mit service_role und umgeht RLS — deshalb gibt es
-- hier bewusst KEINE Policy für ihn. Eine solche Policy wäre eine
-- Einladung, den Weg später über einen schwächeren Schlüssel zu gehen.

-- PostgREST-Schema-Cache sofort neu laden, damit der direkt
-- anschließende Schema-Check die neue Tabelle sieht.
notify pgrst, 'reload schema';
