// Die Geometrie des Wetterdiagramms — pur, ohne ein einziges Widget.
//
// Der Kern der Betreiber-Vorgabe ist eine Invariante: Balkenmitte i ==
// Linienstützpunkt i, beide „um 12 Uhr" ihres Tages. Sie wird hier am
// Painter geprüft, nicht an Pixeln — ein Screenshot bewiese die Deckung
// nur für eine Breite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/core/axis_scale.dart';
import 'package:pilzbuddy/features/spots/widgets/weather_chart.dart';

void main() {
  group('temperatureAxis', () {
    test('umfasst die Werte mit runden Grenzen auf dem Schritt', () {
      final axis = temperatureAxis(8.2, 23.7);
      expect(axis.low, lessThanOrEqualTo(8.2));
      expect(axis.high, greaterThanOrEqualTo(23.7));
      expect(axis.low % axis.step, 0);
      expect(axis.high % axis.step, 0);
      expect((axis.high - axis.low) / axis.step, lessThanOrEqualTo(5),
          reason: 'mehr Beschriftungen passen nicht auf ~80 Pixel');
    });

    test('kann Frost — negative Grenzen, 0 liegt auf dem Raster', () {
      final axis = temperatureAxis(-3.4, 22.1);
      expect(axis.low, lessThanOrEqualTo(-3.4));
      expect(axis.low, lessThan(0));
      expect(axis.low % axis.step, 0,
          reason: 'auch eine negative Grenze muss auf dem Schritt liegen');
      // 0 ist Vielfaches jedes Schritts: Die Frostgrenze fällt damit
      // immer auf eine Beschriftungshöhe.
      expect((0 - axis.low) % axis.step, 0);
    });

    test('eine Spanne von null öffnet sich, statt durch null zu teilen',
        () {
      final axis = temperatureAxis(15, 15);
      expect(axis.high, greaterThan(axis.low));
    });
  });

  test('alignedTrack ordnet über das Datum zu, nie über den Index', () {
    // Stapel und Stationstabelle werden getrennt veröffentlicht und
    // dürfen um einen Tag auseinanderliegen — ein Index-Join wäre dann
    // still um einen Tag verschoben.
    final chartDays = [
      DateTime.utc(2026, 8, 1),
      DateTime.utc(2026, 8, 2),
      DateTime.utc(2026, 8, 3),
    ];
    final trackDays = [
      DateTime.utc(2026, 8, 2),
      DateTime.utc(2026, 8, 3),
      DateTime.utc(2026, 8, 4),
    ];
    expect(alignedTrack(chartDays, trackDays, [1, 2, 3]), [null, 1, 2]);
  });

  test('lineSegments bricht an Lücken, statt sie zu überbrücken', () {
    final segments = lineSegments([1, null, 2, 3]);
    expect(segments, hasLength(2));
    expect(segments.first.single, (index: 0, value: 1.0));
    expect(segments.last.map((p) => p.index), [2, 3]);
    expect(lineSegments([null, null]), isEmpty);
  });

  group('endLabel', () {
    final now = DateTime(2026, 8, 4, 14, 30);

    test('nennt gestern „gestern"', () {
      expect(endLabel(DateTime.utc(2026, 8, 3), now), 'gestern, 3.8.');
    });

    test('nennt einen alten Stand beim Datum — nicht „gestern"', () {
      // Fünf Tage ohne Empfang: Das Datum ist dann genau die Auskunft,
      // die zählt. Ein „gestern" über altem Stand wäre gelogen.
      expect(endLabel(DateTime.utc(2026, 7, 30), now), '30.7.');
    });
  });

  group('Painter-Geometrie', () {
    const size = Size(340, 112);
    final axis = temperatureAxis(8, 24);

    WeatherChartPainter painterOf(
            {List<int?>? mm,
            ({double low, double high, double step})? withAxis}) =>
        WeatherChartPainter(
          mm: mm ?? List<int?>.filled(14, 3),
          weekdays: List.filled(14, 'Mo'),
          startLabel: '21.7.',
          endLabel: 'gestern, 3.8.',
          mmStep: 1,
          mmMax: 5,
          axis: withAxis,
          soil: null,
          airMax: null,
          airMin: null,
          barColor: AppColors.friendBlue,
          hintColor: Colors.grey,
          textColor: Colors.black87,
        );

    test('Tag i hat seine Mitte bei (i + 0,5)/14 der Plotbreite', () {
      final painter = painterOf(withAxis: axis);
      final plot = painter.plotArea(size);
      for (final index in [0, 6, 13]) {
        expect(painter.centerX(index, size),
            closeTo(plot.left + (index + 0.5) * plot.width / 14, 0.001));
      }
    });

    test('Balkenmitte i == Linienstützpunkt i', () {
      // DIE Invariante des Diagramms: „jeder Balken um 12 Uhr gezeichnet",
      // die Linie durch dieselben Mitten.
      final painter = painterOf(withAxis: axis);
      for (final index in [0, 5, 13]) {
        expect(painter.barRect(index, size).center.dx,
            closeTo(painter.linePoint(index, 15, size).dx, 0.001));
      }
    });

    test('die °C-Achse spannt den Plot auf: low unten, high oben', () {
      // Mit Frost, also einer Untergrenze ≠ 0: Eine Achse, die den
      // Nullpunkt vergisst und stumpf `wert / spanne` rechnet, sieht
      // bei low == 0 zufällig richtig aus — genau der Fall, der die
      // erste Fassung dieses Tests wertlos machte (Mutation überlebte).
      final frost = temperatureAxis(-3, 24);
      expect(frost.low, isNot(0));
      final painter = painterOf(withAxis: frost);
      final plot = painter.plotArea(size);
      expect(
          painter.temperatureY(frost.low, size), closeTo(plot.bottom, 0.001));
      expect(painter.temperatureY(frost.high, size), closeTo(plot.top, 0.001));
      expect(painter.temperatureY(frost.low, size),
          greaterThan(painter.temperatureY(frost.high, size)),
          reason: 'wärmer ist oben');
    });

    test('ein Tag ohne Messung bekommt einen Stummel, keinen Balken', () {
      final painter = painterOf(mm: [null, 0, 4, ...List.filled(11, 2)],
          withAxis: axis);
      expect(painter.barRect(0, size).height, 2);
      expect(painter.barRect(1, size).height, 2,
          reason: 'trocken ist ein Messwert, aber kein Balken');
      expect(painter.barRect(2, size).height, greaterThan(10));
    });

    test('ohne Temperatur rückt der Plot nach links — keine leere Spalte',
        () {
      final without = painterOf();
      final with_ = painterOf(withAxis: axis);
      expect(without.plotArea(size).left, lessThan(with_.plotArea(size).left));
    });
  });
}
