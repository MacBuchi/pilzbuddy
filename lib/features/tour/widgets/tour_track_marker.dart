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
import '../../../core/widgets/mushroom_icon.dart' show stableSeed;
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

/// Die Farbe der EIGENEN Spur (#340).
///
/// Grün, wie überall in dieser App, wo etwas mir gehört — die
/// Boden-Ellipse an den eigenen Spots, der eigene Standort-Tropfen
/// (#403). Bis 1.125.1 stand hier `friendBlue`, also die Farbe für
/// ANDERE. Solange man allein unterwegs war, fiel das niemandem auf;
/// sobald die Spur eines Buddys danebenliegt, sagt sie das Gegenteil von
/// dem, was sie meint.
const kOwnTrackColor = AppColors.forestGreen;

/// Die Farbe der Spur eines BUDDYS (#340, Stufe 2).
///
/// **Warum nicht einfach [AppColors.friendBlue] für alle.** Dieselbe
/// Farbe für drei Leute an einem Hang beantwortet genau die Frage
/// nicht, für die das Feature da ist: welche Linien hat WER schon
/// abgelaufen. Die Farbe kommt deshalb aus der Nutzer-id, über
/// dasselbe [stableSeed] wie das Aussehen eines Spot-Pilzes — sie
/// bleibt damit über Sitzungen und Geräte hinweg dieselbe.
///
/// **Grün bleibt frei, und zwar durch die SPANNE selbst.** Grün heißt in
/// dieser App „gehört mir" (eigene Spur, Boden-Ellipse an eigenen Spots,
/// eigener Standort-Tropfen). Ein Buddy in Grün sagte das Gegenteil von
/// dem, was er meint — derselbe Fehler, den die eigene Spur bis 1.125.1
/// hatte, nur andersherum.
///
/// Die Töne laufen von 190° über 360° hinaus bis 70°, decken also
/// **[190°, 359°] ∪ [0°, 69°]** ab. [AppColors.forestGreen] liegt bei
/// ~123°, der ganze grüne Sektor damit außerhalb — ohne Sonderfall im
/// Code.
///
/// **Ein erster Entwurf hatte hier zusätzlich einen Sprung über 75°–165°.
/// Der war toter Code**: Die Spanne erreicht diesen Bereich nie. Die
/// Gegenprobe hat ihn entlarvt — ihn zu entfernen ließ den Test grün,
/// was nur heißen kann, dass er nichts tat. Wer [span] oder den
/// Startwert ändert, muss deshalb den Test lesen: Er prüft die Zusage,
/// nicht die Rechnung.
Color buddyTrackColor(String userId) {
  // 190° … 429°, umgebrochen: die Spanne IST die Aussage, siehe oben.
  const span = 240;
  var hue = 190.0 + (stableSeed(userId) % span);
  if (hue >= 360) hue -= 360;
  return HSLColor.fromAHSL(1, hue, 0.62, 0.42).toColor();
}

/// Ein Punkt der Spur. Klein und halbdurchsichtig: Die Spur ist
/// Hintergrund, kein Inhalt — sie darf die Pilze nicht überstrahlen.
class TourTrackDot extends StatelessWidget {
  const TourTrackDot({super.key, this.size = 7, this.color = kOwnTrackColor});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          // Ein heller Saum, sonst verschwindet der Punkt über dunklem
          // Wald — dieselbe Not wie beim Halo der Pilz-Symbole.
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.7), width: 1),
        ),
        child: SizedBox.square(dimension: size),
      );
}

/// Die Spur als einzelne Punkte — die Vorgabe.
///
/// [color] ist vorbelegt mit der eigenen Spur; für die eines Buddys
/// kommt sie von außen (#340).
List<MapViewMarker> tourTrackMarkers(List<TourPoint> points,
        {Color color = kOwnTrackColor}) =>
    [
      for (final point in thinnedTrack(points))
        MapViewMarker(
          point: LatLng(point.lat, point.lng),
          width: 9,
          height: 9,
          // Mittig, nicht `topCenter`: Ein Spurpunkt IST die Stelle, an
          // der man stand — anders als ein Pilz-Symbol, das darüber
          // hängt.
          alignment: Alignment.center,
          child: TourTrackDot(color: color),
        ),
    ];

/// Dieselbe Spur als Linienzug (#340).
///
/// Gedünnt wie die Punkte — 400 Stützstellen lösen mehr auf, als ein Auge
/// unterscheidet, und `tourVisits` rechnet ohnehin mit ALLEN Punkten
/// weiter. Unter zwei Punkten gibt es keine Linie; dann bleibt die Liste
/// leer, statt einen Strich der Länge null zu zeichnen.
List<MapViewPolyline> tourTrackPolyline(List<TourPoint> points,
    {Color color = kOwnTrackColor}) {
  final kept = thinnedTrack(points);
  if (kept.length < 2) return const [];
  return [
    MapViewPolyline(
      points: [for (final p in kept) LatLng(p.lat, p.lng)],
      color: color.withValues(alpha: 0.7),
      width: 4,
    ),
  ];
}
