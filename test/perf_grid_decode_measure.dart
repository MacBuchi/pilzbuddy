// Messlauf, KEIN Dauertest:
// `flutter test --tags measure test/perf_grid_decode_measure.dart`
//
// Was hier gemessen wird, ist die eine Zahl, die in
// `docs/map-performance.md` bisher fehlte: **das Auspacken selbst.**
// Dokumentiert waren immer nur Größen („3,4 MB", „13,6 MB") und die
// Rechnung DANACH (Fläche, Höhenlinien). Wie lange gunzip und
// Zeilen-Delta dauern, stand nirgends — und ohne diese Zahl lässt sich
// nicht beurteilen, ob ein Platten-Zwischenspeicher für ausgepackte
// Gitter etwas brächte oder nur Platz kostete.
//
// Gemessen wird an den ECHTEN Assets, nicht an Attrappen.
//
// Der Regenteil braucht eine echte Tagesdatei; die liegt nicht im Repo,
// sondern am festen Tag `rain-data`. Vor dem Lauf einmal holen und den
// Pfad mitgeben:
//
//   curl -sL https://github.com/MacBuchi/pilzbuddy/releases/download/\
//   rain-data/rain_day_20260823.bin.gz -o /tmp/rain_day.bin.gz
//   RAIN_DAY_FILE=/tmp/rain_day.bin.gz \
//     flutter test --tags measure test/perf_grid_decode_measure.dart
//
// Ohne die Datei wird dieser Teil übersprungen statt geraten.
//
// Ergebnis gehört nach `docs/map-performance.md` — die Hausregel
// verlangt für jede Stellschraube der Karte eine Messung. Der Test
// selbst prüft nur grobe Reißleinen, kein Benchmark-Golden: Maschinen
// streuen, und dieser Rechner ist keiner der Zielgeräte.
@Tags(['measure'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/forest_species.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';

Map<String, dynamic> _manifest(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Median statt Mittelwert: Der erste Lauf trägt JIT-Aufwärmung, und ein
/// einzelner Ausreißer soll die Aussage nicht verschieben.
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
  test('Höhengitter auspacken', () {
    final manifest = _manifest('assets/elevation/elevation_manifest.json');
    final bytes = File('assets/elevation/elevation.bin.gz').readAsBytesSync();
    final result = _time(
        5,
        () => ElevationGrid.decode(
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
            ));
    final cells = (manifest['width'] as int) * (manifest['height'] as int);
    // ignore: avoid_print
    print('Höhengitter:   ${bytes.length ~/ 1024} KB gepackt → '
        '${cells ~/ 1024} KB ausgepackt · '
        '${result.medianMs} ms (${result.minMs}–${result.maxMs})');
    expect(result.medianMs, lessThan(10000));
  });

  test('Waldgitter auspacken — läuft bei JEDEM App-Start', () {
    // map_screen.dart beobachtet forestGridProvider für die Sichtbarkeit
    // des Wald-Knopfes. Anders als beim Höhengitter ist dieses Auspacken
    // also nicht aufschiebbar, solange die Regel „kein Knopf ohne
    // Gitter" gilt.
    final manifest = _manifest('assets/forest/forest_manifest.json');
    final bytes = File('assets/forest/forest_grid.bin.gz').readAsBytesSync();
    final result = _time(
        5,
        () => ForestGrid.decode(
              bytes,
              width: manifest['width'] as int,
              height: manifest['height'] as int,
              west: (manifest['west'] as num).toDouble(),
              east: (manifest['east'] as num).toDouble(),
              north: (manifest['north'] as num).toDouble(),
              south: (manifest['south'] as num).toDouble(),
              referenceYear: manifest['reference_year'] as int,
              hexLonStep: (manifest['hex_lon_step'] as num?)?.toDouble(),
              hexLatStep: (manifest['hex_lat_step'] as num?)?.toDouble(),
            ));
    // ignore: avoid_print
    print('Waldgitter:    ${bytes.length ~/ 1024} KB gepackt · '
        '${result.medianMs} ms (${result.minMs}–${result.maxMs})');
    expect(result.medianMs, lessThan(10000));
  });

  test('Baumarten-Gitter auspacken', () {
    final manifest = _manifest('assets/forest/forest_species_manifest.json');
    final bytes =
        File('assets/forest/forest_species.bin.gz').readAsBytesSync();
    final result = _time(
        5,
        () => ForestSpeciesGrid.decode(
              bytes,
              width: manifest['width'] as int,
              height: manifest['height'] as int,
              west: (manifest['west'] as num).toDouble(),
              east: (manifest['east'] as num).toDouble(),
              north: (manifest['north'] as num).toDouble(),
              south: (manifest['south'] as num).toDouble(),
              referenceYear: manifest['reference_year'] as int,
              hexLonStep: (manifest['hex_lon_step'] as num).toDouble(),
              hexLatStep: (manifest['hex_lat_step'] as num).toDouble(),
            ));
    // ignore: avoid_print
    print('Baumarten:     ${bytes.length ~/ 1024} KB gepackt · '
        '${result.medianMs} ms (${result.minMs}–${result.maxMs})');
    expect(result.medianMs, lessThan(10000));
  });

  group('Regenverlauf an einem Punkt', () {
    final path = Platform.environment['RAIN_DAY_FILE'];
    final available = path != null && File(path).existsSync();

    test('26 Tage für EINEN Spot', () {
      if (!available) {
        // ignore: avoid_print
        print('übersprungen — RAIN_DAY_FILE nicht gesetzt (siehe Kopf).');
        return;
      }
      final day = File(path).readAsBytesSync();
      // Der echte Stapel führt 26 Tage. Dieselbe Datei 26-mal ist für die
      // ZEIT ehrlich: Jeder Tag wird ohnehin einzeln und vollständig
      // ausgepackt, der Inhalt entscheidet nur über die gzip-Rate.
      final days = [
        for (var i = 0; i < 26; i++)
          (date: DateTime(2026, 8, 23).subtract(Duration(days: i)), gzipped: day)
      ];
      final result = _time(
          5,
          () => rainCourseFrom(days,
              width: 800,
              height: 940,
              west: 5.6,
              east: 15.4,
              north: 55.2,
              south: 47.1,
              lat: 47.9025,
              lon: 8.1275));
      // ignore: avoid_print
      print('Regenverlauf:  ${day.length * 26 ~/ 1024} KB gepackt → '
          '${752000 * 26 ~/ 1024 ~/ 1024} MB ausgepackt für 26 gelesene '
          'Bytes · ${result.medianMs} ms '
          '(${result.minMs}–${result.maxMs}) je Spot');
      expect(result.medianMs, lessThan(30000));
    });

    test('hochgerechnet auf 19 eigene Spots', () {
      if (!available) {
        // ignore: avoid_print
        print('übersprungen — RAIN_DAY_FILE nicht gesetzt (siehe Kopf).');
        return;
      }
      // Die Frage hinter dem Ampel-Banner (#277): Was kostet es, beim
      // Öffnen der App für ALLE eigenen Spots zu rechnen? 19 ist der
      // Bestand des Testkontos.
      final day = File(path).readAsBytesSync();
      final days = [
        for (var i = 0; i < 26; i++)
          (date: DateTime(2026, 8, 23).subtract(Duration(days: i)), gzipped: day)
      ];
      final watch = Stopwatch()..start();
      for (var spot = 0; spot < 19; spot++) {
        rainCourseFrom(days,
            width: 800,
            height: 940,
            west: 5.6,
            east: 15.4,
            north: 55.2,
            south: 47.1,
            lat: 47.9 + spot * 0.01,
            lon: 8.1 + spot * 0.01);
      }
      watch.stop();
      final einzeln = watch.elapsedMilliseconds;
      // ignore: avoid_print
      print('19 Spots einzeln:   $einzeln ms — '
          '${19 * 26} Gitter-Dekodierungen für ${19 * 26} gelesene Bytes');

      final points = [
        for (var spot = 0; spot < 19; spot++)
          (lat: 47.9 + spot * 0.01, lon: 8.1 + spot * 0.01)
      ];
      final batched = Stopwatch()..start();
      rainCoursesFrom(days,
          width: 800,
          height: 940,
          west: 5.6,
          east: 15.4,
          north: 55.2,
          south: 47.1,
          points: points);
      batched.stop();
      // ignore: avoid_print
      print('19 Spots gebündelt: ${batched.elapsedMilliseconds} ms — '
          '26 Dekodierungen · Faktor '
          '${(einzeln / batched.elapsedMilliseconds.clamp(1, 1 << 30))
              .toStringAsFixed(1)}');
    });
  });
}
