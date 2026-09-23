-- Patch 028: Kudos für Fundfotos (#532, Stufe 4).
--
-- > Ein Pilz je Buddy und Foto — keine Skala.
--
-- EIN ZEICHEN, KEINE WERTUNG. Eine Skala von 1 bis 5 wäre in einer
-- Runde von zwölf eine Botschaft, die niemand senden wollte („2 Pilze");
-- und weil das Foto nach 14 Tagen weg ist, summiert sich nie etwas zu
-- einer Rangliste. Deshalb je (Foto, Nutzer) höchstens eine Zeile, und
-- zurücknehmen heißt löschen.
--
-- DIE SICHTBARKEIT WIRD GEERBT, wie beim Foto selbst vom Fund: Die
-- select-Policy fragt nur, ob das FOTO für mich lesbar ist — die
-- find_photos-Policies greifen im Subselect. Wer das Foto sieht, sieht
-- seine Kudos; wer nicht, nicht. Keine zweite Freigabe, die driften kann.
--
-- ABGERÄUMT WIRD PER CASCADE. Der Bot löscht abgelaufene find_photos-
-- Zeilen (feedback_bot.py, `sweep_find_photos`), und die Kudos gehen
-- mit. Eine eigene Frist gibt es deshalb nicht.
--
-- `user_id` VERWEIST AUF auth.users, NICHT AUF profiles — und das ist
-- Absicht. Mit Fremdschlüsseln auf find_photos UND profiles hielte
-- PostgREST diese Tabelle für eine Verbindungstabelle zwischen beiden,
-- und das Embed `find_photos?select=…,profiles(username,avatar)` der
-- ausgelieferten App würde mehrdeutig (PGRST201) — dieselbe Falle wie
-- beim push_outbox (Patch 018). Die Namen löst die App über die eigene
-- Buddy-Liste auf; mehr gäbe die profiles-Policy ohnehin nicht her.
-- Das Löschen eines Kontos räumt trotzdem mit ab: auth.users ist die
-- Wurzel, an der auch profiles hängt.
--
-- KEIN Bump von minimum_supported_version: rein additiv.
create table public.find_photo_kudos (
  photo_id uuid not null references public.find_photos(id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (photo_id, user_id)
);
-- „Welche Kudos habe ich gegeben" braucht niemand; der Index hilft dem
-- Cascade beim Löschen eines Kontos.
create index find_photo_kudos_user_idx on public.find_photo_kudos (user_id);

alter table public.find_photo_kudos enable row level security;
grant select, insert, delete on public.find_photo_kudos to authenticated;

-- Lesen: alle Kudos an einem Foto, das ich sehen darf.
create policy fpk_select on public.find_photo_kudos for select
  using (exists (select 1 from public.find_photos p where p.id = photo_id));
-- Geben: nur als ich selbst, nur an ein Foto, das ich sehe, und nie an
-- mein eigenes — ein Pilz für sich selbst ist Rauschen.
create policy fpk_insert on public.find_photo_kudos for insert
  with check (user_id = auth.uid()
    and exists (select 1 from public.find_photos p
                where p.id = photo_id and p.user_id <> auth.uid()));
-- Zurücknehmen: nur die eigenen.
create policy fpk_delete on public.find_photo_kudos for delete
  using (user_id = auth.uid());
