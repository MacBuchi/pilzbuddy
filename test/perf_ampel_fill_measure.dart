// Messlauf, KEIN Dauertest: `flutter test test/perf_ampel_fill_measure.dart`
// von Hand — misst die Kombi-Ebene am ECHTEN Waldgitter (13,6 Mio.
// Waben, Übersichtszoom) mit und ohne Höhenauswertung je Wabe.
// Ergebnis gehört nach docs/map-performance.md; der Test selbst prüft
// nur, dass der Aufpreis unter 2× bleibt (grobe Reißleine, kein
// Benchmark-Golden — Maschinen streuen).
@Tags(['measure'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/ampel/ampel_fill.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/forest_fill.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';

T loadAsset<T>(String manifestPath, String binPath,
    T Function(Map<String, dynamic> m, Uint8List bytes) build) {
  final manifest =
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>;
  return build(manifest, File(binPath).readAsBytesSync());
}

void main() {
  test('Kombi-Ebene: Aufpreis der Höhenauswertung je Wabe', () {
    final forest = loadAsset(
        'assets/forest/forest_manifest.json',
        'assets/forest/forest_grid.bin.gz',
        (m, bytes) => ForestGrid.decode(
              bytes,
              width: m['width'] as int,
              height: m['height'] as int,
              west: (m['west'] as num).toDouble(),
              east: (m['east'] as num).toDouble(),
              north: (m['north'] as num).toDouble(),
              south: (m['south'] as num).toDouble(),
              referenceYear: m['reference_year'] as int,
              hexLonStep: (m['hex_lon_step'] as num).toDouble(),
              hexLatStep: (m['hex_lat_step'] as num).toDouble(),
            ));
    final elevation = loadAsset(
        'assets/elevation/elevation_manifest.json',
        'assets/elevation/elevation.bin.gz',
        (m, bytes) => ElevationGrid.decode(
              bytes,
              encoding: m['encoding'] as String,
              width: m['width'] as int,
              height: m['height'] as int,
              west: (m['west'] as num).toDouble(),
              east: (m['east'] as num).toDouble(),
              north: (m['north'] as num).toDouble(),
              south: (m['south'] as num).toDouble(),
              hexLonStep: (m['hex_lon_step'] as num).toDouble(),
              hexLatStep: (m['hex_lat_step'] as num).toDouble(),
            ));
    // Ein Stufen-Gitter in Regenraster-Größenordnung, überall gültig
    // und „günstig" — so führt JEDE Waldwabe die volle Auswertung aus:
    // teuerster Fall, nicht Durchschnitt.
    const cells = 900 * 1100;
    final levels = AmpelLevelGrid(
      rainFactor: Float32List.fromList(List.filled(cells, 1.0)),
      meanC: Float32List.fromList(List.filled(cells, 13.0)),
      stationHeightM: Int16List.fromList(List.filled(cells, 300)),
      valid: Uint8List.fromList(List.filled(cells, 1)),
      width: 900,
      height: 1100,
      west: forest.west,
      east: forest.east,
      north: forest.north,
      south: forest.south,
      newest: DateTime.utc(2026, 8, 17),
    );
    final window = FillWindow(
        west: forest.west,
        east: forest.east,
        north: forest.north,
        south: forest.south,
        width: 800,
        height: 600);

    Duration run({ElevationGrid? withElevation}) {
      final watch = Stopwatch()..start();
      forestAmpelFillPng([forest],
          window: window, levels: levels, elevation: withElevation);
      return watch.elapsed;
    }

    // Aufwärmen (JIT), dann je drei Läufe, Median.
    run();
    run(withElevation: elevation);
    Duration median(List<Duration> runs) =>
        (runs..sort())[runs.length ~/ 2];
    final without = median([for (var i = 0; i < 3; i++) run()]);
    final withEl = median(
        [for (var i = 0; i < 3; i++) run(withElevation: elevation)]);
    // ignore: avoid_print
    print('Kombi-Ebene, Übersichtszoom (13,6 Mio. Waben, 800×600 px): '
        'ohne Höhe ${without.inMilliseconds} ms, '
        'mit Höhe ${withEl.inMilliseconds} ms');
    expect(withEl.inMilliseconds, lessThan(without.inMilliseconds * 2 + 200),
        reason: 'Höhenauswertung je Wabe kostet mehr als das Doppelte — '
            'vor dem Ausliefern in docs/map-performance.md neu entscheiden');
  }, tags: ['measure'], timeout: const Timeout(Duration(minutes: 5)));
}
