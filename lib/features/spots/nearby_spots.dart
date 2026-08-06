// Wann sind zwei Fundorte in Wirklichkeit einer? (#215)
//
// Der Betreiber im Feld: „Wenn ich 5 m weitergehe, wird ein neuer Fundort
// aufgemacht … sodass sich die Fundorte örtlich nicht überlagern. Man
// könnte sich das so vorstellen, dass sie quasi wie in kleinen Sektionen
// geteilt sind, mit einem kleinen Umkreis. Sagen wir mal 20 m."
//
// Umgesetzt als **Umkreis um vorhandene Spots**, nicht als festes Raster:
// Ein Raster trennt zwei Funde, die zwei Meter auseinanderliegen, sobald
// eine Zellgrenze zwischen ihnen verläuft — und diese Grenze liegt für
// den Sammler im Wald völlig unsichtbar da.
//
// Alles hier ist rein: Listen rein, Ergebnis raus. Die Regel ist die
// Substanz von #215, die Oberfläche darüber ist austauschbar.
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../models/spot.dart';

/// Ab dieser Entfernung gelten zwei Fundorte als verschiedene Stellen.
///
/// 20 m ist die Zahl des Betreibers, und sie passt zur Streuung: GPS unter
/// Blätterdach liegt 10–20 m daneben, zwei Einträge derselben Stelle
/// können also durchaus so weit auseinanderliegen.
const kNearbySpotMeters = 20.0;

/// Ein Spot mit seiner Entfernung zum gefragten Punkt.
typedef SpotDistance = ({Spot spot, double meters});

/// Zwei eigene Spots, die zu dicht beieinanderstehen.
typedef SpotPair = ({Spot a, Spot b, double meters});

/// Der nächste EIGENE Spot innerhalb von [meters] — oder `null`.
///
/// Bewusst nur eigene: Einen Fund still an den Spot eines Buddys zu
/// hängen, nur weil man zufällig dort steht, wäre eine Überraschung — und
/// zusammenführen lassen sich fremde Spots ohnehin nie.
SpotDistance? nearestOwnSpot(
  List<Spot> spots,
  LatLng at, {
  double meters = kNearbySpotMeters,
}) {
  SpotDistance? best;
  for (final spot in spots) {
    if (!spot.isOwn) continue;
    final distance =
        distanceMeters(at.latitude, at.longitude, spot.lat, spot.lng);
    if (distance > meters) continue;
    if (best == null || distance < best.meters) {
      best = (spot: spot, meters: distance);
    }
  }
  return best;
}

/// Alle eigenen Spot-Paare, die dichter als [meters] beieinanderliegen —
/// nächstes zuerst.
///
/// Jedes Paar kommt **einmal** vor: Die innere Schleife startet hinter der
/// äußeren, sonst stünde jede Überlagerung zweimal in der Liste (A/B und
/// B/A) und man räumte scheinbar doppelt so viel auf, wie es gibt.
///
/// Quadratisch über die eigenen Spots — bei Hobby-Datenmengen (ein paar
/// hundert) ist das eine Millisekunde, und die Liste liegt ohnehin schon
/// im Speicher.
List<SpotPair> overlappingPairs(
  List<Spot> spots, {
  double meters = kNearbySpotMeters,
}) {
  final own = [
    for (final spot in spots)
      if (spot.isOwn) spot,
  ];
  final pairs = <SpotPair>[];
  for (var i = 0; i < own.length; i++) {
    for (var j = i + 1; j < own.length; j++) {
      final distance = distanceMeters(
          own[i].lat, own[i].lng, own[j].lat, own[j].lng);
      if (distance <= meters) {
        pairs.add((a: own[i], b: own[j], meters: distance));
      }
    }
  }
  pairs.sort((x, y) => x.meters.compareTo(y.meters));
  return pairs;
}

/// Lässt sich dieses Paar zusammenführen?
///
/// Nein, sobald an einem der beiden ein **fremder** Fund hängt. Die RLS
/// lässt einen nur die eigenen Funde umhängen
/// (`finds_author_all` prüft `author_id = auth.uid()`); ein Buddy-Fund
/// bliebe am alten Spot liegen, und dessen Löschung nähme ihn per
/// `on delete cascade` still mit. Das wäre Datenverlust bei jemand
/// anderem — deshalb wird das Paar gar nicht erst angeboten.
bool canMerge(SpotPair pair) =>
    pair.a.finds.every((f) => f.isOwn) && pair.b.finds.every((f) => f.isOwn);
