// Die eine Entfernungsrechnung des Projekts. Sie trägt zwei Maßstäbe:
// Dutzende Kilometer zur nächsten Wetterstation und die 20 m zwischen zwei
// Spots (#215). Beide werden hier geprüft — der Kilometer-Test allein hat
// eine Toleranz von ±2 km und sagt auf Metermaßstab gar nichts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/geo.dart';

void main() {
  group('distanceKm', () {
    test('liegt an bekannten Paaren richtig', () {
      // Berlin–Potsdam (~27 km Luftlinie) und München–Augsburg (~57 km):
      // grob genug, um vertauschte Achsen oder eine fehlende
      // Breitengrad-Stauchung sofort zu sehen.
      expect(distanceKm(52.52, 13.405, 52.396, 13.058), closeTo(27, 2));
      expect(distanceKm(48.137, 11.575, 48.371, 10.898), closeTo(57, 3));
    });
  });

  group('distanceMeters', () {
    test('stimmt auf Metermaßstab — Nord/Süd', () {
      // 20 m Nord/Süd sind 20/111200 Grad Breite. Diese Richtung ist die
      // einfache: keine Stauchung, reine Umrechnung.
      const north = 20 / 111200;
      expect(distanceMeters(51.0, 10.0, 51.0 + north, 10.0), closeTo(20, 0.1));
    });

    test('stimmt auf Metermaßstab — Ost/West, mit Breitengrad-Stauchung', () {
      // Der Fall, der eine fehlende cos-Korrektur auffliegen lässt: Auf
      // 51° N ist ein Längengrad nur noch rund 63 % so lang wie ein
      // Breitengrad. Ohne den Faktor käme hier etwa 32 m heraus.
      const east = 20 / 111200 / 0.6293;
      expect(distanceMeters(51.0, 10.0, 51.0, 10.0 + east), closeTo(20, 0.5));
    });

    test('ist symmetrisch und null bei gleichem Punkt', () {
      expect(distanceMeters(51.0, 10.0, 51.0, 10.0), 0);
      expect(distanceMeters(51.0, 10.0, 51.001, 10.002),
          closeTo(distanceMeters(51.001, 10.002, 51.0, 10.0), 1e-9));
    });

    test('ist tausendmal der Kilometerwert', () {
      expect(distanceMeters(52.52, 13.405, 52.396, 13.058),
          closeTo(distanceKm(52.52, 13.405, 52.396, 13.058) * 1000, 1e-6));
    });
  });
}
