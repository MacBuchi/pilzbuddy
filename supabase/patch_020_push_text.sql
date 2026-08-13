-- Mehr Inhalt in der Benachrichtigung (Betreiber-Rückmeldung vom
-- 2026-08-13: „im Vergleich zu anderen Apps quasi wertlos, bis man
-- drauf klickt").
--
-- Zwei Mängel, beide ohne neue Daten zu beheben:
--
-- 1. **Der Titel war verschenkt.** Dort stand „PilzBuddy" — was Android
--    ohnehin über jeder Meldung anzeigt. Die eigentliche Aussage rutschte
--    damit in die zweite Zeile, und die wird im eingeklappten Banner als
--    Erstes abgeschnitten. Jetzt trägt der Titel die Aussage.
-- 2. **Es fehlte jede Menge.** Drei Funde sahen aus wie einer.
--
-- **Was bewusst NICHT dazukommt: Namen und Arten.** Die Meldung läuft
-- über Googles Server, und die Datenschutzerklärung sagt zu, dass sie
-- „niemals Koordinaten und niemals Spot-Namen" enthält, sondern nur
-- einen allgemeinen Hinweis. Anzahlen sind Aggregate und bleiben
-- innerhalb dieser Zusage; ein Benutzername wäre der soziale Graph, eine
-- Pilzart wäre Fundinhalt — beides bräuchte eine geänderte Zusage und
-- eine eigene Entscheidung (Betreiber, 2026-08-13: vorerst nicht).
--
-- Neu ist außerdem die Zahl der betroffenen SPOTS. Sie kommt aus
-- `spot_id`, das der DELETE bisher gar nicht zurückgab — ohne sie ließe
-- sich „drei Funde an zwei Spots" nicht sagen.
--
-- Grundlage ist patch_019, NICHT patch_018: Dort heißt der Header
-- `x-push-secret`, und ein Neuschreiben aus der älteren Fassung hätte
-- ihn stillschweigend auf `x-push-job-secret` zurückgedreht — die
-- Function hätte weiter Meldungen erzeugt, und `send-push` hätte sie
-- allesamt als unbefugt abgewiesen.

create or replace function app_internal.push_flush()
returns integer
language plpgsql security definer
set search_path = public, app_internal, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
  payload jsonb;
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

  if payload is null then return 0; end if;
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
