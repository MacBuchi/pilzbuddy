-- Patch 026: Fundfotos für Buddys (#532, #525 folgt darauf).
--
-- > Ein besonders schönes Fundstück fotografieren, die Buddys bekommen
-- > es in einen Posteingang, der es ein, zwei Wochen behält.
--
-- DIE BYTES LIEGEN NICHT IN DIESER TABELLE. Sie gehen in den Bucket
-- `find-photos` (Supabase Storage, eigenes Kontingent — 1 GB auf dem
-- Free-Plan); hier steht je Foto eine Zeile mit Schlüssel, Fund und
-- Ablauf, rund 200 Byte. Tausend Fotos sind 200 KB in einer Datenbank
-- mit 500 MB. Der Speicher wächst also nicht mit den Bildern, und der
-- Bucket wächst nicht mit der Zeit: `expires_at` ist auf 14 Tage
-- begrenzt, der Feedback-Bot räumt alle zwei Stunden ab (Zeilen UND
-- Objekte, per Abgleich — ein Objekt ohne lebende Zeile fliegt).
--
-- DAS FOTO HÄNGT AM FUND, und die Sichtbarkeit wird GEERBT: Die
-- Freundes-Policy fragt nur, ob der Fund für den Betrachter lesbar
-- ist (`exists (select 1 from finds …)` — die drei finds-Policies aus
-- Patch 014 greifen im Subselect). Wer den Fund sehen darf, darf das
-- Foto sehen; wer nicht, nicht. Damit gibt es keine zweite
-- Freigabe-Bedingung, die neben der ersten driften könnte. Das ist
-- die Entscheidung des Betreibers vom 2026-09-22 („am Fund").
--
-- DIE FRIST GEHÖRT DER DATENBANK, NICHT DEM CLIENT. `expires_at`
-- bekommt seinen Wert per Default, und der Constraint verbietet, ihn
-- über 14 Tage hinauszuschieben — ein veränderter Client könnte sonst
-- ein Foto für Jahre ablegen, und „14 Tage" wäre nur noch eine Zeile
-- in der Erklärung.
--
-- DER SCHLÜSSEL BEGINNT MIT DEM NUTZER (`<user_id>/<id>`), und das ist
-- die Brücke zur Storage-Policy: Hochladen darf man nur in den eigenen
-- Ordner, und der Constraint hier sorgt dafür, dass die Zeile keinen
-- fremden Pfad behaupten kann.
--
-- KEIN Bump von minimum_supported_version: rein additiv.
create table public.find_photos (
  id uuid primary key default gen_random_uuid(),
  find_id uuid not null references public.finds(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- Pfad im Bucket ohne Endung; Bild unter `<key>.jpg`, Vorschau unter
  -- `<key>_s.jpg`.
  key text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  constraint find_photos_frist
    check (expires_at <= created_at + interval '14 days'),
  constraint find_photos_key_owner
    check (key like (user_id::text || '/%'))
);
create index find_photos_find_idx on public.find_photos (find_id);
-- Die Freundes-Policy filtert über expires_at, der Bot räumt darüber.
create index find_photos_expires_idx on public.find_photos (expires_at);

alter table public.find_photos enable row level security;
grant select, insert, delete on public.find_photos to authenticated;

-- Eigene Zeilen voll verwalten — anlegen nur an EIGENEN Funden. Am
-- Fund eines Buddys hängt man kein Foto auf, auch nicht am eigenen
-- Spot: Das Foto sagt „so sah MEIN Fund aus".
create policy fp_owner_all on public.find_photos for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
    and exists (select 1 from public.finds f
                where f.id = find_id and f.author_id = auth.uid()));
-- Fremde Zeilen: solange sie nicht abgelaufen sind und der FUND für
-- mich lesbar ist. Die Freigabe steht nicht hier, sondern in den
-- finds-Policies — das ist der Punkt.
create policy fp_friend_select on public.find_photos for select
  using (user_id <> auth.uid()
     and expires_at > now()
     and exists (select 1 from public.finds f where f.id = find_id));

-- ---------------------------------------------------------------------------
-- Der Bucket und seine Policies. Privat: Es gibt keine öffentliche URL,
-- jeder Abruf läuft mit Token durch die Policies unten.
-- ---------------------------------------------------------------------------
-- Größe und Typ als Riegel des Servers: Der Client schickt zwei JPEGs
-- (≤ 1024 px bei Qualität 80, gemessen ~150 KB); ein Client, der
-- etwas anderes schickt, ist nicht unserer.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('find-photos', 'find-photos', false, 600000, array['image/jpeg'])
on conflict (id) do nothing;

-- Hochladen: nur in den eigenen Ordner. `storage.foldername` zerlegt den
-- Pfad; das erste Glied ist die Nutzer-id.
create policy find_photos_upload on storage.objects for insert
  to authenticated
  with check (bucket_id = 'find-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);
-- Lesen: genau die Objekte, zu denen ich eine Zeile sehe. Die Zeile
-- sehe ich nach den Policies oben — eigene immer, fremde nur mit
-- lesbarem Fund und vor dem Ablauf. Ein Objekt ohne Zeile ist für
-- niemanden lesbar, auch nicht für den, der es hochgeladen hat.
create policy find_photos_read on storage.objects for select
  to authenticated
  using (bucket_id = 'find-photos'
    and exists (select 1 from public.find_photos p
                where name in (p.key || '.jpg', p.key || '_s.jpg')));
-- Löschen: eigener Ordner. Der Bot löscht mit dem Service-Schlüssel,
-- an den Policies vorbei.
create policy find_photos_remove on storage.objects for delete
  to authenticated
  using (bucket_id = 'find-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);
