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

  group('bearingDegrees und compassPoint (#373)', () {
    // 51,16 N: ein Breitengrad ~111,2 km, ein Längengrad ~69,7 km. Ohne
    // den cos-Faktor auf die Länge zeigte „östlich" hier um rund ein
    // Drittel daneben — deshalb ist genau das der Ost-Test.
    const lat = 51.1634;
    const lng = 10.4477;

    test('die vier Haupthimmelsrichtungen stimmen', () {
      expect(compassPoint(bearingDegrees(lat, lng, lat + 0.001, lng)),
          'nördlich');
      expect(compassPoint(bearingDegrees(lat, lng, lat, lng + 0.001)),
          'östlich');
      expect(compassPoint(bearingDegrees(lat, lng, lat - 0.001, lng)),
          'südlich');
      expect(compassPoint(bearingDegrees(lat, lng, lat, lng - 0.001)),
          'westlich');
    });

    test('ein echter Nordost-Versatz liest sich als nordöstlich', () {
      // Gleich weit nach Norden und nach Osten — in METERN, nicht in
      // Grad. Wer die Grade gleich setzt, bekommt auf 51° N einen Kurs
      // von 32° und damit die falsche Richtung.
      final north = 0.0001; // ~11,1 m
      final east = 0.0001 * 111.2 / 69.7; // dieselben ~11,1 m
      expect(compassPoint(bearingDegrees(lat, lng, lat + north, lng + east)),
          'nordöstlich');
    });

    test('die Sektorgrenzen liegen bei 22,5°', () {
      expect(compassPoint(22.4), 'nördlich');
      expect(compassPoint(22.6), 'nordöstlich');
      expect(compassPoint(337.6), 'nördlich');
      expect(compassPoint(360), 'nördlich');
      expect(compassPoint(0), 'nördlich');
    });

    test('acht Richtungen, nicht sechzehn', () {
      final all = {
        for (var deg = 0; deg < 360; deg += 5) compassPoint(deg.toDouble())
      };
      expect(all, hasLength(8),
          reason: '„nordnordöstlich" behauptet eine Auflösung, die ein '
              'Kurswinkel über zwölf Meter nicht hat');
    });
  });

  group('formatMeters', () {
    test('unter einem Kilometer ganze Meter', () {
      expect(formatMeters(14.4), '14 m');
      expect(formatMeters(999), '999 m');
    });

    test('ab einem Kilometer mit deutschem Dezimalkomma', () {
      expect(formatMeters(1000), '1,0 km');
      expect(formatMeters(1234), '1,2 km');
    });
  });
}
