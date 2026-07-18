-- Patch 002: Feature-Wünsche / Feedback aus der App.
-- Im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.
-- Einträge liest der Betreiber im Table Editor (Tabelle "feedback").

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check (char_length(message) between 3 and 2000),
  created_at timestamptz not null default now()
);

alter table public.feedback enable row level security;

-- Jeder darf eigene Wünsche einreichen und die eigenen nachlesen;
-- fremde Einträge sieht nur der Betreiber (Dashboard/service_role).
create policy feedback_insert on public.feedback for insert
  with check (user_id = auth.uid());
create policy feedback_select_own on public.feedback for select
  using (user_id = auth.uid());
