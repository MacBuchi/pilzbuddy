// Die Spur der laufenden Pilztour auf der Karte (#338) — „Linienpunkte",
// so der Betreiber.
//
// Ein Punkt je Fix, kein Linienzug. Zwei Gründe, und der zweite ist der
// eigentliche: Die Fassade kennt keine Polylinien (beide Engines müssten
// sie getrennt bekommen), und Punkte sagen etwas, was eine Linie
// verschweigt — wo sie dicht liegen, ist man langsam gegangen oder
// stehengeblieben. Genau das ist die Größe, aus der hinterher die
// Leergänge folgen.
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_colors.dart';
import '../../map/map_view/map_view.dart';
import '../tour_track.dart';

/// Wie viele Punkte höchstens gezeichnet werden.
///
/// Eine Dreistundentour im 15-Sekunden-Takt sind 720 Punkte, im
/// 5-Sekunden-Takt über 2000 — und jeder ist ein Widget. Die Grenze
/// greift nicht ins Ergebnis ein: [tourVisits] rechnet weiter mit ALLEN
/// Punkten. Gedünnt wird nur, was das Auge ohnehin nicht auflöst.
const kTourTrackMaxDots = 400;

/// Jeder n-te Punkt, damit höchstens [kTourTrackMaxDots] übrig bleiben —
/// und der LETZTE ist immer dabei.
///
/// Der letzte Punkt ist der, an dem man gerade steht; fiele er der
/// Verdünnung zum Opfer, hinkte die Spur sichtbar hinterher und man
/// zweifelte an der Aufnahme.
List<TourPoint> thinnedTrack(List<TourPoint> points,
    {int max = kTourTrackMaxDots}) {
  if (points.length <= max) return points;
  final step = (points.length / max).ceil();
  final kept = <TourPoint>[
    for (var i = 0; i < points.length; i += step) points[i],
  ];
  if (kept.last != points.last) kept.add(points.last);
  return kept;
}

/// Ein Punkt der Spur. Klein und halbdurchsichtig: Die Spur ist
/// Hintergrund, kein Inhalt — sie darf die Pilze nicht überstrahlen.
class TourTrackDot extends StatelessWidget {
  const TourTrackDot({super.key, this.size = 7});

  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.friendBlue.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          // Ein heller Saum, sonst verschwindet der Punkt über dunklem
          // Wald — dieselbe Not wie beim Halo der Pilz-Symbole.
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.7), width: 1),
        ),
        child: SizedBox.square(dimension: size),
      );
}

/// Die Marker der Spur, fertig für [MapViewMarkers.tourTrack].
List<MapViewMarker> tourTrackMarkers(List<TourPoint> points) => [
      for (final point in thinnedTrack(points))
        MapViewMarker(
          point: LatLng(point.lat, point.lng),
          width: 9,
          height: 9,
          // Mittig, nicht `topCenter`: Ein Spurpunkt IST die Stelle, an
          // der man stand — anders als ein Pilz-Symbol, das darüber
          // hängt.
          alignment: Alignment.center,
          child: const TourTrackDot(),
        ),
    ];
