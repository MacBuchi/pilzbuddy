// Schutzgebiete schraffiert statt gefüllt (#580).
//
// Geprüft wird am BILD, nicht an einer Zusage: Welche Pixel volle und
// welche verringerte Deckkraft haben, liest der Test aus dem PNG.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_fill.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/protected_areas.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart' show mercatorY;

import 'forest_grid_test.dart' show encodeForest;
import 'protected_areas_test.dart' show protectedOf;
import 'rain_fill_test.dart' show decodePng;

void main() {
  const lonStep = 0.004, latStep = 0.003;
  const cols = 60, rows = 80;

  // Überall Laubwald (Byte 11 = 10 % Nadel).
  final grid = ForestGrid.decode(
    encodeForest([
      for (var y = 0; y < rows; y++) [for (var x = 0; x < cols; x++) 11],
    ]),
    width: cols,
    height: rows,
    west: 10,
    east: 10 + lonStep * (cols + 0.5),
    north: 50,
    south: 50 - latStep * (rows + 1),
    referenceYear: 2024,
    hexLonStep: lonStep,
    hexLatStep: latStep,
  );

  // Auf demselben Raster: die linke Hälfte ist Schutzgebiet.
  final ProtectedAreas protected = protectedOf(
    [
      for (var y = 0; y < rows; y++) [(0, cols ~/ 2, 1)],
    ],
    west: 10,
    north: 50,
    lonStep: lonStep,
    latStep: latStep,
    width: cols,
  );

  FillWindow windowAt(double hexPixels, {double shiftPx = 0}) {
    const inset = 8;
    final west = grid.west + lonStep * inset;
    final east = grid.east - lonStep * inset;
    final north = grid.north - latStep * inset;
    final south = grid.south + latStep * inset;
    final width = ((east - west) / lonStep * hexPixels).round();
    final degPerPx = (east - west) / width;
    final mercHeight = (mercatorY(north) - mercatorY(south)).abs();
    final mercWidth = (east - west) * math.pi / 180 * 6378137.0;
    return FillWindow(
      west: west + shiftPx * degPerPx,
      east: east + shiftPx * degPerPx,
      north: north,
      south: south,
      width: width,
      height: (width * mercHeight / mercWidth).round(),
    );
  }

  /// Deckkraft je Pixel als Zeilen.
  List<List<int>> alphas(Uint8List png) {
    final image = decodePng(png);
    return [
      for (var y = 0; y < image.height; y++)
        [
          for (var x = 0; x < image.width; x++)
            image.pixels[(y * image.width + x) * 4 + 3],
        ],
    ];
  }

  /// Die Mitte der linken (geschützten) und rechten Hälfte — fern der
  /// Gebietsgrenze, damit kein halb bedecktes Pixel mitzählt.
  (List<int> left, List<int> right) halves(List<List<int>> a) {
    final width = a.first.length;
    final left = <int>[], right = <int>[];
    for (final row in a.sublist(a.length ~/ 4, a.length * 3 ~/ 4)) {
      left.addAll(row.sublist(width ~/ 10, width * 3 ~/ 10));
      right.addAll(row.sublist(width * 7 ~/ 10, width * 9 ~/ 10));
    }
    return (left, right);
  }

  test('im Schutzgebiet wechseln volle Streifen und blasse Lücken, '
      'draußen bleibt die Fläche, wie sie war', () {
    final window = windowAt(6);
    final (left, right) = halves(alphas(forestFillPng(grid,
        classes: allForestClasses, window: window, protected: protected)));

    expect(right.toSet(), {forestFillAlpha},
        reason: 'außerhalb ändert die Schraffur nichts');
    final gap = (forestFillAlpha * hatchGapShare).round();
    expect(left.toSet(), {forestFillAlpha, gap},
        reason: 'genau zwei Stufen: Streifen und Lücke');
    final gapShare = left.where((a) => a == gap).length / left.length;
    const expected = (hatchPeriodPx - hatchStripePx) / hatchPeriodPx;
    expect(gapShare, closeTo(expected, 0.03));
  });

  test('die Streifen laufen diagonal', () {
    final a = alphas(forestFillPng(grid,
        classes: allForestClasses, window: windowAt(6), protected: protected));
    // Entlang x + y = konstant bleibt der Zustand gleich — einen Schritt
    // nach rechts und einen nach oben.
    final y = a.length ~/ 2;
    final x = a.first.length ~/ 5;
    for (var k = 0; k < 10; k++) {
      expect(a[y - k][x + k], a[y][x], reason: 'Schritt $k');
    }
    // Und quer dazu wechselt er innerhalb einer Periode.
    final across = {for (var k = 0; k < hatchPeriodPx; k++) a[y][x + k]};
    expect(across, hasLength(2));
  });

  test('die Streifen hängen an der Karte: ein verschobenes Fenster zeigt '
      'an derselben Stelle dasselbe Muster', () {
    // Ohne diese Verankerung sprängen die Streifen bei jedem Neuplanen
    // des Fensters, also bei jedem Verschieben über seinen Rand.
    const shift = 7.0;
    final a = alphas(forestFillPng(grid,
        classes: allForestClasses, window: windowAt(6), protected: protected));
    final b = alphas(forestFillPng(grid,
        classes: allForestClasses,
        window: windowAt(6, shiftPx: shift),
        protected: protected));
    final y = a.length ~/ 2;
    for (var x = 20; x < 60; x++) {
      expect(b[y][x - shift.toInt()], a[y][x], reason: 'Spalte $x');
    }
  });

  test('weit draußen (Wabe unter $hatchMinHexPx px) keine Schraffur', () {
    // Dort wären die Streifen breiter als die Gebiete, und der Nachschlag
    // liefe über jede Wabe im Übersichtszoom.
    final window = windowAt(1);
    final hatched = alphas(forestFillPng(grid,
        classes: allForestClasses, window: window, protected: protected));
    final plain =
        alphas(forestFillPng(grid, classes: allForestClasses, window: window));
    expect(hatched, plain);
  });

  test('ohne Schutzgebiete malt die Fläche genau wie vorher', () {
    final window = windowAt(6);
    final empty = protectedOf([
      for (var y = 0; y < rows; y++) const <(int, int, int)>[],
    ], west: 10, north: 50, lonStep: lonStep, latStep: latStep, width: cols);
    expect(
        alphas(forestFillPng(grid,
            classes: allForestClasses, window: window, protected: empty)),
        alphas(forestFillPng(grid, classes: allForestClasses, window: window)));
  });
}
