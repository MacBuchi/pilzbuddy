// Der Tagesverlauf am Spot.
//
// Die Rechnung ist einfach genug, dass sie von Hand nachprüfbar ist —
// und genau deshalb wird sie hier von Hand nachgerechnet. Was NICHT
// einfach ist: was passieren soll, wenn ein Tag fehlt. Eine Summe über
// unvollständige Tage sieht aus wie eine vollständige und ist zu klein.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';

import 'rain_grid_test.dart' show encode;

void main() {
  // Ein Gitter von 2x1 Zellen über 10..14 Grad Ost: Die linke Zelle liegt
  // bei 11 Grad, die rechte bei 13.
  List<int> dayOf(int left, int right) => encode([
        [left, right]
      ]);

  List<({DateTime date, List<int> gzipped})> stackOf(List<int> mmLeft) => [
        for (final (index, mm) in mmLeft.indexed)
          (
            date: DateTime.utc(2026, 7, 21).add(Duration(days: index)),
            gzipped: dayOf(mm, 0),
          ),
      ];

  RainCourse courseOf(List<int> mmLeft, {double lon = 11}) => rainCourseFrom(
        stackOf(mmLeft),
        width: 2,
        height: 1,
        west: 10,
        east: 14,
        north: 55,
        south: 47,
        lat: 51,
        lon: lon,
      );

  test('liest jeden Tag am selben Punkt', () {
    final course = courseOf([1, 2, 3]);
    expect(course.days.map((d) => d.mm), [1, 2, 3]);
    expect(course.days.first.date, DateTime.utc(2026, 7, 21));
    expect(course.newest, DateTime.utc(2026, 7, 23));
  });

  test('sortiert nach Datum, egal wie der Stapel ankommt', () {
    // Das Manifest sortiert, die Platte liefert in Dateisystem-Reihenfolge.
    // Ein Verlauf mit vertauschten Tagen sähe aus wie Wetter.
    final unsorted = stackOf([1, 2, 3]).reversed.toList();
    final course = rainCourseFrom(unsorted,
        width: 2, height: 1, west: 10, east: 14, north: 55, south: 47,
        lat: 51, lon: 11);
    expect(course.days.map((d) => d.mm), [1, 2, 3]);
  });

  group('Summen', () {
    test('addiert das gewünschte Fenster vom jüngsten Tag her', () {
      final course = courseOf([5, 10, 20, 40]);
      expect(course.sumOfLast(1), 40);
      expect(course.sumOfLast(2), 60);
      expect(course.sumOfLast(4), 75);
    });

    test('gibt nichts aus, wenn der Stapel kürzer ist als das Fenster', () {
      // 14 Tage aus 12 gespeicherten Tagen wären eine zu kleine Zahl,
      // der man das nicht ansieht.
      expect(courseOf([1, 2, 3]).sumOfLast(14), isNull);
    });

    test('gibt nichts aus, wenn ein Tag im Fenster keine Messung hat', () {
      // Ein Spot am Rand des Radarverbunds. Lieber keine Zahl als eine,
      // die zu niedrig ist.
      final course = rainCourseFrom(
        [
          (date: DateTime.utc(2026, 7, 21), gzipped: dayOf(10, 0)),
          (date: DateTime.utc(2026, 7, 22), gzipped: dayOf(rainNoData, 0)),
          (date: DateTime.utc(2026, 7, 23), gzipped: dayOf(30, 0)),
        ],
        width: 2, height: 1, west: 10, east: 14, north: 55, south: 47,
        lat: 51, lon: 11,
      );
      expect(course.sumOfLast(1), 30, reason: 'der jüngste Tag allein geht');
      expect(course.sumOfLast(3), isNull);
    });
  });

  group('Wann hat es zuletzt geregnet', () {
    test('zählt vom jüngsten Tag zurück, 0 heißt gestern', () {
      expect(courseOf([20, 0, 0]).daysSinceRain(), 2);
      expect(courseOf([0, 0, 20]).daysSinceRain(), 0);
    });

    test('ignoriert Nieselregen', () {
      // Ein Millimeter macht keinen Boden nass, zählte aber sonst als
      // „gestern hat es geregnet" — genau die Aussage, für die es diesen
      // Verlauf gibt.
      expect(courseOf([20, 1, 1]).daysSinceRain(), 2);
      expect(courseOf([20, 1, 1]).daysSinceRain(threshold: 1), 0);
    });

    test('sagt nichts, wenn im ganzen Verlauf nichts fiel', () {
      expect(courseOf([0, 0, 1]).daysSinceRain(), isNull);
    });
  });

  test('nennt den höchsten Tageswert als Maßstab der Balken', () {
    expect(courseOf([3, 40, 7]).peak, 40);
    expect(courseOf([0, 0, 0]).peak, 0,
        reason: 'ohne Regen darf der Maßstab nicht negativ oder null-teilend '
            'werden — die Balken rechnen damit');
  });

  test('macht aus einer kaputten Tagesdatei einen Tag ohne Wert', () {
    // Nicht einen Fehler: Eine halb geschriebene Datei soll den ganzen
    // Verlauf nicht mitnehmen, sondern nur ihr eigenes Fenster ungültig
    // machen.
    final course = rainCourseFrom(
      [
        (date: DateTime.utc(2026, 7, 21), gzipped: dayOf(10, 0)),
        (date: DateTime.utc(2026, 7, 22), gzipped: const [1, 2, 3]),
      ],
      width: 2, height: 1, west: 10, east: 14, north: 55, south: 47,
      lat: 51, lon: 11,
    );
    expect(course.days.map((d) => d.mm), [10, null]);
    expect(course.sumOfLast(2), isNull);
  });

  test('liest wirklich den Punkt, nicht immer dieselbe Zelle', () {
    // Ohne diese Zusicherung ginge ein Verlauf durch, der jedem Spot in
    // Deutschland dieselben Zahlen zeigt.
    expect(courseOf([7], lon: 11).days.single.mm, 7);
    expect(courseOf([7], lon: 13).days.single.mm, 0);
  });

  test('gibt außerhalb des Gitters keine Werte aus', () {
    expect(courseOf([7], lon: 20).days.single.mm, isNull);
  });
}
