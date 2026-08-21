// Die Höhenlinien-Seite: Abtastung, Glättung, Äquidistanz, Stufenwahl.
//
// Alles ohne Karte und ohne das echte 3,4-MB-Asset — die Fehler, die
// hier lauern, sind Rechenfehler, und die sieht man am Gerät zu spät.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/contours.dart';
import 'package:pilzbuddy/features/map/elevation_contours.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart';

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

  group('Maßstab', () {
    test('Bodenauflösung fällt aus Sichtfenster und Pixelbreite', () {
      // 0,01° Länge auf 51° Breite sind rund 700 m; auf 100 Pixel also
      // rund 7 m je Pixel. Eine Zoomstufe kommt in der Rechnung nicht
      // vor, und genau das ist der Punkt: MapLibre und flutter_map
      // zählen sie verschieden.
      const bounds =
          MapViewBounds(west: 10.0, east: 10.01, north: 51.0, south: 50.99);
      expect(groundResolution(bounds, 100), closeTo(7.0, 0.3));
      expect(groundResolution(bounds, 200), closeTo(3.5, 0.2));
      expect(groundResolution(bounds, 0), double.infinity,
          reason: 'ein Fenster ohne Breite hat keinen Maßstab');
    });
  });

  group('Äquidistanz aus dem Gelände', () {
    test('folgt dem Relief, nicht einer Zoomtabelle', () {
      // Die Regel ist EIN Satz: Zwei Nachbarlinien brauchen
      // [contourMinLineSpacingPixels] Pixel Abstand. Steigt ein Pixel um
      // r Meter, ist die nötige Äquidistanz 20 · r.
      expect(contourEquidistanceM(reliefPerPixel: 0.5), 20);
      expect(contourEquidistanceM(reliefPerPixel: 2.0), 50);
      expect(contourEquidistanceM(reliefPerPixel: 4.0), 100);
      expect(contourEquidistanceM(reliefPerPixel: 9.0), 200);
      expect(contourEquidistanceM(reliefPerPixel: 11.0), isNull,
          reason: 'auch 200 m wären hier eine Schraffur — dann lieber '
              'nichts, und die Legende sagt „erst näher dran"');
    });

    test('dasselbe Gelände, gröberer Maßstab ⇒ gröbere Linien', () {
      int? at(double relief) => contourEquidistanceM(reliefPerPixel: relief);
      var previous = 0;
      for (final relief in [0.1, 0.5, 1.0, 2.0, 4.0, 8.0]) {
        final step = at(relief)!;
        expect(step, greaterThanOrEqualTo(previous), reason: 'Relief $relief');
        previous = step;
      }
    });

    test('eine strengere Schranke vergröbert, sie verfeinert nie', () {
      expect(contourEquidistanceM(reliefPerPixel: 2.0, minSpacingPixels: 10),
          20);
      expect(contourEquidistanceM(reliefPerPixel: 2.0, minSpacingPixels: 20),
          50);
      expect(contourEquidistanceM(reliefPerPixel: 2.0, minSpacingPixels: 40),
          100);
    });

    test('geht nie unter die Quantisierung der Rohdaten', () {
      expect(contourSteps.first, elevationQuantM);
      expect(contourEquidistanceM(reliefPerPixel: 0.0001), 20);
    });
  });

  group('Relief je Pixel', () {
    test('nimmt das bewegtere Viertel, nicht den Median', () {
      // Ein Feld aus Terrassen: knapp 30 % der Nachbarpaare liegen an
      // einer Stufenkante (100 m), der Rest ist eben. Der MEDIAN wäre
      // damit 0 — und aus 0 folgte die feinste Äquidistanz, ausgerechnet
      // im bewegten Gelände. Das 75. Perzentil sieht die Kante.
      const cols = 10, rows = 9;
      final values = Int32List(cols * rows);
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < cols; x++) {
          values[y * cols + x] = 100 * (x ~/ 3 + y ~/ 3);
        }
      }
      final field = ContourField(
        values: values,
        cols: cols,
        rows: rows,
        west: 10,
        east: 10.1,
        north: 51,
        south: 50.9,
      );
      expect(reliefPerPixel(field, pixelsPerCell: 1), 100,
          reason: 'ein Median von 0 hieße: feinste Äquidistanz im Steilhang');
      // Und die Rechnung teilt durch die Pixelgröße einer Zelle: Wird
      // dieselbe Kante auf zwei Pixel gestreckt, halbiert sich das
      // Relief je Pixel.
      expect(reliefPerPixel(field, pixelsPerCell: 2), 50);
    });

    test('ohne genug Nachbarpaare gibt es keine Aussage', () {
      final grid = elevationOf([
        [5, 5],
        [5, 5],
      ]);
      final field =
          resampleElevation(grid, window: windowOf(grid), smooth: false);
      expect(reliefPerPixel(field, pixelsPerCell: 1), isNull);
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

  group('Hauptlinien', () {
    test('kommen etwa alle 100 Höhenmeter, nicht „jede fünfte"', () {
      // Bei 20 m ist beides dasselbe. Bei 100 m wäre „jede fünfte" alle
      // 500 Höhenmeter — in einem Talkessel stünde dann keine einzige
      // Zahl auf dem Schirm.
      expect(contourIndexStepM(20), 100);
      expect(contourIndexStepM(50), 100);
      expect(contourIndexStepM(100), 100);
      expect(contourIndexStepM(200), 200,
          reason: 'gröber als die Äquidistanz geht nicht');
      for (final step in contourSteps) {
        expect(contourIndexStepM(step) % step, 0,
            reason: 'eine Hauptlinie ist immer auch eine Linie');
      }
    });
  });

  group('Zahlen an den Linien', () {
    ContourLine lineAt(double fromLon, double toLon,
            {required int level, required bool index}) =>
        ContourLine(
          level: level,
          index: index,
          cells: 20,
          points: [
            for (var i = 0; i <= 20; i++)
              LatLng(51.0, fromLon + (toLon - fromLon) * i / 20),
          ],
        );

    test('nur die Hauptlinien bekommen eine Zahl', () {
      // Alle fünf zu beschriften wäre dasselbe Zuviel wie vorher, nur
      // in Schrift. Die Zwischenlinien zählt man von der Hauptlinie ab.
      final labels = contourLabels([
        lineAt(10.0, 10.1, level: 500, index: true),
        lineAt(10.0, 10.1, level: 520, index: false),
      ], metersPerPixel: 10);
      expect(labels, isNotEmpty);
      expect(labels.every((l) => l.level == 500), isTrue);
    });

    test('ein kurzer Bogen bleibt unbeschriftet', () {
      // Eine Zahl auf einem 30-Pixel-Stummel überdeckt ihn ganz.
      final labels = contourLabels(
        [lineAt(10.0, 10.001, level: 500, index: true)],
        metersPerPixel: 10,
      );
      expect(labels, isEmpty);
    });

    test('die Zahlen stehen im Abstand, nicht am Anfang', () {
      final labels = contourLabels(
        [lineAt(10.0, 10.3, level: 500, index: true)],
        metersPerPixel: 10,
        spacingPixels: 400,
      );
      // ~21 km auf 10 m/px sind 2100 Pixel: fünf Plätze, gleichmäßig
      // verteilt und keiner am Linienende.
      expect(labels.length, greaterThanOrEqualTo(3));
      final firstLon = labels.first.point.longitude;
      expect(firstLon, greaterThan(10.0));
      expect(labels.last.point.longitude, lessThan(10.3));
    });

    test('keine Zahl steht auf dem Kopf', () {
      // Eine Höhenlinie läuft in jede Richtung; von Ost nach West wäre
      // der rohe Winkel 180°.
      for (final line in [
        lineAt(10.0, 10.3, level: 500, index: true),
        lineAt(10.3, 10.0, level: 500, index: true),
      ]) {
        for (final label in contourLabels([line], metersPerPixel: 10)) {
          expect(label.angleRadians.abs(), lessThanOrEqualTo(math.pi / 2));
        }
      }
    });
  });

  group('Der ganze Lauf', () {
    test('schweigt, wo ein Pixel mehr Boden abdeckt als eine Wabe', () {
      final grid = elevationOf([
        [1, 2],
        [3, 4],
      ]);
      expect(
          contourLinesFor(grid,
              window: windowOf(grid), metersPerPixel: 400),
          isNull,
          reason: 'eine Wabe ist 270 m breit — feiner wüssten wir es nicht');
    });

    test('markiert die Hauptlinien — alle 100 Höhenmeter', () {
      final rows = [
        for (var y = 0; y < 30; y++) [for (var x = 0; x < 30; x++) x],
      ];
      final grid = elevationOf(rows);
      final result = contourLinesFor(grid,
          window: windowOf(grid), metersPerPixel: 1)!;
      expect(result.equidistanceM, 20);
      final index = result.lines.where((l) => l.index).map((l) => l.level);
      expect(index, isNotEmpty);
      expect(index.every((level) => level % contourIndexEveryM == 0), isTrue);
      expect(result.lines.any((l) => !l.index), isTrue);
    });

    test('vergröbert einmal, wenn die Punktschranke reißt', () {
      // Ein steiles Feld: bei 20 m Äquidistanz sind es zu viele Linien.
      final rows = [
        for (var y = 0; y < 60; y++) [for (var x = 0; x < 60; x++) x + y],
      ];
      final grid = elevationOf(rows);
      final window = windowOf(grid);
      final generous =
          contourLinesFor(grid, window: window, metersPerPixel: 1)!;
      final tight = contourLinesFor(grid,
          window: window, metersPerPixel: 1, pointBudget: 200)!;
      expect(generous.equidistanceM, 20);
      expect(tight.equidistanceM, 50,
          reason: 'genau eine Stufe gröber, nicht in einer Schleife');
      expect(tight.key, endsWith('_50'));
    });
  });
}
