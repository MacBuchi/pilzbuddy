-- Patch 029: Funde an iNaturalist melden (#553, Stufe 1).
--
-- > Man sollte im Fund sehen, ob er gemeldet / akzeptiert wurde, und
-- > melden sollte auch im Nachhinein funktionieren. (Betreiber)
--
-- EINE ZEILE JE FUND UND PLATTFORM. Der Primärschlüssel ist die
-- Idempotenz: Ein zweiter Versuch findet die Zeile von vorhin und
-- sendet mit DERSELBEN `remote_uuid` — iNaturalist übernimmt sie als
-- Kennung der Beobachtung, eine Wiederholung legt also keine zweite
-- an. Deshalb entsteht die Zeile, BEVOR gesendet wird.
--
-- DER ZUGANG STEHT HIER NICHT. Er liegt im Keystore des Geräts; die
-- Datenbank kennt nur, was gemeldet wurde, nicht womit.
--
-- NUR DER EIGENE FUND, NUR FÜR MICH. Melden darf nur, wer den Fund
-- eingetragen hat (sonst meldete ein Buddy unter eigenem Namen, was ein
-- anderer gesehen hat — genau das, was iNaturalist verbietet). Lesen
-- ebenso: Ob jemand meldet, ist seine Sache. Wer es Buddys zeigen will,
-- braucht eine eigene Entscheidung und eine eigene Policy.
--
-- `user_id` VERWEIST AUF auth.users, NICHT AUF profiles — dieselbe
-- Vorsicht wie bei den Kudos (Patch 028): Zwei Fremdschlüssel auf finds
-- und profiles machten die Tabelle für PostgREST zur Verbindungstabelle
-- zwischen beiden, und die profiles-Embeds der Spot-Abfrage würden
-- mehrdeutig (PGRST201).
--
-- DIE STATUSLISTE IST SCHON VOLLSTÄNDIG, obwohl Stufe 1 nur die ersten
-- beiden schreibt: Ein Check-Constraint lässt sich nur per neuem Patch
-- erweitern, und Stufe 2 (Status am Fund) liest die übrigen von
-- iNaturalist zurück.
--   sending   Zeile steht, Beobachtung oder Fotos noch nicht bestätigt
--   reported  angelegt, Fotos hängen dran
--   needs_id  bei iNaturalist „Needs ID" — wartet auf Bestätigung
--   research  „Research Grade" — geht mit freier Lizenz an GBIF
--   casual    „Casual" — kommt nicht bei GBIF an (z. B. ohne Foto)
--   withdrawn bei iNaturalist gelöscht
-- `gbif_id` trägt die Kennung, sobald GBIF die Beobachtung führt.
--
-- KEIN Bump von minimum_supported_version: rein additiv.
create table public.find_reports (
  find_id uuid not null references public.finds(id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  platform text not null default 'inat' check (platform in ('inat')),
  remote_uuid uuid not null,
  remote_id bigint,
  status text not null default 'sending' check (status in
    ('sending', 'reported', 'needs_id', 'research', 'casual', 'withdrawn')),
  gbif_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (find_id, platform)
);
-- Der Cascade beim Löschen eines Kontos.
create index find_reports_user_idx on public.find_reports (user_id);

alter table public.find_reports enable row level security;
grant select, insert, update, delete on public.find_reports to authenticated;

create policy fr_select on public.find_reports for select
  using (user_id = auth.uid());
create policy fr_insert on public.find_reports for insert
  with check (user_id = auth.uid()
    and exists (select 1 from public.finds f
                where f.id = find_id and f.author_id = auth.uid()));
-- Ändern: nur die eigene Zeile, und sie bleibt beim eigenen Fund — der
-- `with check` verhindert, dass eine Zeile auf einen fremden Fund
-- umgehängt wird.
create policy fr_update on public.find_reports for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
    and exists (select 1 from public.finds f
                where f.id = find_id and f.author_id = auth.uid()));
create policy fr_delete on public.find_reports for delete
  using (user_id = auth.uid());
