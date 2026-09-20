// Die Farbe der Spur eines Buddys (#340, Stufe 2).
//
// Drei Zusagen, und jede davon ist eine Aussage über die Karte:
// dieselbe Person immer dieselbe Farbe, verschiedene Personen
// unterscheidbar, und niemand in Grün — Grün heißt in dieser App
// „gehört mir".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/tour/widgets/tour_track_marker.dart';

void main() {
  double hueOf(Color c) => HSLColor.fromColor(c).hue;

  test('Dieselbe Nutzer-id gibt immer dieselbe Farbe', () {
    // Sonst wechselte die Zuordnung mit jedem App-Start, und „die blaue
    // Linie ist Lilli" hielte keine Stunde.
    expect(buddyTrackColor('abc-123'), buddyTrackColor('abc-123'));
  });

  test('Verschiedene Buddys sind unterscheidbar', () {
    // Der ganze Zweck: Drei Leute an einem Hang, und man sieht, wer
    // welche Linie gelaufen ist.
    final hues = <double>{
      for (var i = 0; i < 12; i++) hueOf(buddyTrackColor('buddy-$i')),
    };
    expect(hues.length, greaterThan(8),
        reason: 'zwölf ids dürfen nicht auf eine Handvoll Töne fallen');
  });

  test('Kein Buddy landet im grünen Bereich', () {
    // Grün ist die Besitzfarbe — eigene Spur, Boden-Ellipse an eigenen
    // Spots, eigener Standort-Tropfen. Ein Buddy in Grün sagte das
    // Gegenteil von dem, was er meint; genau diesen Fehler hatte die
    // EIGENE Spur bis 1.125.1, nur andersherum.
    final ownHue = hueOf(AppColors.forestGreen);
    for (var i = 0; i < 200; i++) {
      final hue = hueOf(buddyTrackColor('user-$i'));
      expect(hue > 75 && hue < 165, isFalse,
          reason: 'user-$i liegt bei ${hue.round()}° im grünen Sektor');
      // Und mit Abstand zum konkreten Markengrün.
      expect((hue - ownHue).abs(), greaterThan(20),
          reason: 'user-$i liegt zu nah an forestGreen (${ownHue.round()}°)');
    }
  });
}
