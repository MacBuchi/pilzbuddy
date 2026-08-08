// Das Waldtypen-Gitter (#213): Format, Punktabfrage, Klassen-Schwellen.
// Die Helfer hier spiegeln test/rain_grid_test.dart — mit dem einen
// gewollten Unterschied, dass die Zeilen LINEAR in der Breite liegen.
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart' show mercatorY;

List<int> encodeForest(List<List<int>> rows) {
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

ForestGrid forestOf(List<List<int>> rows,
        {double west = 10,
        double east = 14,
        double north = 55,
        double south = 47}) =>
    ForestGrid.decode(encodeForest(rows),
        width: rows.first.length,
        height: rows.length,
        west: west,
        east: east,
        north: north,
        south: south,
        referenceYear: 2021);

void main() {
  group('decode', () {
    test('Roundtrip mit Zeilen, die verschieden anfangen', () {
      // Fängt ein Delta, das nicht je Zeile zurückgesetzt wird — die
      // erste Zeile stimmt dann, alles darunter ist Unsinn.
      final grid = forestOf([
        [0, 50, 101],
        [101, 1, 0],
        [255, 255, 80],
      ]);
      expect(grid.byteAt(0, 0), 0);
      expect(grid.byteAt(2, 0), 101);
      expect(grid.byteAt(0, 1), 101);
      expect(grid.byteAt(2, 2), 80);
    });

    test('falsche Größe wird abgelehnt', () {
      expect(
          () => ForestGrid.decode(
                encodeForest([
                  [1, 2, 3]
                ]),
                width: 2,
                height: 2,
                west: 10,
                east: 14,
                north: 55,
                south: 47,
                referenceYear: 2021,
              ),
          throwsFormatException);
    });
  });

  group('shareAt', () {
    test('liefert Wert−1 als Nadelanteil', () {
      final grid = forestOf([
        [1, 51, 101],
      ]);
      expect(grid.shareAt(51, 10.5), 0, reason: 'Byte 1 = 0 % Nadel');
      expect(grid.shareAt(51, 12.0), 50);
      expect(grid.shareAt(51, 13.5), 100);
    });

    test('kein Wald und keine Daten sind beide null — aber classAt trennt sie',
        () {
      final grid = forestOf([
        [0, 255],
      ]);
      expect(grid.shareAt(51, 11), isNull);
      expect(grid.shareAt(51, 13), isNull);
      expect(grid.classAt(51, 11), ForestClass.none,
          reason: '„kein Wald" ist eine Aussage');
      expect(grid.classAt(51, 13), isNull,
          reason: 'außerhalb der Abdeckung gibt es keine Aussage');
    });

    test('außerhalb des Gitters null', () {
      final grid = forestOf([
        [50, 50],
        [50, 50],
      ]);
      expect(grid.shareAt(56, 12), isNull);
      expect(grid.shareAt(46, 12), isNull);
      expect(grid.shareAt(51, 9.9), isNull);
      expect(grid.shareAt(51, 14.1), isNull);
    });

    test('die Breite ist LINEAR — eine Mercator-Rechnung träfe die falsche '
        'Zelle', () {
      // 100 Zeilen zwischen 47° und 55°, geprüft in der GITTERMITTE: An
      // den Rändern laufen lineare und Mercator-Rechnung zusammen (beide
      // gehen dort gegen 0 bzw. 1 — der erste Wurf dieses Tests stand bei
      // 47,8° und prüfte deshalb nichts), in der Mitte klaffen sie um
      // zwei Zeilen auseinander.
      final rows = [
        for (var y = 0; y < 100; y++) List<int>.filled(1, (y % 100) + 1),
      ];
      final grid = forestOf(rows, west: 10, east: 11);

      const lat = 51.0;
      final linearRow = ((55 - lat) / (55 - 47) * 100).floor();
      final top = mercatorY(55.0);
      final mercatorRow =
          ((mercatorY(lat) - top) / (mercatorY(47.0) - top) * 100).floor();
      expect(mercatorRow, isNot(linearRow),
          reason: 'sonst prüft dieser Test nichts');

      expect(grid.shareAt(lat, 10.5), (linearRow % 100) + 1 - 1);
    });
  });

  group('classOfByte', () {
    test('die Schwellen: unter 25 Laub, über 75 Nadel, dazwischen Misch', () {
      expect(classOfByte(0), ForestClass.none);
      expect(classOfByte(1), ForestClass.broadleaf); // 0 % Nadel
      expect(classOfByte(25), ForestClass.broadleaf); // 24 %
      expect(classOfByte(26), ForestClass.mixed); // 25 %
      expect(classOfByte(76), ForestClass.mixed); // 75 %
      expect(classOfByte(77), ForestClass.conifer); // 76 %
      expect(classOfByte(101), ForestClass.conifer); // 100 %
      expect(classOfByte(255), ForestClass.none);
    });
  });
}
