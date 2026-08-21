// Messlauf, KEIN Dauertest:
// `flutter test test/perf_elevation_contours_measure.dart` von Hand —
// misst die Höhenlinien am ECHTEN Höhengitter (3038 × 4470 Waben) in
// drei Lagen: Alpen bei z11 (der teuerste Fall, den die Zoomregel
// zulässt), Mittelgebirge bei z12, Flachland bei z13.
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

/// Das geplante Fenster um einen Punkt, so wie es ein 1080×1920-Schirm
/// bei dieser Zoomstufe auslöst — also derselbe Weg, den die App nimmt.
FillWindow windowAt(ElevationGrid grid, double lat, double lon, double zoom) {
  final degPerPixel = 360 / (256 * math.pow(2, zoom));
  final halfLon = degPerPixel * 1080 / 2;
  final halfLat = degPerPixel * 1920 / 2 * math.cos(lat * math.pi / 180);
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
  test('Höhenlinien: Rechenzeit je Kamera-Stillstand', () {
    final grid = loadElevation();
    final cases = [
      (name: 'Alpen z11      ', lat: 47.30, lon: 11.40, zoom: 11.0),
      (name: 'Mittelgebirge z12', lat: 51.05, lon: 8.30, zoom: 12.0),
      (name: 'Flachland z13  ', lat: 53.20, lon: 9.90, zoom: 13.0),
    ];
    var worst = 0;
    // ignore: avoid_print
    print('| Lage | Abtastung | Äquidistanz | Linien | Punkte | ms |');
    // ignore: avoid_print
    print('|---|---|---|---|---|---|');
    for (final c in cases) {
      final window = windowAt(grid, c.lat, c.lon, c.zoom);
      final counts = contourSampleCounts(
        window: window,
        hexLonStep: grid.hexLonStep,
        hexLatStep: grid.hexLatStep,
      );
      final watch = Stopwatch()..start();
      final result =
          contourLinesFor(grid, window: window, zoom: c.zoom);
      watch.stop();
      worst = watch.elapsedMilliseconds > worst
          ? watch.elapsedMilliseconds
          : worst;
      final points = result == null
          ? 0
          : result.lines.fold<int>(0, (sum, l) => sum + l.points.length);
      // ignore: avoid_print
      print('| ${c.name} | ${counts.cols}×${counts.rows} | '
          '${result?.equidistanceM ?? "—"} m | ${result?.lines.length ?? 0} | '
          '$points | ${watch.elapsedMilliseconds} |');
      expect(points, lessThanOrEqualTo(contourPointBudget),
          reason: '${c.name}: die Punktschranke hat nicht gegriffen');
    }
    // Grobe Reißleine. Gerechnet wird im Isolate und nur bei
    // Kamera-Stillstand; alles unter einer Viertelsekunde ist unsichtbar.
    expect(worst, lessThan(1500),
        reason: 'teuerster Fall \$worst ms — das gehört gemessen und '
            'in docs/map-performance.md erklärt, bevor es bleibt');
  });
}
