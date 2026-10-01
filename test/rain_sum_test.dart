// Regensummen aus dem Tagesstapel (`rain_sum.dart`, seit 1.220.0).
//
// Von Hand nachgerechnet, wie der Verlauf am Spot. Was hier zählt, ist
// vor allem die Lücke: Eine Summe über unvollständige Tage sieht aus wie
// eine vollständige und ist zu klein — und „zu trocken" ist genau die
// Aussage, nach der jemand auf dieser Ebene sucht.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';
import 'package:pilzbuddy/features/map/rain_sum.dart';

import 'rain_grid_test.dart' show encode;

void main() {
  // 2×1 Zellen; je Tag ein Wertepaar (links, rechts), null = keine Daten.
  RainStackData stackOf(List<(int?, int?)> days,
          {DateTime? start, List<int> skip = const []}) =>
      RainStackData(
        info: const RainStackInfo(
            width: 2,
            height: 1,
            west: 10,
            east: 14,
            north: 55,
            south: 47,
            days: []),
        days: [
          for (final (i, (left, right)) in days.indexed)
            if (!skip.contains(i))
              (
                date: (start ?? DateTime(2026, 9, 1)).copyWith(
                    day: (start ?? DateTime(2026, 9, 1)).day + i),
                gzipped: encode([
                  [left ?? rainNoData, right ?? rainNoData]
                ]),
              ),
        ],
      );

  test('summiert die jüngsten Tage je Zelle', () {
    final stack = stackOf([(9, 9), (1, 2), (3, 4), (5, 6)]);
    final sum = rainSumGrid(stack, 3)!;
    expect(sum.values, [1 + 3 + 5, 2 + 4 + 6],
        reason: 'der älteste Tag (9 mm) liegt außerhalb des Fensters');
    expect(sum.width, 2);
    expect(sum.west, 10);
    expect(sum.east, 14);
    expect(sum.measured, DateTime(2026, 9, 4),
        reason: 'Stand ist der jüngste Tag, nicht heute');
  });

  test('zu wenig Tage: keine Summe statt einer zu kleinen', () {
    expect(rainSumGrid(stackOf([(1, 1), (1, 1)]), 3), isNull);
  });

  test('eine Lücke im Fenster: keine Summe', () {
    // Tag 3 von 5 fehlt — vier Tage liegen, aber nicht am Stück.
    final stack = stackOf([(1, 1), (1, 1), (1, 1), (1, 1), (1, 1)],
        skip: [2]);
    expect(rainStackRunLength(stack), 2);
    expect(rainSumGrid(stack, 3), isNull);
    expect(rainSumGrid(stack, 2)!.values, [2, 2],
        reason: 'die beiden jüngsten Tage liegen am Stück');
  });

  test('fehlt einer Zelle ein Tag, hat sie keinen Wert', () {
    final sum = rainSumGrid(stackOf([(4, 4), (null, 5), (6, 6)]), 3)!;
    expect(sum.values, [rainNoData, 15],
        reason: 'eine Teilsumme wäre eine erfundene Zahl');
    expect(sum.mmAt(51, 11), isNull);
    expect(sum.mmAt(51, 13), 15);
  });

  test('gekappt beim Quantisierungsdeckel', () {
    final sum = rainSumGrid(stackOf([(200, 1), (200, 1)]), 2)!;
    expect(sum.values.first, rainMaxMm);
    expect(sum.values.last, 2);
  });

  test('zählt über die Zeitumstellung hinweg nach Datum', () {
    // 25. Oktober 2026: Ende der Sommerzeit in Mitteleuropa — ein Tag
    // mit 25 Stunden. Lokale Mitternacht minus 24 h träfe den Vortag
    // um 23 Uhr; gezählt wird deshalb über das Datum.
    final stack = stackOf([(1, 1), (1, 1), (1, 1)],
        start: DateTime(2026, 10, 24));
    expect(rainStackRunLength(stack), 3);
    expect(rainSumGrid(stack, 3)!.values, [3, 3]);
  });

  test('leerer Stapel', () {
    expect(rainStackRunLength(stackOf(const [])), 0);
    expect(rainSumGrid(stackOf(const []), 1), isNull);
  });

  test('die untere Fläche schweigt, wo die obere etwas sagt', () {
    // Unten 2×1 über 10..14° O (Zellmitten 11° und 13°), oben 1×1 über
    // 12..14° O mit Wert — deckt also nur die rechte Zelle.
    final lower = rainSumGrid(stackOf([(5, 5)]), 1)!;
    RainGrid upperWith(int value) => RainGrid.decode(
          encode([
            [value]
          ]),
          width: 1,
          height: 1,
          west: 12,
          east: 14,
          north: 55,
          south: 47,
          measured: DateTime(2026, 9, 1),
        );
    expect(maskCovered(lower, upperWith(9)).values, [5, rainNoData]);
    expect(maskCovered(lower, upperWith(rainNoData)).values, [5, 5],
        reason: 'eine obere Zelle ohne Daten deckt nichts ab');
    expect(maskCovered(lower, null).values, [5, 5]);
  });
}
