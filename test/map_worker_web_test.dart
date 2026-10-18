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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/map_worker.dart';
import 'package:pilzbuddy/core/map_worker_web.dart';
import 'package:pilzbuddy/features/map/forest_fill.dart' show allForestClasses;
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/map_worker_tasks.dart';

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
