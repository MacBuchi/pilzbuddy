// Das Format, das `tool/rain_grid.py` schreibt, und der Zugriff darauf.
//
// Beides ist still falsch, wenn es falsch ist: Ein Gitter, dessen
// Zeilen-Delta nicht je Zeile zurückgesetzt wird, packt die erste Zeile
// korrekt aus und alles darunter zu Unsinn — auf der Karte sähe das nach
// einem Regengebiet aus.
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';

/// Kodiert wie das Werkzeug: Zeilen-Delta, dann gzip.
List<int> encode(List<List<int>> rows) {
  final delta = <int>[];
  for (final row in rows) {
    var previous = 0;
    for (final value in row) {
      delta.add((value - previous) & 0xFF);
      previous = value;
    }
  }
  return GZipEncoder().encode(delta)!;
}

RainGrid gridOf(
  List<List<int>> rows, {
  double west = 10,
  double east = 14,
  double north = 55,
  double south = 47,
}) =>
    RainGrid.decode(
      encode(rows),
      width: rows.first.length,
      height: rows.length,
      west: west,
      east: east,
      north: north,
      south: south,
      measured: DateTime.utc(2026, 8, 3, 5, 50),
    );

void main() {
  group('Auspacken', () {
    test('gibt genau die Zeilen zurück, die hineingingen', () {
      // Zeile 2 fängt hoch an und Zeile 3 niedrig — genau daran
      // scheitert ein Delta, das über die Zeilengrenze weiterläuft.
      final rows = [
        [0, 5, 5, 200, 255],
        [255, 1, 0, 0, 7],
        [7, 7, 7, 7, 7],
      ];
      final grid = gridOf(rows);
      for (var y = 0; y < rows.length; y++) {
        for (var x = 0; x < rows[y].length; x++) {
          expect(grid.values[y * 5 + x], rows[y][x],
              reason: 'Zelle ($x,$y)');
        }
      }
    });

    test('weist ein Gitter der falschen Größe zurück', () {
      // Lieber laut scheitern als 700 Zellen verschoben zeichnen.
      expect(
        () => RainGrid.decode(
          encode([
            [1, 2, 3]
          ]),
          width: 2,
          height: 1,
          west: 10,
          east: 14,
          north: 55,
          south: 47,
          measured: DateTime.utc(2026),
        ),
        throwsFormatException,
      );
    });
  });

  group('Wert an einem Punkt', () {
    test('liefert die Zelle, in der der Punkt liegt', () {
      final grid = gridOf([
        [1, 2, 3, 4],
        [5, 6, 7, 8],
      ]);
      // Knapp innerhalb der Nordwestecke.
      expect(grid.mmAt(54.99, 10.01), 1);
      // Knapp innerhalb der Südostecke.
      expect(grid.mmAt(47.01, 13.99), 8);
    });

    test('meldet außerhalb und ohne Daten mit null, nicht mit 0', () {
      // 0 mm ist eine Aussage („es hat nicht geregnet"), null ist keine.
      final grid = gridOf([
        [rainNoData, 0],
      ]);
      expect(grid.mmAt(51, 10.5), isNull, reason: 'keine Daten');
      expect(grid.mmAt(51, 13.5), 0, reason: '0 mm ist ein Messwert');
      expect(grid.mmAt(51, 9.9), isNull, reason: 'westlich daneben');
      expect(grid.mmAt(51, 14.1), isNull, reason: 'östlich daneben');
      expect(grid.mmAt(56, 12), isNull, reason: 'nördlich daneben');
      expect(grid.mmAt(46, 12), isNull, reason: 'südlich daneben');
    });

    test('rechnet die Breite IN MERCATOR, nicht in Grad', () {
      // Das Gitter ist in Mercator gleichmäßig. Wer linear in Grad
      // rechnet, greift über Deutschland um mehrere Zeilen daneben —
      // sichtbar wäre das als Regen, der zig Kilometer zu weit nördlich
      // liegt. Ein Gitter mit einer eigenen Zahl je Zeile macht den
      // Unterschied zu einer einzigen Zusicherung.
      final rows = [for (var y = 0; y < 100; y++) [y]];
      final grid = gridOf(rows, west: 10, east: 11, north: 55, south: 47);

      const lat = 51.0;
      final linear = ((55 - lat) / (55 - 47) * 100).floor();
      final mercator = grid.mmAt(lat, 10.5);

      expect(mercator, isNot(linear),
          reason: 'sonst prüft dieser Test nichts');
      // Von Hand nachgerechnet aus der Mercator-Formel.
      final top = mercatorY(55);
      final expected =
          ((mercatorY(lat) - top) / (mercatorY(47) - top) * 100).floor();
      expect(mercator, expected);
    });
  });

  group('Gitterkoordinaten', () {
    test('treffen an den Rändern genau die Ausdehnung', () {
      final grid = gridOf([
        [1, 2],
        [3, 4],
      ], west: 10, east: 14, north: 55, south: 47);
      expect(grid.lonAtColumn(0), closeTo(10, 1e-9));
      expect(grid.lonAtColumn(2), closeTo(14, 1e-9));
      expect(grid.latAtRow(0), closeTo(55, 1e-9));
      expect(grid.latAtRow(2), closeTo(47, 1e-9));
    });

    test('teilen die Breite in Mercator, nicht in Grad', () {
      // Die Mitte des Gitters liegt NICHT bei (55+47)/2 = 51 Grad,
      // sondern weiter nördlich. Ohne diese Zusicherung ließe sich
      // latAtRow durch eine lineare Interpolation ersetzen, ohne dass
      // ein Test es merkt — und der Regen läge dann zig Kilometer
      // daneben.
      final grid = gridOf([
        [1],
        [2],
      ], north: 55, south: 47);
      final middle = grid.latAtRow(1);
      expect(middle, isNot(closeTo(51, 0.01)));
      expect(middle, closeTo(latFromMercatorY(
          (mercatorY(55) + mercatorY(47)) / 2), 1e-9));
    });
  });

  group('Mercator', () {
    test('trifft die dokumentierte Ecke des Web-Mercator-Quadrats', () {
      // Dieselbe Prüfung wie im Selbsttest von tool/rain_grid.py — die
      // Definition von EPSG:3857, nicht eine aus diesem Code
      // abgeschriebene Zahl. Beide Seiten müssen dieselbe Zelle meinen.
      expect(latFromMercatorY(20037508.34), closeTo(85.051129, 1e-5));
      expect(latFromMercatorY(0), closeTo(0, 1e-9));
    });

    test('hin und zurück trifft wieder denselben Punkt', () {
      for (final lat in [-60.0, -0.5, 0.0, 47.0, 51.2971, 55.2, 84.0]) {
        expect(latFromMercatorY(mercatorY(lat)), closeTo(lat, 1e-9),
            reason: '$lat');
      }
    });

    test('stimmt mit einer algebraisch anderen Umkehrung überein', () {
      // asin(tanh(y/R)) ist dieselbe Funktion, anders geschrieben. Ein
      // Tippfehler überlebt nicht beide.
      const radius = 6378137.0;
      for (final y in [-8000000.0, -1.0, 1234.5, 6674000.53, 12000000.0]) {
        final other = math.asin(_tanh(y / radius)) * 180 / math.pi;
        expect(latFromMercatorY(y), closeTo(other, 1e-9), reason: '$y');
      }
    });
  });
}

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
