-- PilzBuddy — Supabase-Schema
-- Komplett im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.

-- ============================================================
-- Tabellen
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar int not null default 0,               -- Index im Pilz-Avatar-Katalog
  share_spots_default boolean not null default true,   -- "Alle Spots mit Freunden teilen"
  share_details boolean not null default true,          -- auch Art/Anzahl/Datum teilen, nicht nur Standort
  created_at timestamptz not null default now()
);
-- Einmalig auch über Groß-/Kleinschreibung hinweg (Patch 013): Die
-- Freundessuche matcht per ilike auf das Namens-Präfix, „Marcus" und
-- „marcus" wären für Suchende dasselbe Konto.
create unique index profiles_username_lower_key
  on public.profiles (lower(username));

create table public.spots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text,
  lat double precision not null,
  lng double precision not null,
  sharing_excluded boolean not null default false,      -- einzelner Spot von der Freigabe ausgeschlossen
  created_at timestamptz not null default now(),
  -- Vom Gerät vergebene Kennung des Auftrags aus dem Ausgangskorb
  -- (Patch 016): macht die Wiedervorlage nach einem abgerissenen Insert
  -- idempotent. Leer bei allem, was nicht über den Korb kam.
  client_id uuid,
  -- Wann der Besitzer bestätigt hat, dass Fundstellen über 100 m vom
  -- Spot entfernt so gewollt sind (Patch 024, #475). Zeitpunkt statt
  -- Flag: Eine jüngere abweichende Fundstelle warnt wieder.
  offset_confirmed_at timestamptz,
  -- Erwartete Arten einer Vormerkung (Patch 025, #499): ein Spot ohne
  -- Funde, für den die Ampel trotzdem je Art sprechen soll. Keine Funde
  -- — eine Absicht, keine Sichtung.
  expected_species text[]
);
create index spots_owner_idx on public.spots (owner_id);
-- Zweimal derselbe Auftrag ⇒ 23505 statt Dublette. Partiell, weil die
-- Spalte für die große Mehrheit der Zeilen leer bleibt.
create unique index spots_owner_client_id_key
  on public.spots (owner_id, client_id)
  where client_id is not null;

create table public.finds (
  id uuid primary key default gen_random_uuid(),
  spot_id uuid not null references public.spots(id) on delete cascade,
  -- Jeder Fund gehört seinem Eintrager (Patch 014): Buddies dürfen an
  -- geteilten Spots Funde anlegen. Default auth.uid(), weil ältere
  -- Clients keine author_id senden; der Constraint-Name ist API-Vertrag
  -- (App und schema_check.sh embedden profiles!finds_author_id_fkey).
  author_id uuid not null default auth.uid()
    constraint finds_author_id_fkey
    references public.profiles(id) on delete cascade,
  species text,
  count int check (count is null or count > 0),
  found_on date not null default current_date,
  note text,
  created_at timestamptz not null default now(),
  -- „Nichts gefunden" (Patch 015): ein Fund ohne Fund — die Aussage gilt
  -- dem Ort, nicht einer Art. Weder Art noch Anzahl, sonst würde daraus
  -- über die Jahre ein schwächeres „keine Steinpilze".
  blank boolean not null default false,
  -- Siehe spots.client_id (Patch 016).
  client_id uuid,
  -- Die eigene Stelle dieses Fundes (Patch 022): Ohne sie lösen alle
  -- Funde eines Spots auf denselben Punkt auf. Nullable ist der
  -- Normalfall — der abends nachgetragene Fund hat keine.
  --
  -- `accuracy_m` ist der Streuradius des GPS-Fixes UND die
  -- Herkunftsangabe: leer bei gesetzter Koordinate heißt „auf der Karte
  -- gewählt" (ein Fadenkreuz hat keinen Messfehler).
  lat double precision,
  lng double precision,
  accuracy_m double precision,
  constraint finds_blank_leer
    check (not blank or (species is null and count is null)),
  -- Eine halbe Koordinate ist keine.
  constraint finds_position_paar
    check ((lat is null) = (lng is null)),
  constraint finds_position_bereich
    check (lat is null
           or (lat between -90 and 90 and lng between -180 and 180)),
  -- Keine Obergrenze: Ab wann ein Fix zu grob ist, entscheidet die
  -- Oberfläche und darf sich ändern.
  constraint finds_genauigkeit_sinn
    check (accuracy_m is null or (lat is not null and accuracy_m >= 0))
);
create index finds_spot_idx on public.finds (spot_id, found_on desc);
create index finds_author_idx on public.finds (author_id);
create unique index finds_author_client_id_key
  on public.finds (author_id, client_id)
  where client_id is not null;

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  check (requester_id <> addressee_id)
);
-- verhindert doppelte Paare in beiden Richtungen
create unique index friendships_pair_uidx on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
-- RLS-Policies und are_friends filtern über diese Spalten (Patch 006)
create index friendships_requester_idx on public.friendships (requester_id);
create index friendships_addressee_idx on public.friendships (addressee_id);

-- Zeitlich begrenztes Live-Standort-Teilen: genau eine Zeile pro Nutzer
-- (Upsert bei jeder Positionsänderung). Freunde sehen die Zeile nur, solange
-- expires_at in der Zukunft liegt; „Teilen beenden" löscht sie.
create table public.live_locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null
);
-- Die Freundes-Select-Policy filtert über expires_at.
create index live_locations_expires_idx on public.live_locations (expires_at);

-- Die Spur einer laufenden Pilztour, teilbar mit Buddys (Patch 023,
-- #340). EINE Zeile je Nutzer, an Ort und Stelle ersetzt — eine Zeile
-- je Messpunkt wären ~720 pro Person und Drei-Stunden-Tour und damit
-- die erste Tabelle, deren Größe mit der verbrachten Zeit wächst.
-- `expires_at` wird aus der laufenden Standort-Freigabe GEERBT: eine
-- Zustimmung statt zwei. Wer nicht teilt, lädt nichts hoch.
create table public.tour_tracks (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  started_at timestamptz not null,
  -- [[lat, lng, "iso8601"], …] — vor dem Hochladen gedünnt.
  points jsonb not null,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index tour_tracks_expires_idx on public.tour_tracks (expires_at);

-- Fundfotos für Buddys (Patch 026, #532). Die BYTES liegen im Bucket
-- `find-photos`, hier steht je Foto nur eine Zeile: Schlüssel, Fund,
-- Frist. Das Foto hängt am FUND und erbt dessen Sichtbarkeit (die
-- Freundes-Policy fragt `finds`); die Frist gehört der Datenbank —
-- Default 14 Tage, per Constraint nicht verlängerbar. Der Bot räumt
-- Zeilen und Objekte per Abgleich ab. Begründungen im Patch.
create table public.find_photos (
  id uuid primary key default gen_random_uuid(),
  find_id uuid not null references public.finds(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- Pfad im Bucket ohne Endung: `<user_id>/<zufall>`; Bild unter
  -- `<key>.jpg`, Vorschau unter `<key>_s.jpg`.
  key text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  constraint find_photos_frist
    check (expires_at <= created_at + interval '14 days'),
  -- Der Ordner ist der Nutzer — dieselbe Bindung wie in der Upload-Policy.
  constraint find_photos_key_owner
    check (key like (user_id::text || '/%'))
);
create index find_photos_find_idx on public.find_photos (find_id);
create index find_photos_expires_idx on public.find_photos (expires_at);

-- Kudos für Fundfotos (Patch 028): ein Pilz je Buddy und Foto, keine
-- Skala. Sichtbarkeit geerbt vom Foto, abgeräumt per Cascade mit ihm.
-- `user_id` verweist bewusst auf auth.users und nicht auf profiles —
-- sonst wäre die Tabelle für PostgREST eine Verbindungstabelle zwischen
-- find_photos und profiles, und das profiles-Embed der Fotos würde
-- mehrdeutig (PGRST201). Begründung im Patch.
create table public.find_photo_kudos (
  photo_id uuid not null references public.find_photos(id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (photo_id, user_id)
);
create index find_photo_kudos_user_idx on public.find_photo_kudos (user_id);

-- Meldungen an iNaturalist (Patch 029, #553): eine Zeile je Fund und
-- Plattform, angelegt BEVOR gesendet wird — `remote_uuid` macht den
-- Wiederholversuch idempotent. Nur der eigene Fund, nur für mich.
-- `user_id` auf auth.users aus demselben Grund wie bei den Kudos.
-- Begründung und Statusliste im Patch.
create table public.find_reports (
  find_id uuid not null references public.finds(id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  platform text not null default 'inat' check (platform in ('inat')),
  remote_uuid uuid not null,
  remote_id bigint,
  status text not null default 'sending' check (status in
    ('sending', 'reported', 'needs_id', 'research', 'casual', 'withdrawn')),
  gbif_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (find_id, platform)
);
create index find_reports_user_idx on public.find_reports (user_id);

-- Nachrichten zwischen Buddys (Patch 030, #564): angenommen unbegrenzt,
-- bei offener Anfrage höchstens drei eigene je Person, sonst keine.
-- 30 Tage, erzwungen über Check UND Spalten-Grants. Beide Personen auf
-- auth.users (Begründung wie Patch 028). Ende der Freundschaft löscht
-- den Verlauf (Trigger unten). Begründungen im Patch.
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
create index buddy_messages_pair_idx
  on public.buddy_messages (sender_id, recipient_id, created_at);
create index buddy_messages_recipient_idx
  on public.buddy_messages (recipient_id);
create index buddy_messages_expires_idx
  on public.buddy_messages (expires_at);

-- Aliase für Buddys (Patch 032, #567): eine private Notiz je Buddy, nur
-- für den, der sie vergibt; nur für bestätigte Buddys; Ende der
-- Freundschaft löscht sie (Trigger unten). Beide Personen auf auth.users
-- (Begründung wie Patch 028). Begründungen im Patch.
create table public.friend_aliases (
  owner_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  alias text not null check (char_length(btrim(alias)) between 1 and 40),
  updated_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);
create index friend_aliases_friend_idx on public.friend_aliases (friend_id);

-- Feature-Wünsche / Feedback aus der App. Der Feedback-Bot
-- (.github/workflows/feedback.yml) macht daraus GitHub-Issues bzw.
-- Pilzart-PRs und setzt processed_at.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check (char_length(message) between 3 and 2000),
  type text not null default 'feature' check (type in ('feature', 'species', 'bug')),
  species_name text,
  processed_at timestamptz,
  -- Aus welchem Stand die Meldung kam (Patch 021). Nullable: Zeilen von
  -- vor der Migration und von älteren Clients haben die Angabe nicht.
  app_version text,
  -- Ein Bild dazu (Patch 027, #525): Pfad im Bucket `feedback-photos`,
  -- `<user_id>/<zufall>.jpg`. Anders als der Text NICHT öffentlich.
  photo_path text,
  -- Bis zu drei Bilder (Patch 033, #569) — neue Clients schreiben NUR
  -- hierhin, `photo_path` bleibt für 1.186.0–1.195.x. Der Check dazu
  -- steht nach `app_internal` weiter unten (er braucht eine Funktion).
  photo_paths text[],
  -- Einwilligung, die Bilder in der Artgalerie zu zeigen (Patch 034):
  -- selbst aufgenommen, CC BY-SA 4.0, Benutzername als Urheber. Nur mit
  -- Bildern; übernommen wird trotzdem nur nach Ansicht.
  photo_consent boolean not null default false,
  created_at timestamptz not null default now(),
  constraint feedback_photo_owner
    check (photo_path is null or photo_path like (user_id::text || '/%')),
  constraint feedback_photo_consent_needs_photos
    check (not photo_consent or photo_paths is not null)
);

-- Gefangene Fehler aus dem Feld (Patch 009). Android Vitals sieht nur harte
-- Abstürze auf Play-Installationen — die abgefangenen Fehler, bei denen die
-- App mit einer SnackBar weiterläuft, landen hier. Absichtlich ohne
-- Nutzdaten: kein Standort, keine Namen.
create table public.error_reports (
  id uuid primary key default gen_random_uuid(),
  -- Nullable: die wertvollsten Fehler passieren vor der Anmeldung.
  user_id uuid references public.profiles(id) on delete cascade,
  context text not null check (char_length(context) between 1 and 100),
  error_type text not null check (char_length(error_type) <= 100),
  message text check (char_length(message) <= 1000),
  stack text check (char_length(stack) <= 4000),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);
create index error_reports_created_idx
  on public.error_reports (created_at desc);

-- Server-seitige App-Konfiguration (Patch 012). Einzeilige Tabelle: der
-- check lässt nur id = true zu. minimum_supported_version sperrt Clients
-- aus, die zu alt für das aktuelle Schema sind — jede Breaking-Migration
-- setzt den Wert im selben PR hoch (Issue #80).
create table public.app_config (
  id boolean primary key default true check (id),
  minimum_supported_version text not null default '0.0.0'
    check (minimum_supported_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  updated_at timestamptz not null default now()
);
insert into public.app_config (id) values (true);

-- Wohin eine Push-Benachrichtigung geht (#277, Patch 017). Eine Zeile je
-- Gerät; der Token ist der Schlüssel, weil FCM-Token global eindeutig
-- sind. Eine Zeile IST die Zustimmung — es gibt bewusst keine Spalte
-- „aktiv", die dasselbe ein zweites Mal behaupten könnte.
create table public.push_devices (
  token text primary key,
  user_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('android', 'web')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index push_devices_user_idx on public.push_devices (user_id);


-- ============================================================
-- Profil automatisch bei Registrierung anlegen
-- (Username kommt aus den Signup-Metadaten der App)
-- ============================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'username',
                   'pilzfreund_' || substr(new.id::text, 1, 8)));
  return new;
end $$;

-- Nur der Trigger ruft die Funktion — die Default-Grants an die API-Rollen
-- sind unnötig (EXECUTE wird beim Anlegen des Triggers geprüft, nicht beim
-- Feuern).
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================
-- Hilfsfunktionen (SECURITY DEFINER, damit RLS-Policies andere
-- Tabellen lesen können, ohne zu rekursieren)
--
-- Bewusst NICHT in public: PostgREST exponiert jede Funktion im
-- public-Schema als /rest/v1/rpc/-Endpunkt für anon+authenticated.
-- EXECUTE entziehen geht nicht — die Policies werten die Funktionen
-- mit den Rechten der anfragenden Rolle aus. Deshalb liegen sie in
-- app_internal, das die API nie sieht (Patch 011).
-- ============================================================

create schema if not exists app_internal;

-- Der Anlass, aus dem eine Meldung wird (#277, Patch 018). Der Schlüssel
-- ist (Empfänger, Art, Spot): Ein zweiter Fund am selben Spot trifft
-- dieselbe Zeile und schiebt nur die Fälligkeit — so werden aus zehn
-- Funden auf einem Waldgang nicht zehn Meldungen.
create table app_internal.push_outbox (
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('buddy_find', 'new_spot')),
  spot_id uuid not null references public.spots(id) on delete cascade,
  due_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (recipient_id, kind, spot_id)
);
create index push_outbox_due_idx on app_internal.push_outbox (due_at);

-- Warteschlange für Nachrichten-Pushes (Patch 031). In app_internal wie
-- push_outbox (und erst HIER: vorher gibt es das Schema app_internal
-- noch nicht); RLS an, keine Policy, keine Grants.
create table app_internal.push_messages (
  message_id uuid primary key
    references public.buddy_messages(id) on delete cascade,
  created_at timestamptz not null default now()
);
grant usage on schema app_internal to anon, authenticated;

-- Feedback-Bilder (Patch 033): höchstens drei, jedes im Ordner des
-- Melders. Eine Funktion, weil ein CHECK kein Array durchlaufen kann.
create or replace function app_internal.feedback_photos_ok(paths text[], owner uuid)
returns boolean language sql immutable as $$
  select paths is null
      or (cardinality(paths) between 1 and 3
          and not exists (select 1 from unnest(paths) p
                          where p is null or p not like (owner::text || '/%')));
$$;
alter table public.feedback
  add constraint feedback_photos_owner
  check (app_internal.feedback_photos_ok(photo_paths, user_id));

create or replace function app_internal.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b)
        or (requester_id = b and addressee_id = a)));
$$;

-- Auch offene Anfragen zählen — nötig, damit man den Namen des
-- Absenders einer Freundschaftsanfrage sehen kann.
create or replace function app_internal.involved_in_friendship(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where (requester_id = a and addressee_id = b)
       or (requester_id = b and addressee_id = a));
$$;

-- Darf ich [other] schreiben? (Patch 030) Angenommen ⇒ ja; offen ⇒
-- solange ich weniger als drei Nachrichten an sie geschickt habe.
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

create or replace function app_internal.owner_shares_spots(owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select share_spots_default from profiles where id = owner;
$$;

create or replace function app_internal.owner_shares_details(owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select share_details from profiles where id = owner;
$$;

-- Freundesuche: exakte E-Mail oder Username-Präfix; gibt nie E-Mails zurück.
create or replace function public.search_profiles(query text)
returns table (id uuid, username text, display_name text, avatar int)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name, p.avatar
  from profiles p
  left join auth.users u on u.id = p.id
  where p.id <> auth.uid()
    and (lower(u.email) = lower(query) or p.username ilike query || '%')
  limit 10;
$$;
-- Nur für Angemeldete: für anon wäre der exakte E-Mail-Vergleich ein
-- E-Mail-Orakel (verrät ohne Konto, ob eine Adresse registriert ist).
revoke all on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated;

-- Konto-Löschung durch den Nutzer selbst (Play-Anforderung, Patch 008).
-- Alle Tabellen hängen per `on delete cascade` an profiles und profiles an
-- auth.users — das Löschen des Auth-Users räumt daher alles mit ab.
-- Kein Parameter: auth.uid() kommt aus dem JWT, eine übergebene id wäre eine
-- Einladung, fremde Konten zu löschen.
create or replace function public.delete_own_account()
returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_own_account() from public;
revoke all on function public.delete_own_account() from anon;
grant execute on function public.delete_own_account() to authenticated;

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.profiles       enable row level security;
alter table public.spots          enable row level security;
alter table public.finds          enable row level security;
alter table public.friendships    enable row level security;
alter table public.live_locations enable row level security;
alter table public.tour_tracks    enable row level security;
alter table public.find_photos    enable row level security;
alter table public.find_photo_kudos enable row level security;
alter table public.find_reports   enable row level security;
alter table public.buddy_messages enable row level security;
alter table public.friend_aliases enable row level security;
alter table public.feedback       enable row level security;
alter table public.error_reports  enable row level security;
alter table public.app_config     enable row level security;
alter table public.push_devices   enable row level security;
alter table app_internal.push_outbox    enable row level security;
alter table app_internal.push_messages  enable row level security;
revoke all on app_internal.push_messages from public, anon, authenticated;

-- app_config: lesen darf jeder, auch anon — die Mindestversion wird beim
-- Start und damit vor der Anmeldung geprüft. Geändert wird der Wert über
-- einen Patch, deshalb kein insert/update/delete-Grant.
create policy app_config_read on public.app_config for select using (true);
grant select on public.app_config to anon, authenticated;
-- find_photos (Patch 026): ausdrücklich, nicht über auto_expose — die
-- Vorgabe fällt am 2026-10-30 (config.toml).
grant select, insert, delete on public.find_photos to authenticated;
grant select, insert, delete on public.find_photo_kudos to authenticated;
grant select, insert, update, delete on public.find_reports to authenticated;
-- buddy_messages (Patch 030): ERST alles weg — die Legacy-Vorgabe gäbe
-- sonst Tabellen-INSERT, und der schlüge die Spalten-Grants.
revoke all on public.buddy_messages from anon, authenticated;
grant select, delete on public.buddy_messages to authenticated;
grant insert (recipient_id, body) on public.buddy_messages to authenticated;
grant update (read_at) on public.buddy_messages to authenticated;
-- friend_aliases (Patch 032): ebenfalls erst alles weg, anon bekommt nichts.
revoke all on public.friend_aliases from anon, authenticated;
grant select, insert, update, delete on public.friend_aliases to authenticated;

-- push_devices: nur die eigenen Geräte, in beide Richtungen. Ohne das
-- `with check` könnte jemand ein Token auf ein fremdes Konto schreiben
-- und dessen Meldungen mitbekommen. Für den Versender gibt es bewusst
-- KEINE Policy — er liest mit service_role und umgeht RLS; eine Policy
-- wäre die Einladung, den Weg später über einen schwächeren Schlüssel zu
-- gehen.
create policy push_devices_own_all on public.push_devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- push_outbox steht in app_internal und taucht deshalb hier nicht auf:
-- In `public` hielte PostgREST ihn wegen seiner zwei Fremdschlüssel für
-- eine Verbindungstabelle zwischen spots und profiles und könnte das
-- Embed der App nicht mehr auflösen (PGRST201). Siehe Patch 018.

-- error_reports: schreiben darf jeder, auch anon — sonst fehlen genau die
-- Fehler aus Login und Registrierung. Eine fremde user_id lässt sich nicht
-- unterschieben. LESEN darf niemand über die API: es gibt bewusst keine
-- select-Policy, die Auswertung läuft über das Dashboard.
create policy er_insert on public.error_reports for insert
  with check (user_id is null or user_id = auth.uid());
grant insert on public.error_reports to anon, authenticated;

-- feedback: eigene Wünsche einreichen und nachlesen
create policy feedback_insert on public.feedback for insert
  with check (user_id = auth.uid());
create policy feedback_select_own on public.feedback for select
  using (user_id = auth.uid());

-- profiles: ich selbst + alle, mit denen eine (auch offene) Freundschaft
-- besteht (Suche läuft über search_profiles)
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or app_internal.involved_in_friendship(id, auth.uid()));
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- spots: Besitzer hat Vollzugriff
create policy spots_owner_all on public.spots for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- spots: Freunde sehen geteilte, nicht ausgeschlossene Spots (nur Standort-Ebene)
create policy spots_friend_select on public.spots for select
  using (owner_id <> auth.uid()
     and app_internal.are_friends(owner_id, auth.uid())
     and not sharing_excluded
     and app_internal.owner_shares_spots(owner_id));

-- finds: Jeder Fund gehört seinem EINTRAGER (Patch 014). Eigene Funde:
-- voller Zugriff, überall — auch wenn die Freigabe später endet (jeder
-- behält die eigenen Funde). Der with check bindet das ANLEGEN an die
-- Sichtbarkeit des Spots: eigener Spot oder volle Freigabe-Beziehung
-- zum Besitzer. Die Bedingungen stehen absichtlich ausgeschrieben,
-- obwohl die spots-RLS im Subselect ohnehin greift — eine später
-- großzügigere spots-Sichtbarkeit soll das Schreibrecht nicht
-- stillschweigend mitweiten.
create policy finds_author_all on public.finds for all
  using (author_id = auth.uid())
  with check (author_id = auth.uid()
    and exists (select 1 from public.spots s
                where s.id = spot_id
                  and (s.owner_id = auth.uid()
                    or (app_internal.are_friends(s.owner_id, auth.uid())
                        and not s.sharing_excluded
                        and app_internal.owner_shares_spots(s.owner_id)))));
-- finds: Der Spot-Besitzer sieht fremde Funde nur, solange die
-- Freigabe-Beziehung zum AUTOR besteht — symmetrisch zur Sicht des
-- Freundes auf den Spot. Kein owner_shares_details-Gate: Der Autor hat
-- den Fund wissentlich auf diesen Spot geschrieben.
create policy finds_owner_select on public.finds for select
  using (author_id <> auth.uid()
    and exists (select 1 from public.spots s
                where s.id = spot_id
                  and s.owner_id = auth.uid()
                  and not s.sharing_excluded)
    and app_internal.are_friends(author_id, auth.uid())
    and app_internal.owner_shares_spots(auth.uid()));
-- finds: Freunde sehen Fund-Details nur mit Detail-Freigabe des
-- Besitzers — beschränkt auf dessen EIGENE Funde (author_id =
-- s.owner_id): Funde dritter Buddies wandern nie zu Nicht-Freunden.
-- Die eigenen Funde am Freundes-Spot liefert finds_author_all.
create policy finds_friend_select on public.finds for select
  using (exists (select 1 from public.spots s
                 where s.id = spot_id
                   and s.owner_id <> auth.uid()
                   and author_id = s.owner_id
                   and app_internal.are_friends(s.owner_id, auth.uid())
                   and not s.sharing_excluded
                   and app_internal.owner_shares_spots(s.owner_id)
                   and app_internal.owner_shares_details(s.owner_id)));

-- friendships
create policy fr_select on public.friendships for select
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy fr_insert on public.friendships for insert
  with check (requester_id = auth.uid() and status = 'pending');
create policy fr_accept on public.friendships for update
  using (addressee_id = auth.uid() and status = 'pending')
  with check (status = 'accepted');
create policy fr_delete on public.friendships for delete   -- ablehnen / zurückziehen / entfreunden
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- live_locations: eigene Zeile voll verwalten (upsert/löschen/lesen),
-- Freunde sehen sie nur, solange die Freigabe nicht abgelaufen ist.
create policy ll_owner_all on public.live_locations for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ll_friend_select on public.live_locations for select
  using (user_id <> auth.uid()
     and app_internal.are_friends(user_id, auth.uid())
     and expires_at > now());

-- tour_tracks: Spiegel der beiden Policies darüber (Patch 023). Zwei
-- Tabellen mit demselben Sichtbarkeitsversprechen formulieren es
-- gleich — sonst driftet beim nächsten Anfassen eine davon.
create policy tt_owner_all on public.tour_tracks for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy tt_friend_select on public.tour_tracks for select
  using (user_id <> auth.uid()
     and app_internal.are_friends(user_id, auth.uid())
     and expires_at > now());

-- find_photos (Patch 026): eigene Zeilen voll, anlegen nur an EIGENEN
-- Funden. Fremde: nicht abgelaufen UND der Fund ist für mich lesbar —
-- die Freigabe steht in den finds-Policies, nicht hier. Das ist der
-- Punkt: Ein Foto ist genau so sichtbar wie der Fund, an dem es hängt.
create policy fp_owner_all on public.find_photos for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
    and exists (select 1 from public.finds f
                where f.id = find_id and f.author_id = auth.uid()));
create policy fp_friend_select on public.find_photos for select
  using (user_id <> auth.uid()
     and expires_at > now()
     and exists (select 1 from public.finds f where f.id = find_id));

-- find_photo_kudos (Patch 028): lesen, was an sichtbaren Fotos hängt;
-- geben nur als ich selbst und nie ans eigene Foto; zurücknehmen nur
-- die eigenen.
create policy fpk_select on public.find_photo_kudos for select
  using (exists (select 1 from public.find_photos p where p.id = photo_id));
create policy fpk_insert on public.find_photo_kudos for insert
  with check (user_id = auth.uid()
    and exists (select 1 from public.find_photos p
                where p.id = photo_id and p.user_id <> auth.uid()));
create policy fpk_delete on public.find_photo_kudos for delete
  using (user_id = auth.uid());

-- find_reports (Patch 029): nur die eigene Zeile, nur am eigenen Fund.
create policy fr_select on public.find_reports for select
  using (user_id = auth.uid());
create policy fr_insert on public.find_reports for insert
  with check (user_id = auth.uid()
    and exists (select 1 from public.finds f
                where f.id = find_id and f.author_id = auth.uid()));
create policy fr_update on public.find_reports for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
    and exists (select 1 from public.finds f
                where f.id = find_id and f.author_id = auth.uid()));
create policy fr_delete on public.find_reports for delete
  using (user_id = auth.uid());

-- buddy_messages (Patch 030): lesen, was mich betrifft und nicht
-- abgelaufen ist; schreiben nach `may_message`; gelesen markieren nur,
-- was an mich ging; zurücknehmen nur die eigenen.
create policy bm_select on public.buddy_messages for select
  using ((sender_id = auth.uid() or recipient_id = auth.uid())
     and expires_at > now());
create policy bm_insert on public.buddy_messages for insert
  with check (sender_id = auth.uid()
    and app_internal.may_message(recipient_id));
create policy bm_read on public.buddy_messages for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());
create policy bm_delete on public.buddy_messages for delete
  using (sender_id = auth.uid());

-- friend_aliases (Patch 032): alles nur für den Besitzer; anlegen und
-- ändern nur für bestätigte Buddys.
create policy fa_select on public.friend_aliases for select
  using (owner_id = auth.uid());
create policy fa_insert on public.friend_aliases for insert
  with check (owner_id = auth.uid()
    and app_internal.are_friends(owner_id, friend_id));
create policy fa_update on public.friend_aliases for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid()
    and app_internal.are_friends(owner_id, friend_id));
create policy fa_delete on public.friend_aliases for delete
  using (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Storage: der Bucket der Fundfotos (Patch 026)
-- ---------------------------------------------------------------------------
-- Privat, JPEG, gedeckelt. Hochladen und Löschen nur im eigenen Ordner;
-- lesen darf, wer eine Zeile dazu sieht — und das entscheiden die
-- Policies oben. Ein Objekt ohne Zeile ist für niemanden lesbar.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('find-photos', 'find-photos', false, 600000, array['image/jpeg'])
on conflict (id) do nothing;

create policy find_photos_upload on storage.objects for insert
  to authenticated
  with check (bucket_id = 'find-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);
create policy find_photos_read on storage.objects for select
  to authenticated
  using (bucket_id = 'find-photos'
    and exists (select 1 from public.find_photos p
                where name in (p.key || '.jpg', p.key || '_s.jpg')));
create policy find_photos_remove on storage.objects for delete
  to authenticated
  using (bucket_id = 'find-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);

-- Der Bucket der Feedback-Bilder (Patch 027, #525). Strenger als oben:
-- Nutzer legen nur hinein, lesen darf allein der Betreiber (Service-
-- Schlüssel) — der Text einer Meldung wird öffentlich, das Bild nicht.
-- Objekte älter als 90 Tage räumt der Bot ab. Grenze 2 MB seit Patch
-- 035: Art-Hinweise laden in Galerie-Größe (2048 px) hoch.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback-photos', 'feedback-photos', false, 2000000, array['image/jpeg'])
on conflict (id) do nothing;

create policy feedback_photos_upload on storage.objects for insert
  to authenticated
  with check (bucket_id = 'feedback-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Patch-Buchführung
-- ---------------------------------------------------------------------------
-- Dieselbe Tabelle legt auch tool/db_migrate.sh an (`if not exists`) — sie
-- muss dort stehen, weil die Live-Datenbank diese Datei nie im Ganzen sieht.
create table if not exists public.applied_patches (
  filename text primary key,
  applied_at timestamptz not null default now()
);
alter table public.applied_patches enable row level security;
revoke all on table public.applied_patches from anon, authenticated;

-- Diese Datei bildet den Stand NACH den folgenden Patches ab. Sie werden
-- deshalb nur eingetragen, nicht ausgeführt: Ein erneuter Lauf über ein
-- Schema, das ihr Ergebnis schon enthält, verlangte von jedem alten Patch
-- auf Dauer Idempotenz — und zwang dazu, alte Patches nachträglich zu
-- ändern, sobald ein neuerer ihre Voraussetzungen verschob (so geschehen
-- bei patch_007, als patch_011 die Helfer nach app_internal zog). Genau das
-- ist gefährlich: Live läuft ein bereits eingespielter Patch nie wieder, die
-- Änderung landet also ausschließlich in Frischinstallationen, und beide
-- Welten driften still auseinander.
--
-- Folge: Ein neuer patch_NNN gehört im selben PR HIER in die Liste und in
-- die Struktur oben. `tool/patch_guard.sh` erzwingt beides.
-- ============================================================
-- Push: Auslöser und Versand (#277, Patch 018)
-- ============================================================
--
-- Wer benachrichtigt wird, ist NICHT neu entschieden: Es sind exakt die,
-- die den Vorgang ohnehin sehen dürfen — dieselben Bedingungen wie in
-- den Policies oben. Eine Meldung über etwas, das man in der App nicht
-- finden kann, wäre schlimmer als keine.

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- ------------------------------------------------------------- Der Korb
--
-- Der Schlüssel ist (Empfänger, Art, Spot): Ein zweiter Fund am selben
-- Spot trifft dieselbe Zeile und schiebt nur die Fälligkeit — genau das
-- ist das Entprellen. Der Spot steht drin, damit zwei verschiedene Spots
-- getrennt melden; sein Name wandert NIE in eine Nutzlast.

-- ------------------------------------------------------- Die Fälligkeit
--
-- Fünf Minuten Ruhe, gedeckelt auf eine halbe Stunde ab dem ersten
-- Anlass. Die Zahlen stehen hier an EINER Stelle, damit sie nicht
-- zwischen den beiden Triggern auseinanderlaufen.
create or replace function app_internal.push_due_at(first_seen timestamptz)
returns timestamptz
language sql immutable as $$
  select least(now() + interval '5 minutes', first_seen + interval '30 minutes');
$$;

-- --------------------------------------------------------- Die Auslöser

-- Ein Fund ist eingetragen worden. Zwei Fälle, und sie haben
-- verschiedene Empfänger:
--
--   1. Ein Buddy trägt an einem FREMDEN Spot ein  -> der Besitzer erfährt
--      es (Spiegel von `finds_owner_select`).
--   2. Jemand trägt am EIGENEN Spot ein           -> seine Buddys
--      erfahren es (Spiegel von `finds_friend_select`, inklusive des
--      Detail-Gates: Wer seine Funde nicht teilt, meldet auch nichts).
--
-- Leergänge (`blank`, #211) lösen bewusst NICHTS aus: „Ich war da und
-- habe nichts gefunden" ist für einen Buddy keine Nachricht wert.
create or replace function app_internal.push_on_find()
returns trigger
language plpgsql security definer
set search_path = public, app_internal as $$
declare
  spot public.spots%rowtype;
begin
  if new.blank then return new; end if;
  select * into spot from public.spots where id = new.spot_id;
  if not found then return new; end if;

  if new.author_id <> spot.owner_id then
    if app_internal.are_friends(spot.owner_id, new.author_id)
       and not spot.sharing_excluded
       and app_internal.owner_shares_spots(spot.owner_id) then
      insert into app_internal.push_outbox (recipient_id, kind, spot_id, due_at)
        values (spot.owner_id, 'buddy_find', spot.id,
                app_internal.push_due_at(now()))
        on conflict (recipient_id, kind, spot_id) do update
          set due_at = app_internal.push_due_at(push_outbox.created_at);
    end if;
    return new;
  end if;

  if spot.sharing_excluded
     or not app_internal.owner_shares_spots(spot.owner_id)
     or not app_internal.owner_shares_details(spot.owner_id) then
    return new;
  end if;
  insert into app_internal.push_outbox (recipient_id, kind, spot_id, due_at)
    select f.friend_id, 'buddy_find', spot.id, app_internal.push_due_at(now())
      from app_internal.push_friends(spot.owner_id) f
    on conflict (recipient_id, kind, spot_id) do update
      set due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;

-- Ein neuer Spot. Empfänger sind die Buddys, die ihn sehen dürfen —
-- Spiegel der spots-Policy. Kein Detail-Gate: Es geht um den Spot, nicht
-- um seine Funde.
create or replace function app_internal.push_on_spot()
returns trigger
language plpgsql security definer
set search_path = public, app_internal as $$
begin
  if new.sharing_excluded
     or not app_internal.owner_shares_spots(new.owner_id) then
    return new;
  end if;
  insert into app_internal.push_outbox (recipient_id, kind, spot_id, due_at)
    select f.friend_id, 'new_spot', new.id, app_internal.push_due_at(now())
      from app_internal.push_friends(new.owner_id) f
    on conflict (recipient_id, kind, spot_id) do nothing;
  return new;
end $$;

-- Die angenommenen Freundschaften einer Person, in eine Richtung
-- aufgelöst. Eigene Funktion, weil beide Trigger sie brauchen und die
-- Richtung sonst zweimal dastünde.
create or replace function app_internal.push_friends(person uuid)
returns table (friend_id uuid)
language sql stable as $$
  select case when requester_id = person then addressee_id else requester_id end
    from public.friendships
   where status = 'accepted'
     and (requester_id = person or addressee_id = person);
$$;

create trigger push_on_find_trg after insert on public.finds
  for each row execute function app_internal.push_on_find();

create trigger push_on_spot_trg after insert on public.spots
  for each row execute function app_internal.push_on_spot();

-- Nachrichten (Patch 031): eigene Warteschlange, per Cascade an der
-- Nachricht — zurückgenommen oder mit der Freundschaft gelöscht, löst
-- sie keine Meldung mehr aus. Versand im selben `push_flush`.
create or replace function app_internal.push_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into app_internal.push_messages (message_id) values (new.id);
  return new;
end;
$$;
revoke all on function app_internal.push_on_message() from public, anon, authenticated;
create trigger push_on_message_trg after insert on public.buddy_messages
  for each row execute function app_internal.push_on_message();

-- ---------------------------------------------------------- Der Versand
--
-- Holt die fälligen Zeilen, macht daraus Nachrichten je Gerät und ruft
-- `send-push`. Die drei Geheimnisse stehen im VAULT und NICHT hier —
-- ein Patch liegt öffentlich im Repo. Von Hand anzulegen (einmalig, im
-- SQL-Editor des Dashboards):
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1',
--                              'push_functions_url');
--   select vault.create_secret('<PUSH_JOB_SECRET>', 'push_job_secret');
--   select vault.create_secret('<SERVICE_ROLE_KEY>', 'push_service_key');
--
-- **Fehlt eines davon, tut die Funktion NICHTS** — sie wirft nicht. Der
-- Patch spielt beim Merge ein, die Geheimnisse kommen von Hand: Ohne
-- diese Nachsicht liefe ab dem Merge jede Minute ein scheiternder
-- Cron-Job in der Produktion. So schaltet sich der Versand in dem
-- Moment ein, in dem die Geheimnisse stehen.
--
-- Der Text ist ABSICHTLICH nichtssagend: keine Koordinaten, kein
-- Spot-Name, kein Benutzername. Eine Push läuft über Googles Server.
-- AUSNAHME seit Patch 031: Nachrichten zwischen Buddys tragen den Namen
-- des Absenders und ihren Text (Betreiber-Entscheidung, #564) — der Text
-- stammt von einem Menschen, nicht von der App.
create or replace function app_internal.push_flush()
returns integer
language plpgsql security definer
set search_path = public, app_internal, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
  payload jsonb;
  message_payload jsonb;
  sent integer;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'push_functions_url';
  select decrypted_secret into job_secret
    from vault.decrypted_secrets where name = 'push_job_secret';
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'push_service_key';

  -- Nicht eingerichtet: Fällige Zeilen trotzdem wegräumen und still
  -- zurück. Ohne das Löschen wüchse der Korb bis zur Einrichtung.
  if base_url is null or job_secret is null or service_key is null then
    delete from app_internal.push_outbox where due_at <= now();
    delete from app_internal.push_messages;
    return 0;
  end if;

  with due as (
    delete from app_internal.push_outbox
     where due_at <= now()
    returning recipient_id, kind, spot_id
  ),
  -- Je Empfänger EINE Nachricht, auch wenn mehrere Spots fällig sind:
  -- „drei Meldungen gleichzeitig" ist die Art, wie Benachrichtigungen
  -- lästig werden.
  grouped as (
    select recipient_id,
           count(*) filter (where kind = 'buddy_find') as finds,
           count(*) filter (where kind = 'new_spot') as spots,
           count(distinct spot_id) filter (where kind = 'buddy_find')
             as find_spots
      from due group by recipient_id
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', case
             when g.finds > 0 and g.spots > 0
               then 'Deine Buddys waren unterwegs'
             when g.finds > 1
               then g.finds || ' neue Funde bei deinen Buddys'
             when g.finds = 1 then 'Neuer Fund bei einem Buddy'
             when g.spots > 1
               then g.spots || ' neue Spots von deinen Buddys'
             else 'Ein Buddy hat einen neuen Spot geöffnet'
           end,
           -- Der Rumpf trägt die zweite Dimension, wo es eine gibt. Wo
           -- nicht, sagt er, was ein Tipp bringt — mehr bleibt ohne
           -- Namen und Arten nicht übrig, und beim ersten Mal ist es
           -- nicht selbstverständlich.
           'body', case
             when g.finds > 0 and g.spots > 0 then
               g.finds || (case when g.finds = 1 then ' neuer Fund'
                                else ' neue Funde' end) || ' und ' ||
               g.spots || (case when g.spots = 1 then ' neuer Spot'
                                else ' neue Spots' end)
             when g.find_spots > 1 then 'An ' || g.find_spots || ' Spots'
             when g.finds > 1 then 'An einem Spot'
             else 'Tippen zeigt dir die Stelle auf der Karte'
           end))
    into payload
    from grouped g
    join public.push_devices d on d.user_id = g.recipient_id;

  -- Nachrichten (Patch 031): OHNE Entprellung — eine Nachricht will
  -- gelesen werden, solange sie aktuell ist; der Minutentakt fasst
  -- trotzdem zusammen, was in derselben Minute kam. Je Empfänger UND
  -- Absender eine Meldung: der Name als Titel, die NEUESTE Nachricht als
  -- Text, gekürzt. MIT Text — Betreiber-Entscheidung in #564, die
  -- Datenschutzerklärung sagt es. Das Ziel in der App reist als `route`.
  -- Eine Nachricht, die vor dem Lauf zurückgenommen oder mit der
  -- Freundschaft gelöscht wurde, ist per Cascade schon aus der
  -- Warteschlange — sie löst keine Meldung mehr aus.
  with due_msgs as (
    delete from app_internal.push_messages q
     using public.buddy_messages m
     where q.message_id = m.id
    returning m.sender_id, m.recipient_id, m.body, m.created_at
  ),
  per_sender as (
    select recipient_id, sender_id, count(*) as n,
           (array_agg(body order by created_at desc))[1] as last_body
      from due_msgs group by recipient_id, sender_id
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           -- Der Alias, den der EMPFÄNGER vergeben hat (Patch 032) —
           -- sonst stünde in der Meldung ein anderer Name als in der App.
           'title', coalesce(a.alias, p.username, 'Buddy') ||
             case when s.n > 1 then ' · ' || s.n || ' Nachrichten'
                  else '' end,
           'body', case when char_length(s.last_body) > 180
                        then left(s.last_body, 179) || '…'
                        else s.last_body end,
           'route', '/friends/chat/' || s.sender_id))
    into message_payload
    from per_sender s
    join public.push_devices d on d.user_id = s.recipient_id
    left join public.profiles p on p.id = s.sender_id
    left join public.friend_aliases a
      on a.owner_id = s.recipient_id and a.friend_id = s.sender_id;

  payload := coalesce(payload, '[]'::jsonb) ||
             coalesce(message_payload, '[]'::jsonb);
  if jsonb_array_length(payload) = 0 then return 0; end if;
  select jsonb_array_length(payload) into sent;

  -- Asynchron (pg_net): Die Antwort landet in `net._http_response`, der
  -- Cron-Lauf wartet nicht darauf. Ein fehlgeschlagener Versand ist
  -- verloren — bewusst: Eine Wiedervorlage für Benachrichtigungen
  -- brächte im Zweifel dieselbe Meldung ein zweites Mal, und das ist
  -- schlimmer als eine verpasste.
  perform net.http_post(
    url := base_url || '/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key,
      'x-push-secret', job_secret),
    body := jsonb_build_object('messages', payload));
  return sent;
end $$;

revoke all on function app_internal.push_flush() from public, anon, authenticated;
revoke all on function app_internal.push_due_at(timestamptz) from public, anon, authenticated;
revoke all on function app_internal.push_friends(uuid) from public, anon, authenticated;

-- Jede Minute. Der Takt bestimmt nur die Verzögerung NACH der
-- Entprell-Frist; teuer ist er nicht, weil ohne fällige Zeilen nichts
-- passiert.
select cron.schedule('push-flush', '* * * * *',
                     $cron$select app_internal.push_flush()$cron$);

-- Nachrichten (Patch 030): Ende der Freundschaft löscht den Verlauf
-- beider Seiten; Abgelaufenes räumt ein Cron-Job täglich.
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
-- Aliase (Patch 032): Ende der Freundschaft löscht sie beider Seiten.
create or replace function app_internal.aliases_on_unfriend()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from friend_aliases a
  where (a.owner_id = old.requester_id and a.friend_id = old.addressee_id)
     or (a.owner_id = old.addressee_id and a.friend_id = old.requester_id);
  return old;
end;
$$;
revoke all on function app_internal.aliases_on_unfriend() from public, anon, authenticated;
create trigger friendships_delete_aliases
  after delete on public.friendships
  for each row execute function app_internal.aliases_on_unfriend();
select cron.schedule('buddy-messages-sweep', '17 3 * * *',
                     $cron$delete from public.buddy_messages where expires_at < now()$cron$);

insert into public.applied_patches (filename) values
  ('patch_001_anfragen_namen.sql'),
  ('patch_002_feedback.sql'),
  ('patch_003_feedback_typen.sql'),
  ('patch_004_feedback_bug.sql'),
  ('patch_005_avatare.sql'),
  ('patch_006_friendship_indexe.sql'),
  ('patch_007_live_locations.sql'),
  ('patch_008_konto_loeschen.sql'),
  ('patch_009_fehlerberichte.sql'),
  ('patch_010_applied_patches_rls.sql'),
  ('patch_011_interne_funktionen.sql'),
  ('patch_012_mindestversion.sql'),
  ('patch_013_username_gross_klein.sql'),
  ('patch_014_buddy_funde.sql'),
  ('patch_015_leergang.sql'),
  ('patch_016_client_id.sql'),
  ('patch_017_push_geraete.sql'),
  ('patch_018_push_ausloeser.sql'),
  ('patch_019_push_leerlauf.sql'),
  ('patch_020_push_text.sql'),
  ('patch_021_feedback_version.sql'),
  ('patch_022_fund_position.sql'),
  ('patch_023_tour_tracks.sql'),
  ('patch_024_fundstellen_versatz.sql'),
  ('patch_025_vormerkung.sql'),
  ('patch_026_fundfotos.sql'),
  ('patch_027_feedback_bild.sql'),
  ('patch_028_fundfoto_kudos.sql'),
  ('patch_029_inat_meldungen.sql'),
  ('patch_030_buddy_nachrichten.sql'),
  ('patch_031_nachrichten_push.sql'),
  ('patch_032_buddy_alias.sql'),
  ('patch_033_feedback_bilder.sql'),
  ('patch_034_galerie_einwilligung.sql'),
  ('patch_035_feedback_bild_groesse.sql')
on conflict do nothing;
