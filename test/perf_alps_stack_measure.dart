// Messlauf, KEIN Dauertest:
// `flutter test --tags measure test/perf_alps_stack_measure.dart`
//
// Was der gemessene Alpenstapel (#646) auf dem Gerät kostet. Er hat
// 1258 × 576 Zellen je Tag — so viele wie das Radar —, und mit ihm
// rechnen Ampel, Summenfläche und Verlauf am Spot einen Stapel MEHR.
//
// Gemessen an ECHTEN Tagesdateien. Sie liegen nicht im Repo, sondern am
// festen Tag `rain-data`; vor dem Lauf `rain_manifest.json` und die
// Dateien `alps_rain_*` und `alps_origin_*` in einen Ordner holen:
//
//   gh release download rain-data --dir /tmp/alps \
//     --pattern rain_manifest.json --pattern 'alps_*'
//   ALPS_DIR=/tmp/alps \
//     flutter test --tags measure test/perf_alps_stack_measure.dart
//
// Ohne den Ordner wird übersprungen statt geraten. Ergebnis gehört nach
// `docs/map-performance.md`.
@Tags(['measure'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/ampel/ampel_fill.dart';
import 'package:pilzbuddy/features/map/rain_contours.dart';
import 'package:pilzbuddy/features/map/rain_fill.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';
import 'package:pilzbuddy/features/map/rain_sum.dart';

({int medianMs, int minMs, int maxMs}) _time(int runs, void Function() body) {
  final samples = <int>[];
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    samples.add(watch.elapsedMilliseconds);
  }
  samples.sort();
  return (
    medianMs: samples[samples.length ~/ 2],
    minMs: samples.first,
    maxMs: samples.last,
  );
}

void main() {
  final dir = Platform.environment['ALPS_DIR'];
  final skip = dir == null ? 'ALPS_DIR nicht gesetzt' : null;

  RainStackData load() {
    final manifest = jsonDecode(
            File('$dir/rain_manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    final section = RainStackKind.alps.sectionOf(manifest)!;
    final info = RainStackInfo.tryParse(section, versioned: true)!;
    return RainStackData(
      kind: RainStackKind.alps,
      info: info,
      days: [
        for (final day in info.days)
          (date: day.date, gzipped: File('$dir/${day.file}').readAsBytesSync()),
      ],
      origins: [
        for (final day in info.days)
          if (day.origin != null)
            (
              date: day.date,
              gzipped: File('$dir/${day.origin}').readAsBytesSync()
            ),
      ],
    );
  }

  test('Alpenstapel: Größe, Summen, Fläche, Ampel, Verlauf', () {
    final stack = load();
    final packed = stack.days.fold<int>(0, (n, d) => n + d.gzipped.length);
    final origins = stack.origins.fold<int>(0, (n, d) => n + d.gzipped.length);
    // ignore: avoid_print
    print('Alpenstapel: ${stack.days.length} Tage, '
        '${stack.info.width}×${stack.info.height} Zellen, '
        'gepackt ${(packed / 1024).round()} KB + Herkunft '
        '${(origins / 1024).round()} KB');

    for (final days in [7, 14, 30]) {
      final t = _time(5, () => rainSumGrid(stack, days));
      // ignore: avoid_print
      print('Summe $days Tage: ${t.medianMs} ms (${t.minMs}–${t.maxMs})');
    }

    final sum = rainSumGrid(stack, 14)!;
    final fill = _time(5, () {
      final grid = alpineFillGrid(alps: sum, model: null);
      rainFillPng(grid!, levels: rainLevels14d, smooth: true);
    });
    // ignore: avoid_print
    print('Fläche 14 Tage (Gitter + PNG): ${fill.medianMs} ms '
        '(${fill.minMs}–${fill.maxMs})');

    final ampel = _time(3, () => ampelLevelsFrom(stack, null));
    // ignore: avoid_print
    print('Ampel-Zutaten (Regenteil, 26 Tage): ${ampel.medianMs} ms '
        '(${ampel.minMs}–${ampel.maxMs})');

    final points = [
      for (var i = 0; i < 19; i++) (lat: 46.2 + i * 0.1, lon: 9.0 + i * 0.3),
    ];
    final courses = _time(3, () => rainCoursesFromStacks([stack], points: points));
    // ignore: avoid_print
    print('Verläufe an 19 Spots, mit Herkunft: ${courses.medianMs} ms '
        '(${courses.minMs}–${courses.maxMs})');
    final bare = _time(3,
        () => rainCoursesFromStacks([stack], points: points, withOrigin: false));
    // ignore: avoid_print
    print('Verläufe an 19 Spots, ohne Herkunft: ${bare.medianMs} ms '
        '(${bare.minMs}–${bare.maxMs})');
    final one = _time(3, () => rainCoursesFromStacks([stack],
        points: [(lat: 47.27, lon: 11.40)]));
    // ignore: avoid_print
    print('Verlauf an einem Spot, mit Herkunft: ${one.medianMs} ms '
        '(${one.minMs}–${one.maxMs})');

    // Reißleine, kein Benchmark: Dieser Rechner ist kein Zielgerät.
    expect(ampel.medianMs, lessThan(10000));
  }, skip: skip);
}
