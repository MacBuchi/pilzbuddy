-- Patch 022: Ein Fund bekommt seine eigene Position (#373, zweite Hälfte
-- von #367).
--
-- Bis hierher hat nur der SPOT Koordinaten. Jeder Fund an einem Spot löst
-- damit auf denselben Punkt auf — egal, wie weit die Pilze wirklich
-- auseinanderstanden. Der Betreiber: mehrere Funde an einem Spot sollen
-- sich unterscheiden lassen, und die Stelle soll so genau dokumentiert
-- sein, wie sie messbar ist.
--
-- ALLE DREI SPALTEN SIND NULLABLE, und das ist die Aussage: Der Normalfall
-- bleibt der Fund OHNE eigene Position. So sieht jede Bestandszeile aus,
-- und so sieht der Fund aus, der abends auf dem Sofa nachgetragen wird —
-- „Neuer Spot" nimmt die Fadenkreuz-Position aus der Karte, der Standort
-- spielt beim Eintragen keine Rolle. Ein blind beim Öffnen des Blatts
-- genommener Fix schriebe das Wohnzimmer auf den Fund; die Pilztour hat
-- dieselbe Frage mit „lieber zu wenig als zu viel" beantwortet
-- (lib/features/tour/tour_track.dart).
--
-- `accuracy_m` ist der Streuradius, den das GERÄT zum Fix gemeldet hat.
-- Er wird mitgeführt und nicht weggeworfen, weil eine Koordinate ohne ihn
-- eine Genauigkeit behauptet, die sie nicht hat: `nearby_spots.dart` hält
-- fest, dass GPS unter Blätterdach 10–20 m danebenliegt.
--
-- Zugleich IST er die Herkunftsangabe: LEER bei gesetzter Koordinate
-- heißt „auf der Karte gewählt". Ein Fadenkreuz hat keinen Messfehler,
-- den man angeben könnte, und eine erfundene Zahl wäre schlimmer als
-- keine. Eine eigene `position_source`-Spalte wäre eine zweite Wahrheit
-- über dieselbe Sache und bräuchte einen Kreuz-Constraint, um konsistent
-- zu bleiben — zumal die Oberfläche `accuracy_m` ohnehin auswerten muss,
-- um zu entscheiden, ob sie ein „±" schreibt. Kommt je eine dritte Quelle
-- dazu (etwa „aus der Pilztour übernommen"), ist der Weg ein Patch mit
-- `source`-Spalte, nicht eine Umdeutung dieser hier.
--
-- KEIN Bump von minimum_supported_version: rein additiv. Ein älterer
-- Client sendet die Spalten nicht und ignoriert sie im finds(*)-Embed; er
-- zeigt den Fund dann wie bisher ohne eigene Position.
--
-- KEIN Policy-Patch — und das ist trotzdem eine Entscheidung, deshalb
-- steht sie hier: finds_author_all, finds_owner_select und
-- finds_friend_select sind spaltenunabhängig, ein Freund mit
-- DETAIL-Freigabe sieht ab jetzt also die metergenaue Fundstelle statt
-- nur den Spot. Das ist gewollt: Er sieht den Spot ohnehin, der
-- Unterschied sind die zwanzig Meter innerhalb desselben Fleckens, und
-- genau diese Genauigkeit IST der Zweck. Spaltenweise Freigabe könnte
-- Postgres-RLS auch gar nicht — das ginge nur über eine View, und die
-- zerschlüge das finds(*)-Embed, an dem die ganze App hängt. Wer die
-- Fundstelle nicht teilen will, hat weiterhin drei Regler dafür:
-- Detail-Freigabe global, Spot ausschließen, Freundschaft.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- "Schema Check").

alter table public.finds
  add column lat double precision,
  add column lng double precision,
  add column accuracy_m double precision;

-- Eine halbe Koordinate ist keine. Beide oder keine — sonst entstünde
-- über einen krummen Import eine Zeile, die auf dem Nullmeridian oder am
-- Äquator zu liegen scheint.
alter table public.finds
  add constraint finds_position_paar
  check ((lat is null) = (lng is null));

-- Die Erde ist endlich. Der GPX-Import prüft das schon (_validCoords in
-- waypoint_parser.dart); hier steht die Linie, die nicht vom Client
-- abhängt.
alter table public.finds
  add constraint finds_position_bereich
  check (lat is null
         or (lat between -90 and 90 and lng between -180 and 180));

-- Eine Genauigkeit ohne Koordinate beschreibt nichts, und ein negativer
-- Radius ist kein Radius. Bewusst KEINE Obergrenze: Ab wann ein Fix zu
-- grob ist, entscheidet die Oberfläche und darf sich ändern — ein
-- Constraint betonierte die Zahl für alle Zeit ein und wiese ausgerechnet
-- das Zurückspielen älterer Sicherungen ab.
alter table public.finds
  add constraint finds_genauigkeit_sinn
  check (accuracy_m is null or (lat is not null and accuracy_m >= 0));

-- PostgREST-Schema-Cache sofort neu laden (neue Spalten), damit der
-- direkt anschließende Schema-Check nicht gegen die alte Oberfläche
-- prüft.
notify pgrst, 'reload schema';
