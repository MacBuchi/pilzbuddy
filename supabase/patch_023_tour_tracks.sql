-- Patch 023: Die Spur einer Pilztour wird mit Buddys teilbar (#340,
-- Stufe 2 — zweite Hälfte des Wunsches aus #338).
--
-- > Wenn man mit mehreren PilzBuddies unterwegs ist und der Standort
-- > geteilt ist, kann auch der Track der PilzBuddies, sofern sie die
-- > Pilztour starten, dargestellt werden.
--
-- DIESER PATCH BRICHT EINE ZUSAGE, UND ZWAR ABSICHTLICH. Seit Stufe 1
-- (1.102.0) gilt: die Spur verlässt das Gerät nie. Das steht nicht nur
-- im Code, sondern in `docs/play-console.md` (Data Safety und
-- „Prominent Disclosure"), in `docs/datenschutz-nachweise.md` als
-- belegte Behauptung, und `tours/` liegt in beiden Backup-Ausschlüssen.
-- Alle vier Stellen ändern sich im selben PR wie dieser Patch — eine
-- Tabelle, die Bewegungsdaten aufnimmt, ohne dass die Erklärung es
-- sagt, wäre genau der Fall, gegen den `test/privacy_policy_test.dart`
-- da ist.
--
-- EINE ZEILE JE NUTZER, AN ORT UND STELLE ERSETZT — wie
-- `live_locations` (Patch 007) und aus einem schärferen Grund: Eine
-- Zeile je Messpunkt wären bei 15 s Takt rund 720 Zeilen pro Person
-- und Drei-Stunden-Tour. Das wäre die erste Tabelle der App, deren
-- Größe mit der VERBRACHTEN ZEIT wächst statt mit den Funden — auf
-- einem Free-Plan mit 500 MB. Die gedünnte Spur (höchstens
-- `kTourTrackMaxDots` = 400 Punkte) sind rund 10 KB in `points`.
--
-- `points` als jsonb und nicht als eigene Tabelle: Gelesen wird die
-- Spur immer GANZ (man zeichnet sie), nie punktweise abgefragt. Eine
-- Kindtabelle bräuchte eigene Policies, einen Index und einen Weg,
-- alte Punkte loszuwerden — für eine Liste, die als Ganzes ersetzt
-- wird.
--
-- `expires_at` IST DIE ZUSTIMMUNG, und sie wird GEERBT statt neu
-- eingeholt: Die Spur ist genau so lange sichtbar wie die laufende
-- Standort-Freigabe, aus der sie ihr Ende bekommt. Eine zweite
-- Zustimmung neben „ich teile meinen Standort für 2 h" wäre eine
-- zweite Frage auf dieselbe Entscheidung — und zwei Fristen, die
-- auseinanderlaufen können. Wer nicht teilt, lädt nichts hoch; für
-- ihn gilt Stufe 1 unverändert weiter.
--
-- KEIN Bump von minimum_supported_version: rein additiv. Ein älterer
-- Client kennt die Tabelle nicht, lädt nichts hoch und zeigt nichts an
-- — er verhält sich wie vor diesem Patch.
create table public.tour_tracks (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  started_at timestamptz not null,
  -- [[lat, lng, "iso8601"], …] — vor dem Hochladen gedünnt.
  points jsonb not null,
  updated_at timestamptz not null default now(),
  -- Geerbt aus der Standort-Freigabe, siehe oben.
  expires_at timestamptz not null
);

-- Die Freundes-Select-Policy filtert über expires_at — wie bei
-- live_locations, und derselbe Index aus demselben Grund.
create index tour_tracks_expires_idx on public.tour_tracks (expires_at);

alter table public.tour_tracks enable row level security;

-- Spiegel von ll_owner_all / ll_friend_select (Patch 007). Bewusst
-- Zeichen für Zeichen dieselbe Form: Zwei Tabellen, die dasselbe
-- Sichtbarkeitsversprechen geben, sollen es nicht auf zwei Arten
-- formulieren — sonst driftet beim nächsten Anfassen eine davon.
create policy tt_owner_all on public.tour_tracks for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy tt_friend_select on public.tour_tracks for select
  using (user_id <> auth.uid()
     and app_internal.are_friends(user_id, auth.uid())
     and expires_at > now());
