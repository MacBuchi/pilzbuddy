-- Patch 033: Bis zu drei Bilder am Feedback (#569).
--
-- > Mir ist aufgefallen, dass nur ein Foto anhängbar ist, das sollten
-- > wir auf drei Fotos erhöhen. (Betreiber)
--
-- EINE LISTE IN DER ZEILE, KEINE ZWEITE TABELLE. Die App darf ihre
-- Feedback-Zeile nach dem Einfügen nicht zurücklesen (nur die eigenen,
-- und der Insert fragt nicht nach); eine Kindtabelle bräuchte deshalb
-- eine vorab erzeugte id UND eine Definer-Funktion für ihre Policy.
-- Die Pfade als Array tragen dieselbe Aussage mit einer Spalte.
--
-- `photo_path` BLEIBT: Die Clients 1.186.0–1.195.x schreiben weiter
-- dorthin, und der Bot liest beide. Neue Clients schreiben nur
-- `photo_paths`. Entfernt werden kann die alte Spalte erst, wenn keine
-- dieser Versionen mehr im Feld ist (erweitern → ausliefern → entfernen).
--
-- DIE GRENZEN ZIEHT DIE DATENBANK: höchstens drei Pfade, jeder im Ordner
-- des Melders — dieselbe Bindung wie `feedback_photo_owner` und die
-- Upload-Policy. Ein CHECK kann ein Array nicht selbst durchlaufen
-- (keine Unterabfragen), deshalb die kleine Prüffunktion. Sie liegt in
-- `app_internal` (kein API-Endpunkt) und behält EXECUTE für die Rollen:
-- Der CHECK läuft mit den Rechten dessen, der einfügt.
--
-- KEIN Bump von minimum_supported_version: nullable Spalte, ältere
-- Clients schicken sie nicht.
create or replace function app_internal.feedback_photos_ok(paths text[], owner uuid)
returns boolean language sql immutable as $$
  select paths is null
      or (cardinality(paths) between 1 and 3
          and not exists (select 1 from unnest(paths) p
                          where p is null or p not like (owner::text || '/%')));
$$;

alter table public.feedback
  add column if not exists photo_paths text[];
alter table public.feedback
  add constraint feedback_photos_owner
  check (app_internal.feedback_photos_ok(photo_paths, user_id));
