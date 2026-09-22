-- Patch 027: Ein Bild am Feedback (#525).
--
-- > Eine Möglichkeit, Bilder über die Feedback-Funktion aus dem
-- > Pilzporträt heraus zu teilen wäre schön.
--
-- Die Text-Hälfte gab es schon (#520, „Hinweis zu dieser Art melden");
-- das hier ist die Bild-Hälfte, auf demselben Unterbau wie die
-- Fundfotos (Patch 026): Pipeline auf dem Gerät, Bucket beim Server,
-- Pfad in der Zeile.
--
-- STRENGER ALS `find-photos`, UND ZWAR IN EINER RICHTUNG: Der Text
-- einer Meldung wird öffentlich (GitHub-Issue) — das Bild NICHT. Es
-- gibt hier keine Select-Policy für Nutzer, auch nicht für den, der es
-- hochgeladen hat: Gelesen wird ausschließlich mit dem Service-Schlüssel
-- (Dashboard, Bot). Ein Screenshot zum Bug kann alles Mögliche zeigen,
-- was in einem öffentlichen Issue nichts verloren hat.
--
-- Die Frist steht nicht in der Zeile, sondern beim Bot: Objekte älter
-- als 90 Tage fliegen (`ERROR_REPORT_RETENTION_DAYS`, dieselbe Frist
-- wie die Fehlerberichte). Die Zeile bleibt — sie trägt dann einen Pfad
-- ins Leere, und das ist gewollt: Das Issue existiert, das Bild hat
-- seinen Dienst getan.
--
-- KEIN Bump von minimum_supported_version: nullable Spalte, ältere
-- Clients schicken sie nicht.
alter table public.feedback
  add column if not exists photo_path text;
-- Der Ordner ist der Melder — dieselbe Bindung wie in der Upload-Policy.
alter table public.feedback
  add constraint feedback_photo_owner
  check (photo_path is null or photo_path like (user_id::text || '/%'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback-photos', 'feedback-photos', false, 600000, array['image/jpeg'])
on conflict (id) do nothing;

-- Nur hineinlegen, nur in den eigenen Ordner. Kein select, kein delete:
-- siehe oben.
create policy feedback_photos_upload on storage.objects for insert
  to authenticated
  with check (bucket_id = 'feedback-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);
