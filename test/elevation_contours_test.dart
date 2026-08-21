// Die Höhenlinien-Seite: Abtastung, Glättung, Äquidistanz, Stufenwahl.
//
// Alles ohne Karte und ohne das echte 3,4-MB-Asset — die Fehler, die
// hier lauern, sind Rechenfehler, und die sieht man am Gerät zu spät.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/contours.dart';
import 'package:pilzbuddy/features/map/elevation_contours.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';

/// Ein Höhengitter aus Byte-Zeilen — dieselbe Bauart wie `gridOf` beim
/// Regen, nur ohne den Umweg über gzip.
ElevationGrid elevationOf(
  List<List<int>> rows, {
  double west = 10.0,
  double north = 51.0,
  double lonStep = 0.01,
  double latStep = 0.01,
}) {
  final height = rows.length;
  final width = rows.first.length;
  return ElevationGrid(
    values: Uint8List.fromList([for (final row in rows) ...row]),
    width: width,
    height: height,
    west: west,
    east: west + width * lonStep,
    north: north,
    south: north - height * latStep,
    hexLonStep: lonStep,
    hexLatStep: latStep,
  );
}

FillWindow windowOf(ElevationGrid grid) => FillWindow(
      west: grid.west,
      east: grid.east,
      north: grid.north,
      south: grid.south,
      width: 256,
      height: 256,
    );

void main() {
  group('Abtastung', () {
    test('nimmt höchstens eine Probe je Wabe', () {
      // Feiner abzutasten als das Gitter bläst jede Wabe zu einem Block
      // gleicher Werte auf — Marching Squares zeichnet daraufhin die
      // Wabenkanten als Terrassen in die Linie.
      final counts = contourSampleCounts(
        window: const FillWindow(
            west: 10, east: 10.5, north: 51, south: 50.5, width: 1, height: 1),
        hexLonStep: 0.01,
        hexLatStep: 0.01,
      );
      expect(counts.cols, 50);
      expect(counts.rows, 50);
    });

    test('deckelt weit draußen auf das Budget', () {
      final counts = contourSampleCounts(
        window: const FillWindow(
            west: 5.8, east: 17.3, north: 55.1, south: 45.7,
            width: 1, height: 1),
        hexLonStep: 0.003786015,
        hexLatStep: 0.002102809,
        budget: 768,
      );
      expect(counts.cols, 768);
      expect(counts.rows, 768);
    });

    test('trifft dieselbe Wabe wie heightMetersAt', () {
      // Die #1-Regel aus CLAUDE.md: keine zweite Geometrie. Wenn die
      // Abtastung eine andere Wabe nähme als die Punkt-Ablesung, läge
      // die Linie woanders als die Zahl im Blatt.
      final grid = elevationOf([
        [1, 5, 9],
        [2, 6, 10],
        [3, 7, 11],
      ]);
      final field = resampleElevation(grid,
          window: windowOf(grid), smooth: false);
      for (var y = 0; y < field.rows; y++) {
        for (var x = 0; x < field.cols; x++) {
          final lat = field.latAtRow(y + 0.5);
          final lon = field.lonAtColumn(x + 0.5);
          expect(field.values[y * field.cols + x],
              grid.heightMetersAt(lat, lon),
              reason: 'Zelle ($x,$y) bei $lat/$lon');
        }
      }
    });

    test('macht aus einer Randzelle ohne Aussage keine Höhe', () {
      final grid = elevationOf([
        [5, elevationNoData],
        [5, 5],
      ]);
      final field = resampleElevation(grid,
          window: windowOf(grid), smooth: false);
      expect(field.values, contains(contourNoData));
      expect(field.values, isNot(contains(elevationNoData * elevationQuantM)));
    });
  });

  group('Glätten ist Pflicht, nicht Geschmack', () {
    test('bricht die 20-Meter-Entartung auf der Stufe selbst', () {
      // Rohhöhen sind Vielfache von 20 m. Liegt eine Stufe GENAU auf
      // einem Wert — hier 120 m auf der rechten Hälfte —, dann gibt
      // `_fraction(100, 120, 120)` glatt 1,0 zurück: Der Stützpunkt
      // rutscht exakt auf die Zellmitte, und die Linie wird zur Treppe
      // entlang des Gitters statt zwischen den Zellen zu verlaufen.
      final rows = [
        for (var y = 0; y < 9; y++)
          [
            // 100 m — Plateau auf genau 120 m — 140 m
            for (var x = 0; x < 9; x++)
              x < 3
                  ? 5
                  : x < 5
                      ? 6
                      : 7,
          ],
      ];
      final grid = elevationOf(rows);
      final window = windowOf(grid);

      List<ContourLine> at({required bool smooth}) {
        final field =
            resampleElevation(grid, window: window, smooth: smooth);
        return contourLines(
          values: field.values,
          width: field.cols,
          height: field.rows,
          noData: contourNoData,
          levels: const [120],
          latAtRow: field.latAtRow,
          lonAtColumn: field.lonAtColumn,
          toleranceCells: 0,
          minChainCells: 2,
          roundingPasses: 0,
        );
      }

      final raw = at(smooth: false);
      final smoothed = at(smooth: true);
      expect(raw, isNotEmpty);
      expect(smoothed, isNotEmpty);

      // Ungeglättet liefert `_fraction` glatt 1,0 bzw. 0,5 — jeder
      // Stützpunkt liegt auf einer GANZZAHLIGEN Spalte, die Linie ist
      // also eine Treppe entlang des Gitters.
      bool onLattice(double lon) {
        final column =
            (lon - window.west) / ((window.east - window.west) / 9) - 0.5;
        return (column - column.roundToDouble()).abs() < 1e-9;
      }

      expect(
          [for (final line in raw) ...line.points].every(
              (point) => onLattice(point.longitude)),
          isTrue,
          reason: 'ohne Glätten klebt jeder Stützpunkt auf einer Spalte');
      expect(
          [for (final line in smoothed) ...line.points].any(
              (point) => !onLattice(point.longitude)),
          isTrue,
          reason: 'geglättet muss die Linie zwischen die Spalten rutschen');
    });

    test('mittelt den Paritätsversatz des Hexgitters weg', () {
      // Das Höhengitter ist odd-r: Benachbarte ZEILEN holen ihren Wert
      // aus Waben, die um eine halbe Wabe gegeneinander versetzt liegen.
      // Bei einem Gefälle nach Osten heißt das ±eine halbe Wabe im
      // Wechsel — ein Sägezahn an jeder Linie, und zwar in derselben
      // Größenordnung wie die Quantisierung.
      final rows = [
        for (var y = 0; y < 24; y++) [for (var x = 0; x < 24; x++) x],
      ];
      final grid = elevationOf(rows);
      final window = windowOf(grid);

      double wobble({required bool smooth}) {
        final field =
            resampleElevation(grid, window: window, smooth: smooth);
        final lines = contourLines(
          values: field.values,
          width: field.cols,
          height: field.rows,
          noData: contourNoData,
          levels: const [230],
          latAtRow: field.latAtRow,
          lonAtColumn: field.lonAtColumn,
          toleranceCells: 0,
          minChainCells: 4,
          roundingPasses: 0,
        );
        expect(lines, isNotEmpty);
        final lons = [
          for (final line in lines) ...line.points.map((p) => p.longitude),
        ];
        return lons.reduce(math.max) - lons.reduce(math.min);
      }

      // Eine senkrechte Linie darf in Längsrichtung kaum schwanken.
      expect(wobble(smooth: true), lessThan(wobble(smooth: false)),
          reason: 'ohne Glätten sägt die Linie um eine halbe Wabe');
    });

    test('lässt Nichtdaten Nichtdaten und zieht den Mittelwert nicht herunter',
        () {
      final values = [
        100, 100, 100, //
        100, contourNoData, 100, //
        100, 100, 100,
      ];
      final out =
          smooth3x3(values, width: 3, height: 3, noData: contourNoData);
      expect(out[4], contourNoData);
      expect(out.where((v) => v != contourNoData), everyElement(100));
    });
  });

  group('Äquidistanz nach Maßstab', () {
    test('fällt aus Pixeln, nicht aus geratenen Zoomstufen', () {
      expect(contourEquidistanceM(14), 20);
      expect(contourEquidistanceM(13), 20);
      expect(contourEquidistanceM(12), 50);
      expect(contourEquidistanceM(11), 100);
      expect(contourEquidistanceM(10), 200);
      expect(contourEquidistanceM(9), isNull,
          reason: 'in der Übersicht ist eine 270-m-Linie eine Karikatur');
    });

    test('hängt an der Pixelschranke — doppelt so streng, eine Stufe später',
        () {
      // Die Probe darauf, dass die Tabelle oben eine Rechnung ist und
      // keine abgetippte Liste.
      for (final zoom in [10.0, 11.0, 12.0, 13.0]) {
        expect(contourEquidistanceM(zoom, minPixels: 24),
            contourEquidistanceM(zoom - 1, minPixels: 12),
            reason: 'Zoom $zoom');
      }
    });

    test('geht nie unter die Quantisierung der Rohdaten', () {
      expect(contourSteps.first, elevationQuantM);
      expect(contourEquidistanceM(18), 20);
    });
  });

  group('Stufen im Feld', () {
    test('nimmt nur, was vorkommt — nicht 0 bis 4740', () {
      final grid = elevationOf([
        [5, 5],
        [8, 8],
      ]); // 100 m und 160 m
      final field =
          resampleElevation(grid, window: windowOf(grid), smooth: false);
      expect(levelsIn(field, 20), [120, 140, 160]);
      expect(levelsIn(field, 50), [150]);
    });

    test('ein Feld ohne Aussage hat keine Stufen', () {
      final grid = elevationOf([
        [elevationNoData, elevationNoData],
        [elevationNoData, elevationNoData],
      ]);
      final field =
          resampleElevation(grid, window: windowOf(grid), smooth: false);
      expect(field.range, isNull);
      expect(levelsIn(field, 20), isEmpty);
    });
  });

  group('Der ganze Lauf', () {
    test('zeichnet unter z10 gar nichts', () {
      final grid = elevationOf([
        [1, 2],
        [3, 4],
      ]);
      expect(
          contourLinesFor(grid, window: windowOf(grid), zoom: 9), isNull);
    });

    test('markiert jede fünfte Linie als Hauptlinie', () {
      final rows = [
        for (var y = 0; y < 30; y++) [for (var x = 0; x < 30; x++) x],
      ];
      final grid = elevationOf(rows);
      final result =
          contourLinesFor(grid, window: windowOf(grid), zoom: 13)!;
      expect(result.equidistanceM, 20);
      final index = result.lines.where((l) => l.index).map((l) => l.level);
      expect(index, isNotEmpty);
      expect(index.every((level) => level % 100 == 0), isTrue);
      expect(result.lines.any((l) => !l.index), isTrue);
    });

    test('vergröbert einmal, wenn die Punktschranke reißt', () {
      // Ein steiles Feld: bei 20 m Äquidistanz sind es zu viele Linien.
      final rows = [
        for (var y = 0; y < 60; y++) [for (var x = 0; x < 60; x++) x + y],
      ];
      final grid = elevationOf(rows);
      final window = windowOf(grid);
      final generous = contourLinesFor(grid, window: window, zoom: 13)!;
      final tight = contourLinesFor(grid,
          window: window, zoom: 13, pointBudget: 200)!;
      expect(generous.equidistanceM, 20);
      expect(tight.equidistanceM, 50,
          reason: 'genau eine Stufe gröber, nicht in einer Schleife');
      expect(tight.key, endsWith('_50'));
    });
  });
}
