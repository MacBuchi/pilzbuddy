// Die Kamerafahrt ist der Messhaken des Direktvergleichs (Migrations-
// stufe 7): dieselbe Choreographie auf beiden Engines, deterministisch —
// nur dann sind Perfetto-Frame-Zahlen vergleichbar. Hier wird die pure
// Choreographie geprüft; das Abfahren am Gerät ist Sache des FABs.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/map_view/camera_tour.dart';

void main() {
  test('rund eine Minute lang — lang genug für stabile Perzentile, kurz '
      'genug für einen Messlauf je Engine', () {
    final total = cameraTourSteps.fold(
        Duration.zero, (sum, step) => sum + step.hold);
    expect(total, greaterThanOrEqualTo(const Duration(seconds: 50)));
    expect(total, lessThanOrEqualTo(const Duration(seconds: 70)));
  });

  test('bleibt in den Zoomgrenzen der Karte (3–19)', () {
    for (final step in cameraTourSteps) {
      expect(step.zoom, inInclusiveRange(3, 19),
          reason: 'Schritt „${step.label}" verließe die Karte.');
    }
  });

  test('bleibt im DACH-Ausschnitt der Übersichtskarte', () {
    // bbox des overview-Extracts: 5.5,45.5 – 17.5,55.5 (pubspec.yaml).
    for (final step in cameraTourSteps) {
      expect(step.center.longitude, inInclusiveRange(5.5, 17.5));
      expect(step.center.latitude, inInclusiveRange(45.5, 55.5));
    }
  });

  test('enthält Wischen auf hoher Zoomstufe — die Last, die den ANR '
      'auslöste, nicht nur Sprünge', () {
    var consecutiveHighZoomMoves = 0;
    var maxRun = 0;
    LatLng? previous;
    for (final step in cameraTourSteps) {
      if (step.zoom >= 14 && previous != null) {
        consecutiveHighZoomMoves++;
        if (consecutiveHighZoomMoves > maxRun) {
          maxRun = consecutiveHighZoomMoves;
        }
      } else {
        consecutiveHighZoomMoves = 0;
      }
      previous = step.center;
    }
    expect(maxRun, greaterThanOrEqualTo(3),
        reason: 'Mindestens drei aufeinanderfolgende Bewegungen bei '
            'Zoom ≥ 14 — dort rendert die Detailkarte, dort saß #151.');
  });
}
