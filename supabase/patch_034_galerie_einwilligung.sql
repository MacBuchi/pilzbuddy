-- Patch 034: Einwilligung, Feedback-Bilder in der Artgalerie zu zeigen
-- (#569 Teil b).
--
-- > Einwilligung beim Melden. Nennung von Nutzernamen in der Galerie
-- > (wie bei mir). — CC BY-SA 4.0 passt. (Betreiber, 2026-09-23)
--
-- WARUM ES DAS BRAUCHT: Ein Bild am Feedback ist bisher ausdrücklich
-- NICHT zur Veröffentlichung gedacht (Patch 027, Dialog-Text). Ohne
-- Einwilligung und Lizenz darf der Betreiber es nicht in die App
-- übernehmen — auch nicht von Hand. Diese Spalte ist die Einwilligung:
-- „selbst aufgenommen, darf unter CC BY-SA 4.0 mit meinem Benutzernamen
-- als Urheber in der Artgalerie stehen".
--
-- NUR DIE EINWILLIGUNG, KEINE ÜBERNAHME. Ob ein Bild wirklich in die
-- Galerie kommt, entscheidet weiter ein Mensch, der es angesehen hat
-- (`species_photos.dart`, `pilz-fotos`-Skill). Den Namen zum Zeitpunkt
-- der Meldung hält das Issue fest, das der Bot schreibt; der Zeitpunkt
-- ist `created_at`.
--
-- Ein Ja ohne Bilder ergibt keinen Sinn — der Check sagt das.
--
-- KEIN Bump von minimum_supported_version: Spalte mit Default, ältere
-- Clients schicken sie nicht.
alter table public.feedback
  add column if not exists photo_consent boolean not null default false;
alter table public.feedback
  add constraint feedback_photo_consent_needs_photos
  check (not photo_consent or photo_paths is not null);
