-- Patch 030: Nachrichten zwischen Buddys (#564, Stufe 1 — ohne Push).
--
-- > Eine ganz einfache Nachrichtenfunktion von Buddy zu Buddy. Ohne
-- > bestätigte Freundschaft auf 3 Nachrichten je Seite begrenzt, 30 Tage
-- > Aufbewahrung. Man muss ja wissen, wen man reinnimmt. (Betreiber)
--
-- WER MIT WEM. Nur wer eine Zeile in `friendships` teilt: angenommen ⇒
-- unbegrenzt; offen (in welcher Richtung auch immer) ⇒ höchstens DREI
-- eigene Nachrichten an diese Person. Ohne Anfrage keine Nachricht —
-- sonst wäre die Namenssuche ein Weg, jedem zu schreiben. Das Limit steht
-- HIER und nicht in der App: Eine Grenze, die nur die Oberfläche zieht,
-- umgeht jeder mit einem eigenen Client.
--
-- ENDE DES KONTAKTS ENDET DEN VERLAUF. Wer ablehnt, zurückzieht oder
-- einen Buddy entfernt, löscht die Freundschaftszeile — und ein Trigger
-- nimmt die Nachrichten beider Seiten mit. Er läuft als Definer: Die
-- delete-Policy erlaubt jedem nur die EIGENEN Nachrichten.
--
-- 30 TAGE, UND ZWAR ERZWUNGEN. `expires_at` hat einen Default, einen
-- Check gegen `created_at` — und vor allem SPALTEN-Grants: Ein Client
-- darf beim Anlegen nur Empfänger und Text setzen, beim Ändern nur
-- `read_at`. Ohne die Spalten-Grants könnte er `created_at` in die
-- Zukunft legen und den Check damit aushebeln. Abgelaufenes sieht
-- niemand mehr (select-Policy), und ein Cron-Job räumt es täglich.
--
-- NICHT ENDE-ZU-ENDE-VERSCHLÜSSELT (Betreiber-Entscheidung, #564): Wie
-- Spots und Funde geschützt durch RLS, für den Betreiber technisch
-- lesbar. Die Datenschutzerklärung sagt das ausdrücklich.
--
-- Beide Personen-Spalten verweisen auf auth.users, nicht auf profiles:
-- dieselbe Vorsicht wie bei Kudos und Meldungen (Patch 028/029) — die
-- Namen kennt die App ohnehin aus der Buddy-Liste.
--
-- KEIN Bump von minimum_supported_version: rein additiv.
create table public.buddy_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days',
  read_at timestamptz,
  check (sender_id <> recipient_id),
  check (expires_at <= created_at + interval '30 days')
);
-- Ein Verlauf ist ein Paar; gezählt wird je Absender und Empfänger.
create index buddy_messages_pair_idx
  on public.buddy_messages (sender_id, recipient_id, created_at);
create index buddy_messages_recipient_idx
  on public.buddy_messages (recipient_id);
create index buddy_messages_expires_idx
  on public.buddy_messages (expires_at);

-- Darf ich [other] schreiben? Angenommen ⇒ ja; offen ⇒ solange ich ihr
-- weniger als drei Nachrichten geschickt habe; sonst nein.
-- Definer wie `are_friends`: Die Policy wertet mit den Rechten der
-- anfragenden Rolle aus, und die Zählung soll nicht an einer
-- select-Policy hängen, die sich später ändert.
create or replace function app_internal.may_message(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when exists (
      select 1 from friendships f
      where f.status = 'accepted'
        and ((f.requester_id = auth.uid() and f.addressee_id = other)
          or (f.requester_id = other and f.addressee_id = auth.uid())))
      then true
    when exists (
      select 1 from friendships f
      where f.status = 'pending'
        and ((f.requester_id = auth.uid() and f.addressee_id = other)
          or (f.requester_id = other and f.addressee_id = auth.uid())))
      then (select count(*) from buddy_messages m
            where m.sender_id = auth.uid() and m.recipient_id = other) < 3
    else false
  end;
$$;

alter table public.buddy_messages enable row level security;
-- ERST alles weg: Das Projekt gibt neuen Tabellen per Voreinstellung
-- ALLE Rechte (`auto_expose_new_tables`, Legacy bis 2026-10-30). Ein
-- Tabellen-INSERT schlüge jeden Spalten-Grant — die Zeitsperre oben
-- wäre dann nur Deko.
revoke all on public.buddy_messages from anon, authenticated;
grant select, delete on public.buddy_messages to authenticated;
grant insert (recipient_id, body) on public.buddy_messages to authenticated;
grant update (read_at) on public.buddy_messages to authenticated;

create policy bm_select on public.buddy_messages for select
  using ((sender_id = auth.uid() or recipient_id = auth.uid())
     and expires_at > now());
create policy bm_insert on public.buddy_messages for insert
  with check (sender_id = auth.uid()
    and app_internal.may_message(recipient_id));
-- Gelesen markieren: nur, was an MICH ging.
create policy bm_read on public.buddy_messages for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());
-- Zurücknehmen: nur die eigenen.
create policy bm_delete on public.buddy_messages for delete
  using (sender_id = auth.uid());

create or replace function app_internal.messages_on_unfriend()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from buddy_messages m
  where (m.sender_id = old.requester_id and m.recipient_id = old.addressee_id)
     or (m.sender_id = old.addressee_id and m.recipient_id = old.requester_id);
  return old;
end;
$$;
revoke all on function app_internal.messages_on_unfriend() from public, anon, authenticated;
create trigger friendships_delete_messages
  after delete on public.friendships
  for each row execute function app_internal.messages_on_unfriend();

-- Täglich um 03:17 UTC — die select-Policy blendet Abgelaufenes schon
-- vorher aus, der Job hält nur die Tabelle klein.
select cron.schedule('buddy-messages-sweep', '17 3 * * *',
                     $cron$delete from public.buddy_messages where expires_at < now()$cron$);
