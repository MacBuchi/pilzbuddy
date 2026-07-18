-- Patch 006: Indexe auf den friendships-Fremdschlüsseln — jede
-- RLS-Policy und die are_friends-Funktion filtern über diese Spalten.
-- Erster Patch, der automatisch eingespielt wird (tool/db_migrate.sh
-- über den Pflicht-Check "Schema Check" bzw. den Release-Workflow).
create index if not exists friendships_requester_idx
  on public.friendships (requester_id);
create index if not exists friendships_addressee_idx
  on public.friendships (addressee_id);
