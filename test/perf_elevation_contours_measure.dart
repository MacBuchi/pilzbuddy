// Messlauf, KEIN Dauertest:
// `flutter test --tags measure test/perf_elevation_contours_measure.dart`
// von Hand — misst die Höhenlinien am ECHTEN Höhengitter
// (3038 × 4470 Waben) in drei Landschaften über den ganzen sinnvollen
// Maßstabsbereich. Er beantwortet zwei Fragen auf einmal: Was kostet
// ein Kamera-Stillstand, und WELCHE Äquidistanz fällt aus dem Gelände?
//
// Ergebnis gehört nach `docs/map-performance.md` — die Hausregel
// verlangt für jede Stellschraube der Karte eine Messung, keine
// Schätzung. Der Test selbst prüft nur eine grobe Reißleine, kein
// Benchmark-Golden: Maschinen streuen.
@Tags(['measure'])
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/elevation_contours.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart';

ElevationGrid loadElevation() {
  final manifest =
      jsonDecode(File('assets/elevation/elevation_manifest.json')
          .readAsStringSync()) as Map<String, dynamic>;
  final bytes = File('assets/elevation/elevation.bin.gz').readAsBytesSync();
  return ElevationGrid.decode(
    bytes,
    encoding: manifest['encoding'] as String,
    width: manifest['width'] as int,
    height: manifest['height'] as int,
    west: (manifest['west'] as num).toDouble(),
    east: (manifest['east'] as num).toDouble(),
    north: (manifest['north'] as num).toDouble(),
    south: (manifest['south'] as num).toDouble(),
    hexLonStep: (manifest['hex_lon_step'] as num).toDouble(),
    hexLatStep: (manifest['hex_lat_step'] as num).toDouble(),
  );
}

/// Breite des Kartenfensters in logischen Pixeln — ein Pixel 7 Pro mit
/// der Vorgabedichte. Dieselbe Zahl, die `map_screen.dart` aus
/// `MediaQuery` holt.
const screenWidthPixels = 412.0;
const screenHeightPixels = 732.0;

/// Das geplante Fenster um einen Punkt, so wie es dieser Schirm bei
/// dieser Bodenauflösung auslöst — derselbe Weg, den die App nimmt.
FillWindow windowAt(
    ElevationGrid grid, double lat, double lon, double metersPerPixel) {
  final degPerPixel =
      metersPerPixel / (111320 * math.cos(lat * math.pi / 180));
  final halfLon = degPerPixel * screenWidthPixels / 2;
  final halfLat = degPerPixel * screenHeightPixels / 2 *
      math.cos(lat * math.pi / 180);
  return planFillWindow(
    viewport: MapViewBounds(
      west: lon - halfLon,
      east: lon + halfLon,
      north: lat + halfLat,
      south: lat - halfLat,
    ),
    gridWest: grid.west,
    gridEast: grid.east,
    gridNorth: grid.north,
    gridSouth: grid.south,
  )!;
}

void main() {
  test('Höhenlinien: Äquidistanz und Rechenzeit je Kamera-Stillstand', () {
    final grid = loadElevation();
    final places = [
      (name: 'Alpen (Innsbruck)', lat: 47.30, lon: 11.40),
      (name: 'Mittelgebirge (Sauerland)', lat: 51.20, lon: 8.30),
      (name: 'Hochwald (Saarland)', lat: 49.62, lon: 6.95),
      (name: 'Flachland (Heide)', lat: 53.20, lon: 9.90),
    ];
    // Bodenauflösungen, wie sie am Gerät wirklich vorkommen — gemessen
    // am Maßstabsbalken, nicht aus einer Zoomtabelle abgeleitet.
    const resolutions = [2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 200.0];
    var worst = 0;
    // ignore: avoid_print
    print('| Lage | m/px | Relief je px | Äquidistanz | Linien | Punkte | ms |');
    // ignore: avoid_print
    print('|---|---|---|---|---|---|---|');
    for (final place in places) {
      for (final metersPerPixel in resolutions) {
        final window =
            windowAt(grid, place.lat, place.lon, metersPerPixel);
        final watch = Stopwatch()..start();
        final result = contourLinesFor(grid,
            window: window, metersPerPixel: metersPerPixel);
        watch.stop();
        worst = watch.elapsedMilliseconds > worst
            ? watch.elapsedMilliseconds
            : worst;
        final points = result == null
            ? 0
            : result.lines.fold<int>(0, (sum, l) => sum + l.points.length);
        // Das Relief noch einmal für die Tabelle — dieselbe Rechnung,
        // die drinnen die Äquidistanz wählt.
        final field = resampleElevation(grid, window: window);
        final metersPerCell = (window.east - window.west) *
            111320 *
            math.cos((window.north + window.south) / 2 * math.pi / 180) /
            field.cols;
        final relief = reliefPerPixel(field,
            pixelsPerCell: metersPerCell / metersPerPixel);
        // ignore: avoid_print
        print('| ${place.name} | ${metersPerPixel.toStringAsFixed(0)} | '
            '${relief?.toStringAsFixed(2) ?? "—"} m | '
            '${result?.equidistanceM ?? "—"} m | '
            '${result?.lines.length ?? 0} | $points | '
            '${watch.elapsedMilliseconds} |');
        expect(points, lessThanOrEqualTo(contourPointBudget),
            reason: '${place.name}: die Punktschranke hat nicht gegriffen');
      }
    }
    // Grobe Reißleine. Gerechnet wird im Isolate und nur bei
    // Kamera-Stillstand; alles unter einer Viertelsekunde ist unsichtbar.
    expect(worst, lessThan(1500),
        reason: 'teuerster Fall \$worst ms — das gehört gemessen und '
            'in docs/map-performance.md erklärt, bevor es bleibt');
  });
}
