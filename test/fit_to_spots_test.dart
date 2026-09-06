// Die Kamera auf die gefilterte Auswahl (#399).
//
// Geprüft wird die EIGENSCHAFT — passen die Spots hinterher ins Bild? —
// und nicht die Formel. Eine nachgerechnete Formel ginge mit ihr
// gemeinsam kaputt.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/fit_to_spots.dart';
import 'package:pilzbuddy/models/spot.dart';

void main() {
  Spot at(double lat, double lng) =>
      Spot(id: '$lat/$lng', ownerId: 'me', lat: lat, lng: lng);

  /// Ein gewöhnlicher Kartenausschnitt: 400 px breit, 30 m je Pixel
  /// (also gut 12 km im Bild), Zoom 13 in der Zählweise irgendeiner Engine.
  FitToSpots? fit(List<Spot> spots,
          {double currentZoom = 13, double metersPerPixel = 30}) =>
      fitToSpots(
        spots: spots,
        currentZoom: currentZoom,
        currentMetersPerPixel: metersPerPixel,
        viewportWidthPixels: 400,
        minZoom: 3,
        maxZoom: 18,
      );

  test('leere Auswahl ergibt keine Bewegung', () {
    expect(fit(const []), isNull);
  });

  test('die Mitte liegt zwischen den äußersten Spots', () {
    final result = fit([at(48.0, 11.0), at(48.4, 11.6)])!;
    expect(result.center.latitude, closeTo(48.2, 1e-9));
    expect(result.center.longitude, closeTo(11.3, 1e-9));
  });

  test('nach dem Zoom passen alle Spots ins Bild', () {
    // Die eigentliche Zusage. Aus dem Zoom-Delta folgt die neue Auflösung;
    // damit muss die Spanne der Spots in die Fensterbreite passen.
    final spots = [at(48.0, 11.0), at(48.05, 11.2), at(47.95, 11.1)];
    final result = fit(spots, currentZoom: 13, metersPerPixel: 30)!;

    final newMetersPerPixel = 30 / _zoomFactor(result.zoom - 13);
    const metersPerDegreeLng = 111320 * 0.6691; // cos(48°)
    final spanMeters = (11.2 - 11.0) * metersPerDegreeLng;
    expect(spanMeters / newMetersPerPixel, lessThan(400),
        reason: 'die Spots müssen in die 400 px passen');
    expect(spanMeters / newMetersPerPixel, greaterThan(200),
        reason: 'aber nicht verloren in der Fläche stehen');
  });

  test('der Zoom ist ein Delta — dieselbe Lage, andere Zählweise', () {
    // MapLibre und flutter_map zählen Zoomstufen verschieden (512er- vs.
    // 256er-Kacheln). Deshalb darf hier nur der ABSTAND zum aktuellen
    // Zoom aus der Geometrie kommen; die Basis reicht der Aufrufer
    // durch. Zwei Kameras mit gleicher Auflösung, aber verschiedener
    // Zoom-Zahl müssen denselben Sprung ergeben.
    final spots = [at(48.0, 11.0), at(48.1, 11.2)];
    final a = fit(spots, currentZoom: 13)!;
    final b = fit(spots, currentZoom: 14)!;
    expect(b.zoom - a.zoom, closeTo(1.0, 1e-9));
  });

  test('ein einzelner Spot zoomt nicht ins Unendliche', () {
    // Ohne Mindestspanne wäre die Spanne 0 und der Zoom unendlich.
    final result = fit([at(48.0, 11.0)])!;
    expect(result.zoom, lessThanOrEqualTo(18));
    expect(result.zoom.isFinite, isTrue);
    expect(result.center.latitude, closeTo(48.0, 1e-9));
  });

  test('zwei Spots dicht beieinander bleiben unter der Höchststufe', () {
    // 10 m auseinander: Ohne `kFitMinimumSpanMeters` stünde man vor zwei
    // Nadeln ohne Wald ringsum.
    final result = fit([at(48.0, 11.0), at(48.0001, 11.0001)])!;
    expect(result.zoom, lessThanOrEqualTo(18));
    final newMetersPerPixel = 30 / _zoomFactor(result.zoom - 13);
    expect(newMetersPerPixel * 400, greaterThanOrEqualTo(600),
        reason: 'mindestens 600 m im Bild');
  });

  test('die Grenzen der Karte werden eingehalten', () {
    // Ganz Deutschland in ein 400-px-Fenster: Der Rechenweg wollte
    // weiter hinaus, als die Karte erlaubt.
    final result = fit([at(47.3, 5.9), at(55.0, 15.0)], currentZoom: 13)!;
    expect(result.zoom, greaterThanOrEqualTo(3));
    expect(result.zoom, lessThanOrEqualTo(18));
  });

  test('ohne bekannte Auflösung wird zentriert, aber nicht gezoomt', () {
    // Die Karte meldet ihren Maßstab erst im ersten Stillstand. Wer
    // gleich nach dem Start auf das Ampel-Banner tippt, bekäme sonst gar
    // keine Bewegung — „wo" ist die halbe Antwort und immer zu haben.
    for (final unusable in <double?>[null, 0, double.infinity]) {
      final result = fitToSpots(
        spots: [at(48.0, 11.0), at(48.2, 11.4)],
        currentZoom: 13,
        currentMetersPerPixel: unusable,
        viewportWidthPixels: 400,
        minZoom: 3,
        maxZoom: 18,
      )!;
      expect(result.zoom, 13, reason: '$unusable');
      expect(result.center.latitude, closeTo(48.1, 1e-9), reason: '$unusable');
    }
  });
}

/// Um welchen Faktor sich die Auflösung bei diesem Zoom-Delta ändert.
/// `math.pow` und nicht von Hand: Eine selbstgebaute Näherung im Test
/// prüft am Ende die Näherung statt den Code.
double _zoomFactor(double exponent) => math.pow(2, exponent).toDouble();
