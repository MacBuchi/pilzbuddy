// Der Tagesverlauf am Spot.
//
// Die Rechnung ist einfach genug, dass sie von Hand nachprüfbar ist —
// und genau deshalb wird sie hier von Hand nachgerechnet. Was NICHT
// einfach ist: was passieren soll, wenn ein Tag fehlt. Eine Summe über
// unvollständige Tage sieht aus wie eine vollständige und ist zu klein.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';

import 'package:pilzbuddy/data/rain_grid_repository.dart';
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

  group('Radar zuerst, Modell als Rückfall (#612)', () {
    // Zwei Stapel mit verschiedener Geometrie: das „Radar" 2×1 über
    // 10..14° O (Zelle links 11°, rechts 13°), das „Modell" 1×1 über
    // 8..16° O — es deckt also auch 9° O, wo das Radar nichts hat.
    RainStackData stack(List<int?> radarLeft, {int width = 2,
        double west = 10, double east = 14,
        RainStackKind kind = RainStackKind.radar}) => RainStackData(
          kind: kind,
          info: RainStackInfo(
              width: width, height: 1, west: west, east: east,
              north: 55, south: 47, days: const []),
          days: [
            for (final (i, mm) in radarLeft.indexed)
              (
                date: DateTime.utc(2026, 7, 21).add(Duration(days: i)),
                gzipped: encode([
                  [for (var c = 0; c < width; c++) mm ?? 255]
                ]),
              ),
          ],
        );
    final points = [(lat: 51.0, lon: 11.0), (lat: 51.0, lon: 9.0)];

    test('wo das Radar einen Wert hat, gewinnt es; sonst das Modell', () {
      final radar = stack([5, null, 7]);
      final model = stack([1, 2, 3, 4],
          width: 1, west: 8, east: 16, kind: RainStackKind.model);
      final courses = rainCoursesFromStacks([radar, model], points: points);
      final inside = courses[0].days;
      expect([for (final d in inside) d.mm], [5, 2, 7, 4],
          reason: 'Tag 2 fehlt im Radar (255), Tag 4 kennt nur das Modell');
      expect([for (final d in inside) d.source], [
        RainSource.radar, RainSource.model, RainSource.radar, RainSource.model,
      ]);
      expect(courses[0].modelDays, 2);
      expect(courses[0].measuredDays, 4);
      // Der Punkt bei 9° O liegt außerhalb des Radars — alles Modell.
      final outside = courses[1].days;
      expect([for (final d in outside) d.mm], [1, 2, 3, 4]);
      expect(outside.every((d) => d.source == RainSource.model), isTrue);
      expect(courses[1].modelDays, 4);
    });

    test('ein Stapel allein ist der alte Weg, Quelle Radar', () {
      final radar = stack([5, null, 7]);
      final only = rainCoursesFromStacks([radar], points: points);
      final direct = rainCoursesFrom(radar.days,
          width: 2, height: 1, west: 10, east: 14, north: 55, south: 47,
          points: points);
      expect([for (final d in only[0].days) d.mm],
          [for (final d in direct[0].days) d.mm]);
      expect(only[0].modelDays, 0);
      expect(only[1].days.every((d) => d.mm == null), isTrue);
    });

    test('das Modell allein heißt trotzdem Modell — die Herkunft hängt am '
        'Stapel, nicht an seiner Position', () {
      final model = stack([1, 2],
          width: 1, west: 8, east: 16, kind: RainStackKind.model);
      final course = rainCoursesFromStacks([model], points: points).first;
      expect(course.days.every((d) => d.source == RainSource.model), isTrue);
      expect(course.modelDays, 2);
    });

    test('ohne Stapel leere Verläufe, ein Tag ohne beide bleibt leer', () {
      expect(rainCoursesFromStacks(const [], points: points),
          everyElement(predicate<RainCourse>((c) => c.isEmpty)));
      final radar = stack([null]);
      final model = stack([null],
          width: 1, west: 8, east: 16, kind: RainStackKind.model);
      final course = rainCoursesFromStacks([radar, model], points: points).first;
      expect(course.days.single.mm, isNull);
      expect(course.modelDays, 0);
    });
  });

  group('Alpenstapel zuerst, dann Radar, dann Modell (#646)', () {
    // Alles 2×1 über 10..14° O: links (11°) liegt der Alpenstapel, rechts
    // (13°) ist er leer — wie im deutschen Landesinneren, wo er 255
    // trägt und das Radar antworten soll.
    List<({DateTime date, List<int> gzipped})> days(
            List<(int, int)> values) =>
        [
          for (final (i, (left, right)) in values.indexed)
            (
              date: DateTime.utc(2026, 9, 1).add(Duration(days: i)),
              gzipped: encode([
                [left, right]
              ]),
            ),
        ];
    RainStackData stackOf(RainStackKind kind, List<(int, int)> values,
            {List<(int, int)> origins = const []}) =>
        RainStackData(
          kind: kind,
          info: const RainStackInfo(
              width: 2, height: 1, west: 10, east: 14, north: 55,
              south: 47, days: []),
          days: days(values),
          origins: days(origins),
        );
    final points = [(lat: 51.0, lon: 11.0), (lat: 51.0, lon: 13.0)];

    test('der Alpenstapel gewinnt, wo er etwas sagt; sonst das Radar', () {
      final alps = stackOf(RainStackKind.alps, [(9, 255), (8, 255)],
          origins: [
            (AlpsOrigin.inca | AlpsOrigin.radar, 0),
            (AlpsOrigin.inca, 0),
          ]);
      final radar = stackOf(RainStackKind.radar, [(1, 2), (1, 3)]);
      final model = stackOf(RainStackKind.model, [(5, 5), (5, 5)]);
      final courses =
          rainCoursesFromStacks([alps, radar, model], points: points);

      final border = courses[0];
      expect([for (final d in border.days) d.mm], [9, 8]);
      expect(border.days.every((d) => d.source == RainSource.alps), isTrue);
      expect([for (final d in border.days) d.origin],
          [AlpsOrigin.inca | AlpsOrigin.radar, AlpsOrigin.inca],
          reason: 'die Herkunft wird an derselben Zelle gelesen wie der '
              'Wert');
      expect(border.alpsDays, 2);
      expect(border.alpsOrigin, AlpsOrigin.inca | AlpsOrigin.radar);

      final inland = courses[1];
      expect([for (final d in inland.days) d.mm], [2, 3],
          reason: 'im Landesinneren ist der Alpenstapel leer, das Radar '
              'antwortet — nicht das Modell');
      expect(inland.days.every((d) => d.source == RainSource.radar), isTrue);
      expect(inland.alpsDays, 0);
    });

    test('ohne Herkunftsdatei gilt die Zahl trotzdem, nur ohne Bits', () {
      final alps = stackOf(RainStackKind.alps, [(9, 255)]);
      final course =
          rainCoursesFromStacks([alps], points: points).first.days.single;
      expect(course.mm, 9);
      expect(course.source, RainSource.alps);
      expect(course.origin, 0);
    });

    test('die Bits sind dieselben wie im Werkzeug', () {
      // `tool/alps_rain.py` schreibt sie, die App liest sie. Zwei Listen
      // derselben Zahlen laufen still auseinander, wenn niemand beide
      // liest.
      final tool = File('tool/alps_rain.py').readAsStringSync();
      final bits = RegExp(r'SOURCE_BITS = \{([^}]*)\}').firstMatch(tool)!;
      final pairs = {
        for (final m in RegExp(r'"(\w+)": (\d+)').allMatches(bits[1]!))
          m[1]!: int.parse(m[2]!),
      };
      expect(pairs, {
        'inca': AlpsOrigin.inca,
        'rprelimd': AlpsOrigin.rprelimd,
        'dpc': AlpsOrigin.dpc,
        'radar': AlpsOrigin.radar,
        'model': AlpsOrigin.model,
      });
    });
  });

  group('Mehrere Punkte in einem Durchgang (#277-Vorarbeit)', () {
    // Der Anlass: rainCourseFrom packte je Punkt ALLE Tage vollständig
    // aus, um je Tag ein Byte zu lesen. Gemessen am 2026-08-23 waren 19
    // Spots damit 494 Dekodierungen und knapp drei Sekunden
    // (docs/map-performance.md). Gebündelt sind es 26.

    test('liefert Punkt für Punkt dasselbe wie der Einzelweg', () {
      // Die eigentliche Zusicherung: Der schnelle Weg darf nichts
      // anderes ausrechnen als der langsame. Linke Zelle bei 11 Grad,
      // rechte bei 13 — zwei Punkte, die verschiedene Zellen treffen.
      final stack = [
        for (final (index, mm) in [(0, 5), (1, 9), (2, 0)].indexed)
          (
            date: DateTime.utc(2026, 7, 21).add(Duration(days: index)),
            gzipped: encode([
              [mm.$1, mm.$2]
            ]),
          ),
      ];
      const points = [(lat: 51.0, lon: 11.0), (lat: 51.0, lon: 13.0)];

      final batched = rainCoursesFrom(stack,
          width: 2,
          height: 1,
          west: 10,
          east: 14,
          north: 55,
          south: 47,
          points: points);

      for (final (index, point) in points.indexed) {
        final single = rainCourseFrom(stack,
            width: 2,
            height: 1,
            west: 10,
            east: 14,
            north: 55,
            south: 47,
            lat: point.lat,
            lon: point.lon);
        expect(batched[index].days.map((d) => d.mm),
            single.days.map((d) => d.mm),
            reason: 'Punkt $index weicht vom Einzelweg ab');
        expect(batched[index].days.map((d) => d.date),
            single.days.map((d) => d.date));
      }
      // Und die beiden Punkte sehen wirklich Verschiedenes — sonst
      // bewiese der Vergleich oben nichts.
      expect(batched[0].days.map((d) => d.mm), [0, 1, 2]);
      expect(batched[1].days.map((d) => d.mm), [5, 9, 0]);
    });

    test('die Reihenfolge der Rückgabe folgt den Punkten, nicht dem Gitter',
        () {
      final stack = stackOf([7]);
      final courses = rainCoursesFrom(stack,
          width: 2,
          height: 1,
          west: 10,
          east: 14,
          north: 55,
          south: 47,
          // Rechts vor links übergeben.
          points: const [(lat: 51.0, lon: 13.0), (lat: 51.0, lon: 11.0)]);
      expect(courses[0].days.single.mm, 0, reason: 'rechte Zelle zuerst');
      expect(courses[1].days.single.mm, 7);
    });

    test('ein kaputter Tag nimmt ALLE Punkte gleich mit', () {
      // Vorher fing jeder Punkt seinen eigenen Fehler. Jetzt scheitert
      // die Dekodierung einmal — das darf nicht dazu führen, dass ein
      // Punkt einen Wert bekommt und ein anderer nicht.
      final stack = [
        (date: DateTime.utc(2026, 7, 21), gzipped: encode([
          [4, 8]
        ])),
        (date: DateTime.utc(2026, 7, 22), gzipped: const <int>[1, 2, 3]),
      ];
      final courses = rainCoursesFrom(stack,
          width: 2,
          height: 1,
          west: 10,
          east: 14,
          north: 55,
          south: 47,
          points: const [(lat: 51.0, lon: 11.0), (lat: 51.0, lon: 13.0)]);
      expect(courses[0].days.map((d) => d.mm), [4, null]);
      expect(courses[1].days.map((d) => d.mm), [8, null]);
    });

    test('ohne Punkte kommt nichts zurück, und es knallt nicht', () {
      expect(
          rainCoursesFrom(stackOf([1, 2]),
              width: 2,
              height: 1,
              west: 10,
              east: 14,
              north: 55,
              south: 47,
              points: const []),
          isEmpty);
    });
  });

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
