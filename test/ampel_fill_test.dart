// Die Pilzwetter-RECHNUNG (Ampel-Vorschau): die Stufe je Zelle, gegen
// das MODELL selbst geprüft — das Gitter rechnet je Zelle dieselbe
// Reihe, die auch `ampelRainFactor`/`ampelLevelOf` bekämen; jede
// Abweichung (Gewichtung, Sättigung, Schwellen) reißt den Vergleich.
//
// Seit 1.76.0 malt hier nichts mehr: Die Ampel färbt nur noch Waldwaben
// (`forestAmpelFillPng`, siehe `forest_ampel_fill_test.dart`). Geprüft
// wird deshalb das Stufen-Gitter, nicht mehr das Bild.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/ampel/ampel_fill.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/map/spot_weather.dart';

import 'rain_grid_test.dart' show encode;

/// Ein Stapel: 3 Spalten × 1 Zeile, je Zelle die eigene Regenreihe
/// (Index 0 = ältester Tag). Kürzere Reihen als [days] füllen vorn mit 0.
RainStackData stackOf(List<List<int>> mmPerCellOldestFirst,
    {int days = 26}) {
  return RainStackData(
    info: RainStackInfo(
      width: mmPerCellOldestFirst.length,
      height: 1,
      west: 10,
      east: 13,
      north: 52,
      south: 50,
      days: const [],
    ),
    days: [
      for (var i = 0; i < days; i++)
        (
          date: DateTime.utc(2026, 7, 1).add(Duration(days: i)),
          gzipped: encode([
            [
              for (final series in mmPerCellOldestFirst)
                i < days - series.length
                    ? 0
                    : series[i - (days - series.length)],
            ]
          ]),
        ),
    ],
  );
}

/// Die Stationstabelle über den echten Parser — eine Luftstation mit
/// konstantem Tagesmittel [meanC] (Max/Min symmetrisch darum).
WeatherTable tableOf({double meanC = 13, double lat = 51, double lon = 11}) {
  String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  final start = DateTime.utc(2026, 7, 7);
  final json = {
    'days': [
      for (var i = 0; i < 20; i++) iso(start.add(Duration(days: i))),
    ],
    'stations': [
      {
        'id': 1,
        'lat': lat,
        'lon': lon,
        'h': 300,
        'name': 'Teststation',
        'max': [for (var i = 0; i < 20; i++) meanC + 3],
        'min': [for (var i = 0; i < 20; i++) meanC - 3],
      },
    ],
    'soil': const [],
  };
  return weatherTableFrom(
      GZipEncoder().encode(utf8.encode(jsonEncode(json)))!)!;
}

void main() {
  /// Die Stufe der Zelle [x] in der einzigen Zeile — `null` heißt
  /// „keine Aussage" (zu wenige Regentage, keine Station in Reichweite).
  AmpelLevel? levelOf(AmpelLevelGrid grid, int x) => grid.levelAtCell(0, x);

  test('je Zelle exakt die Stufe, die das Modell für ihre Reihe nennt',
      () {
    // Drei Zellen: satt (5 mm/Tag → Faktor 1), verhalten (1 mm/Tag →
    // 26/87 ≈ 0,30), trocken (0). Temperatur 13 °C → Faktor 1.
    final series = [
      List.filled(26, 5),
      List.filled(26, 1),
      List.filled(26, 0),
    ];
    final grid = ampelLevelsFrom(stackOf(series), tableOf())!;
    expect(grid.width, 3);

    for (final (x, cell) in series.indexed) {
      // Der Maßstab ist das MODELL selbst: dieselbe Reihe, Vortag
      // zuerst, durch dieselben Funktionen.
      final expected = ampelLevelOf(ampelRainFactor(
          [for (final mm in cell.reversed) mm.toDouble()]));
      expect(levelOf(grid, x), expected, reason: 'Zelle $x');
    }
    expect(grid.newest, DateTime.utc(2026, 7, 26));
    expect(grid.west, 10);
    expect(grid.south, 50);
  });

  test('die Altersgewichtung zählt: gleicher Regen, anderes Alter, '
      'andere Stufe', () {
    // Beide Zellen bekommen 8×8 mm — Zelle 0 in den JÜNGSTEN acht
    // Tagen, Zelle 1 in den ältesten. Wer die Gewichtung umdreht oder
    // weglässt, malt beide gleich.
    final young = [...List.filled(18, 0), ...List.filled(8, 8)];
    final old = [...List.filled(8, 8), ...List.filled(18, 0)];
    final grid = ampelLevelsFrom(stackOf([young, old]), tableOf())!;
    final expectedYoung = ampelLevelOf(ampelRainFactor(
        [for (final mm in young.reversed) mm.toDouble()]));
    final expectedOld = ampelLevelOf(ampelRainFactor(
        [for (final mm in old.reversed) mm.toDouble()]));
    expect(expectedYoung, isNot(expectedOld),
        reason: 'sonst prüft dieser Test nichts');
    expect(expectedYoung, AmpelLevel.guenstig);
    expect(expectedOld, AmpelLevel.verhalten);
    expect(levelOf(grid, 0), AmpelLevel.guenstig);
    expect(levelOf(grid, 1), AmpelLevel.verhalten);
  });

  test('die Temperatur dämpft: 27 °C macht aus sattem Regen ungünstig',
      () {
    final grid = ampelLevelsFrom(
        stackOf([List.filled(26, 5)]), tableOf(meanC: 27))!;
    expect(levelOf(grid, 0), AmpelLevel.unguenstig,
        reason: 'Glocke bei 27 °C ≈ 0,0004 — Score unter jeder Schwelle');
  });

  test('ein fehlender Kalendertag nimmt die ganze Ebene', () {
    // 25 statt 26 Tage: Die Altersgewichte wären still verschoben —
    // dieselbe Strenge wie die graue Sektion, heilt sich am Folgetag.
    expect(
        ampelLevelsFrom(
            stackOf([List.filled(25, 5)], days: 25), tableOf()),
        isNull);
  });

  test('ohne Station in 100 km bleibt die Zelle transparent', () {
    final grid = ampelLevelsFrom(
        stackOf([List.filled(26, 5)]), tableOf(lat: 40, lon: 3))!;
    expect(levelOf(grid, 0), isNull,
        reason: 'keine Temperatur, keine Aussage — kein geratener Wert');
  });

  test('ganz ohne Stationstabelle gibt es keine Ebene', () {
    expect(ampelLevelsFrom(stackOf([List.filled(26, 5)]), null), isNull);
  });
}
