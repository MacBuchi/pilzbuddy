-- Die App-Version zu jeder Feldmeldung (#358).
--
-- `error_reports` trägt sie seit Patch 009, die von Hand geschriebenen
-- Meldungen nicht — ausgerechnet dort, wo die Triage sie am dringendsten
-- braucht. Bei #358 war deshalb nicht entscheidbar, ob die Meldung ein
-- Duplikat einer schon behobenen war oder ein neuer Fehler im frischen
-- Stand; die Frage musste beim Melder zurückgestellt werden.
--
-- Nullable und ohne Vorgabe: Bestandszeilen haben die Angabe nicht, und
-- eine erfundene wäre schlimmer als keine. Ältere Clients schicken sie
-- ebenfalls nicht — deshalb ist das eine ERWEITERNDE Migration, die
-- keine Mindestversion anhebt.
alter table public.feedback
  add column if not exists app_version text;
