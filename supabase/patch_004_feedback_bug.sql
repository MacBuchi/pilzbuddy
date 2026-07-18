-- Patch 004: Feedback-Kategorie "bug" zulassen.
-- Im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.
alter table public.feedback drop constraint feedback_type_check;
alter table public.feedback add constraint feedback_type_check check (type in ('feature', 'species', 'bug'));
