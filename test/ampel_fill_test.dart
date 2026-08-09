// Die Pilzwetter-Fläche (Ampel-Vorschau): zurückdekodiert und gegen
// das MODELL selbst geprüft — der Zeichner rechnet je Zelle dieselbe
// Reihe, die auch `ampelRainFactor`/`ampelLevelOf` bekämen; jede
// Abweichung (Gewichtung, Sättigung, Schwellen) reißt den Vergleich.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/ampel/ampel_fill.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/map/spot_weather.dart';

import 'rain_fill_test.dart' show decodePng;
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
  ({int r, int g, int b, int a}) pixel(dynamic png, int x) => (
        r: png.pixels[x * 4] as int,
        g: png.pixels[x * 4 + 1] as int,
        b: png.pixels[x * 4 + 2] as int,
        a: png.pixels[x * 4 + 3] as int,
      );

  test('je Zelle exakt die Stufe, die das Modell für ihre Reihe nennt',
      () {
    // Drei Zellen: satt (5 mm/Tag → Faktor 1), verhalten (1 mm/Tag →
    // 26/87 ≈ 0,30), trocken (0). Temperatur 13 °C → Faktor 1.
    final series = [
      List.filled(26, 5),
      List.filled(26, 1),
      List.filled(26, 0),
    ];
    final fill = ampelFillFrom(stackOf(series), tableOf())!;
    final png = decodePng(fill.png);
    expect(png.width, 3);

    for (final (x, cell) in series.indexed) {
      // Der Maßstab ist das MODELL selbst: dieselbe Reihe, Vortag
      // zuerst, durch dieselben Funktionen.
      final expected = ampelLevelOf(ampelRainFactor(
          [for (final mm in cell.reversed) mm.toDouble()]));
      final p = pixel(png, x);
      switch (expected) {
        case AmpelLevel.guenstig:
          expect(p.a, ampelFillAlpha, reason: 'Zelle $x');
          expect(p.r, (AppColors.forestGreen.r * 255).round());
        case AmpelLevel.verhalten:
          expect(p.a, ampelFillAlpha, reason: 'Zelle $x');
          expect(p.r, (AppColors.forestBroadleaf.r * 255).round());
        case AmpelLevel.unguenstig:
          expect(p.a, 0,
              reason: 'Zelle $x: ungünstig ist auf der Karte transparent '
                  '— keine Stufe heißt aussichtslos');
      }
    }
    expect(fill.newest, DateTime.utc(2026, 7, 26));
    expect(fill.west, 10);
    expect(fill.south, 50);
  });

  test('die Altersgewichtung zählt: gleicher Regen, anderes Alter, '
      'andere Stufe', () {
    // Beide Zellen bekommen 8×8 mm — Zelle 0 in den JÜNGSTEN acht
    // Tagen, Zelle 1 in den ältesten. Wer die Gewichtung umdreht oder
    // weglässt, malt beide gleich.
    final young = [...List.filled(18, 0), ...List.filled(8, 8)];
    final old = [...List.filled(8, 8), ...List.filled(18, 0)];
    final fill = ampelFillFrom(stackOf([young, old]), tableOf())!;
    final png = decodePng(fill.png);
    final expectedYoung = ampelLevelOf(ampelRainFactor(
        [for (final mm in young.reversed) mm.toDouble()]));
    final expectedOld = ampelLevelOf(ampelRainFactor(
        [for (final mm in old.reversed) mm.toDouble()]));
    expect(expectedYoung, isNot(expectedOld),
        reason: 'sonst prüft dieser Test nichts');
    // Jung: günstig (Grün) — alt: nur noch verhalten (Ocker). Die
    // Farben kommen aus dem Modell-Urteil, nicht aus einer Vermutung.
    expect(expectedYoung, AmpelLevel.guenstig);
    expect(expectedOld, AmpelLevel.verhalten);
    expect(pixel(png, 0).r, (AppColors.forestGreen.r * 255).round());
    expect(pixel(png, 1).r, (AppColors.forestBroadleaf.r * 255).round());
  });

  test('die Temperatur dämpft: 27 °C macht aus sattem Regen ungünstig',
      () {
    final fill = ampelFillFrom(
        stackOf([List.filled(26, 5)]), tableOf(meanC: 27))!;
    expect(pixel(decodePng(fill.png), 0).a, 0,
        reason: 'Glocke bei 27 °C ≈ 0,0004 — Score unter jeder Schwelle');
  });

  test('ein fehlender Kalendertag nimmt die ganze Ebene', () {
    // 25 statt 26 Tage: Die Altersgewichte wären still verschoben —
    // dieselbe Strenge wie die graue Sektion, heilt sich am Folgetag.
    expect(
        ampelFillFrom(
            stackOf([List.filled(25, 5)], days: 25), tableOf()),
        isNull);
  });

  test('ohne Station in 100 km bleibt die Zelle transparent', () {
    final fill = ampelFillFrom(
        stackOf([List.filled(26, 5)]), tableOf(lat: 40, lon: 3))!;
    expect(pixel(decodePng(fill.png), 0).a, 0,
        reason: 'keine Temperatur, keine Aussage — kein geratener Wert');
  });

  test('ganz ohne Stationstabelle gibt es keine Ebene', () {
    expect(ampelFillFrom(stackOf([List.filled(26, 5)]), null), isNull);
  });
}
