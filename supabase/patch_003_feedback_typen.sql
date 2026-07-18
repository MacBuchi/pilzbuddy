-- Patch 003: Feedback-Typen für den Automatisierungs-Bot.
-- Im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.
alter table public.feedback add column type text not null default 'feature' check (type in ('feature', 'species'));
alter table public.feedback add column species_name text;
alter table public.feedback add column processed_at timestamptz;
