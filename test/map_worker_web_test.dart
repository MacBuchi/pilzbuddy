// Der Zeichen-Worker im echten Browser (#689, B2) — die eine Stelle, an
// der bewiesen wird, dass im Web wirklich ein Web Worker rechnet und nicht
// still der Hauptthread.
//
// Läuft NUR auf dart2js, gegen den übersetzten Worker:
//
//     dart compile js -O2 -o test/map_worker_js/map_worker.js \
//         lib/map_worker_main.dart
//     dart compile js -O2 -DMAP_WORKER_BUILD=fremd \
//         -o test/map_worker_js/fremd.js lib/map_worker_main.dart
//     flutter test --platform chrome test/map_worker_web_test.dart
//
// Der Testlauf liefert Dateien unter `test/` aus (`map_worker_js/…`
// relativ zur Seite); `build/` und versteckte Ordner liefert er nicht.
//
// **Ein grünes Bild allein beweist nichts:** Fiele die Leitung auf den
// Hauptthread zurück, käme dasselbe Bild. Bewiesen wird deshalb über
// `resultsFromWorker` (die Antwort kam als Nachricht des Workers) und
// `debugUsesFallback` — und die Gegenprobe, dass ein fehlender oder
// fremder Worker GENAU dorthin zurückfällt.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipEncoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:pilzbuddy/core/map_worker.dart';
import 'package:pilzbuddy/core/map_worker_web.dart';
import 'package:pilzbuddy/features/map/forest_fill.dart' show allForestClasses;
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/data/rain_stack_data.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart'
    show ampelShippedClasses;
import 'package:pilzbuddy/features/map/map_worker_tasks.dart';
import 'package:pilzbuddy/features/map/spot_weather.dart'
    show AirStation, WeatherTable;

import 'rain_grid_test.dart' show encode;

void main() {
  final forest = ForestGrid(
    values: Uint8List.fromList(
        List.generate(24 * 18, (i) => 1 + (i * 37) % 100)),
    width: 24,
    height: 18,
    west: 10,
    east: 10 + 0.004 * 24.5,
    north: 50,
    south: 50 - 0.003 * 19,
    referenceYear: 2024,
    hexLonStep: 0.004,
    hexLatStep: 0.003,
  );
  final params = (
    classes: allForestClasses,
    window: FillWindow(
        west: forest.west,
        east: forest.east,
        north: forest.north,
        south: forest.south,
        width: 240,
        height: 160),
    ampelClasses: null,
    blocks: const <String>[],
  );
  final slots = {'forest': forest, 'protected': null};
  final direct =
      forestFillTask.run(MapWorkerSlots(slots), params);

  Future<({MapWorker worker, WebWorkerTransport transport})> start(
      String url) async {
    final transport = WebWorkerTransport(url);
    final worker = MapWorker.transport(() => transport);
    addTearDown(worker.dispose);
    return (worker: worker, transport: transport);
  }

  test('das Waldbild rechnet im Worker und gleicht dem direkten', () async {
    final (:worker, :transport) = await start('map_worker_js/map_worker.js');
    for (var i = 0; i < 3; i++) {
      final png = await worker
          .submit('wald', forestFillTask, params, slots: slots)
          .result;
      expect(png, direct);
    }
    expect(transport.resultsFromWorker, 3,
        reason: 'jede Antwort kam aus dem Worker');
    expect(worker.debugUsesFallback, isFalse);
    expect(worker.debugSlotTransfers, 2,
        reason: 'Wald und Schutzgebiete gingen EINMAL hinüber');
  });

  test('der Worker lädt ein Gitter selbst: fetch, nativ entpackt, als Fach',
      () async {
    // Wie im Build, nur über eine blob:-Adresse statt eines Assets — der
    // Testlauf liefert `assets/` nicht aus. Bewiesen wird der ganze Weg
    // drüben: Abruf, DecompressionStream, Dekodierer, Fach, und dass das
    // Gitter danach nie vom Hauptthread hinübergeht (#689, B3).
    final deltas = Uint8List(forest.values.length);
    for (var y = 0; y < forest.height; y++) {
      var previous = 0;
      for (var x = 0; x < forest.width; x++) {
        final v = forest.values[y * forest.width + x];
        deltas[y * forest.width + x] = (v - previous) & 0xFF;
        previous = v;
      }
    }
    final gz = Uint8List.fromList(GZipEncoder().encode(deltas)!);
    final url = web.URL.createObjectURL(
        web.Blob(<web.BlobPart>[gz.toJS].toJS));
    addTearDown(() => web.URL.revokeObjectURL(url));
    final manifest = jsonEncode({
      'lattice': 'hex-odd-r',
      'width': forest.width,
      'height': forest.height,
      'west': forest.west,
      'east': forest.east,
      'north': forest.north,
      'south': forest.south,
      'reference_year': forest.referenceYear,
      'hex_lon_step': forest.hexLonStep,
      'hex_lat_step': forest.hexLatStep,
    });

    final transport = WebWorkerTransport('map_worker_js/map_worker.js');
    final worker = MapWorker.transport(() => transport, loadsAssets: true);
    addTearDown(worker.dispose);
    final loaded = await worker.loadAsset(forestLoad,
        slot: 'forest', manifest: manifest, url: url);
    expect(loaded!.values, forest.values);
    expect(transport.resultsFromWorker, 1, reason: 'aus dem Worker');

    final loadedSlots = {'forest': loaded, 'protected': null};
    expect(
        await worker
            .submit('wald', forestFillTask, params, slots: loadedSlots)
            .result,
        direct);
    expect(worker.debugSlotTransfers, 1,
        reason: 'nur die Schutzgebiete gingen hinüber, der Wald lag dort');
    expect(worker.debugUsesFallback, isFalse);
  });

  test('die Ampel-Stufen rechnen im Worker und bleiben dort als Fach '
      '(#689, B3)', () async {
    // Bis 1.226.x blockierte genau diese Rechnung im Browser den
    // Hauptthread 13 s am Stück. Bewiesen wird: Die Antwort kommt aus dem
    // Worker, sie gleicht der direkten Rechnung, und die Ampel-Fläche
    // danach schickt die Stufen nicht wieder hinüber.
    final stacks = [
      RainStackData(
        info: const RainStackInfo(
            width: 3, height: 2, west: 9.5, east: 10.5, north: 50.5,
            south: 49.5, days: []),
        days: [
          for (var i = 0; i < 26; i++)
            (
              date: DateTime.utc(2026, 10, 1).add(Duration(days: i)),
              gzipped: encode([
                [i % 4, 2, 9],
                [0, 5, 3],
              ]),
            ),
        ],
      ),
    ];
    final table = WeatherTable(
      days: [
        for (var i = 0; i < 28; i++)
          DateTime.utc(2026, 9, 29).add(Duration(days: i)),
      ],
      air: [
        AirStation(name: 'A', lat: 50, lon: 10, height: 300,
            max: List.filled(28, 17.0), min: List.filled(28, 9.0)),
      ],
      soil: const [],
    );
    final ampelSlots = {
      'rainStacks': stacks,
      'weatherTable': table,
      'soilMoisture': null,
    };
    final expected =
        ampelLevelsTask.run(MapWorkerSlots(ampelSlots), null)!;

    final (:worker, :transport) = await start('map_worker_js/map_worker.js');
    final levels = (await worker
        .submit('ampel', ampelLevelsTask, null, slots: ampelSlots)
        .result)!;
    expect(transport.resultsFromWorker, 1, reason: 'aus dem Worker');
    expect(
        [for (final g in levels.grids) [g.rainFactor, g.meanC, g.valid]],
        [for (final g in expected.grids) [g.rainFactor, g.meanC, g.valid]]);

    final sent = worker.debugSlotTransfers;
    await worker.submit('wald', forestAmpelFillTask, (
      classes: allForestClasses,
      window: params.window,
      ampelClasses: ampelShippedClasses,
      blocks: const <String>[],
    ), slots: {
      'forest': forest,
      'protected': null,
      'ampelLevels': levels,
      'elevation': null,
    }).result;
    expect(worker.debugSlotTransfers - sent, 3,
        reason: 'Wald, Schutzgebiete, Höhe — die Stufen lagen schon drüben');
    expect(worker.debugUsesFallback, isFalse);
  });

  test('ein Fehler im Worker trifft nur seinen Auftrag', () async {
    final (:worker, :transport) = await start('map_worker_js/map_worker.js');
    await expectLater(
        worker.submit('wald', forestFillTask, params,
            slots: {'protected': null}).result,
        throwsA(isA<MapWorkerError>()));
    expect(await worker
        .submit('wald', forestFillTask, params, slots: slots)
        .result, direct);
    expect(worker.debugUsesFallback, isFalse);
  });

  test('Gegenprobe: ohne Worker rechnet die Seite selbst — dasselbe Bild',
      () async {
    final (:worker, :transport) = await start('map_worker_js/fehlt.js');
    expect(await worker
        .submit('wald', forestFillTask, params, slots: slots)
        .result, direct);
    expect(transport.resultsFromWorker, 0);
    expect(worker.debugUsesFallback, isTrue);
  });

  test('ein Worker aus einem anderen Build wird nicht benutzt', () async {
    // Nach einem Deploy kann der HTTP-Cache den alten Worker zur neuen
    // App liefern — andere Codecs, und das läse sich als Unsinn.
    final (:worker, :transport) = await start('map_worker_js/fremd.js');
    expect(await worker
        .submit('wald', forestFillTask, params, slots: slots)
        .result, direct);
    expect(transport.resultsFromWorker, 0);
    expect(worker.debugUsesFallback, isTrue);
  });
}
