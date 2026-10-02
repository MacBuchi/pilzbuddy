// Das Zeichen-Isolate der Karte (#641): Jede Zusage hier ist eine Antwort
// auf den Befund vom Pixel XL — Aufträge, die sich stapeln, und Gitter,
// die je Schwenk kopiert werden. Echte Isolates, kein FakeAsync.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/errors.dart';
import 'package:pilzbuddy/core/bounded_compute.dart';
import 'package:pilzbuddy/core/map_worker.dart';

/// Wartet im Isolate, bis die Datei existiert — so lässt sich ein laufender
/// Auftrag festhalten, ohne dass beide Seiten Speicher teilen.
int _waitForFile(MapWorkerSlots slots, String path) {
  while (!File(path).existsSync()) {
    sleep(const Duration(milliseconds: 5));
  }
  return -1;
}

int _echo(MapWorkerSlots slots, int n) => n;

int _sumSlot(MapWorkerSlots slots, int extra) =>
    slots.get<Uint8List>('grid').fold<int>(0, (a, b) => a + b) + extra;

Uint8List _image(MapWorkerSlots slots, int n) => Uint8List(n)..fillRange(0, n, 7);

int _boom(MapWorkerSlots slots, int _) => throw StateError('kaputt');

int _die(MapWorkerSlots slots, int _) {
  Isolate.exit();
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('map_worker'));
  tearDown(() async => tmp.delete(recursive: true));

  test('je Spur gewinnt der neueste: der mittlere Auftrag läuft nie',
      () async {
    final worker = MapWorker.isolate();
    addTearDown(worker.dispose);
    final gate = '${tmp.path}/gate';
    final running = worker.submit('wald', _waitForFile, gate);
    // Erst wenn der erste wirklich läuft, stehen die anderen dahinter.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final middle = worker.submit('wald', _echo, 2);
    final newest = worker.submit('wald', _echo, 3);
    File(gate).writeAsStringSync('');
    expect(await running.result, -1);
    await expectLater(middle.result, throwsA(isA<MapWorkerSuperseded>()));
    expect(await newest.result, 3);
  });

  test('verschiedene Spuren warten nicht aufeinander', () async {
    final worker = MapWorker.isolate();
    addTearDown(worker.dispose);
    final a = worker.submit('wald', _echo, 1);
    final b = worker.submit('fundorte', _echo, 2);
    expect(await Future.wait([a.result, b.result]), [1, 2]);
  });

  test('abgesagt, bevor er lief ⇒ läuft nie', () async {
    final worker = MapWorker.isolate();
    addTearDown(worker.dispose);
    final gate = '${tmp.path}/gate';
    final first = worker.submit('wald', _waitForFile, gate);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final second = worker.submit('wald', _echo, 2)..cancel();
    File(gate).writeAsStringSync('');
    await first.result;
    await expectLater(second.result, throwsA(isA<MapWorkerSuperseded>()));
  });

  test('ein Gitter geht einmal hinüber, ein neues Objekt noch einmal',
      () async {
    final worker = MapWorker.isolate();
    addTearDown(worker.dispose);
    final grid = Uint8List.fromList([1, 2, 3]);
    for (var i = 0; i < 5; i++) {
      final job = worker.submit('wald', _sumSlot, i, slots: {'grid': grid});
      expect(await job.result, 6 + i);
    }
    expect(worker.debugSlotTransfers, 1);
    final other = Uint8List.fromList([10]);
    expect(
        await worker.submit('wald', _sumSlot, 0, slots: {'grid': other}).result,
        10);
    expect(worker.debugSlotTransfers, 2);
  });

  test('ein Bild kommt unverändert zurück', () async {
    final worker = MapWorker.isolate();
    addTearDown(worker.dispose);
    final png = await worker.submit('wald', _image, 1000).result;
    expect(png, hasLength(1000));
    expect(png.every((b) => b == 7), isTrue);
  });

  test('ein Fehler trifft nur seinen Auftrag', () async {
    final worker = MapWorker.isolate();
    addTearDown(worker.dispose);
    await expectLater(worker.submit('wald', _boom, 0).result,
        throwsA(isA<MapWorkerError>().having((e) => e.message, 'message',
            contains('kaputt'))));
    expect(await worker.submit('wald', _echo, 5).result, 5);
  });

  test('stirbt das Isolate, startet das nächste und bekommt die Gitter neu',
      () async {
    final worker = MapWorker.isolate();
    addTearDown(worker.dispose);
    final grid = Uint8List.fromList([4]);
    expect(
        await worker.submit('wald', _sumSlot, 0, slots: {'grid': grid}).result,
        4);
    await expectLater(worker.submit('wald', _die, 0).result,
        throwsA(isA<MapWorkerDied>()));
    expect(
        await worker.submit('wald', _sumSlot, 1, slots: {'grid': grid}).result,
        5,
        reason: 'dasselbe Gitter muss nach dem Neustart wieder hinüber');
  });

  test('stirbt es zu oft, rechnet der Rest über compute — nie gar nicht',
      () async {
    final worker = MapWorker.isolate();
    addTearDown(worker.dispose);
    for (var i = 0; i < kMapWorkerMaxDeaths; i++) {
      await expectLater(worker.submit('wald', _die, 0).result,
          throwsA(isA<MapWorkerDied>()));
    }
    expect(await worker.submit('wald', _echo, 9).result, 9);
    expect(worker.debugUsesFallback, isTrue);
  });

  test('in Ruhe beendet es sich und bekommt die Gitter danach neu',
      () async {
    final worker =
        MapWorker.isolate(idleTimeout: const Duration(milliseconds: 100));
    addTearDown(worker.dispose);
    final grid = Uint8List.fromList([2]);
    expect(
        await worker.submit('wald', _sumSlot, 0, slots: {'grid': grid}).result,
        2);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(worker.debugRetirements, 1);
    expect(worker.debugSlotsHeld, isEmpty, reason: 'Fächer freigegeben');
    expect(
        await worker.submit('wald', _sumSlot, 1, slots: {'grid': grid}).result,
        3);
    expect(worker.debugSlotTransfers, 2, reason: 'nach der Ruhe neu kopiert');
    expect(worker.debugUsesFallback, isFalse,
        reason: 'Ruhe ist kein Tod — kein Rückfall');
  });

  test('ein langer Auftrag wird nicht als Ruhe abgeschossen', () async {
    final worker =
        MapWorker.isolate(idleTimeout: const Duration(milliseconds: 100));
    addTearDown(worker.dispose);
    await worker.submit('wald', _echo, 0).result; // Ruhe-Uhr läuft
    final gate = '${tmp.path}/gate';
    final long = worker.submit('fundorte', _waitForFile, gate);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    File(gate).writeAsStringSync('');
    expect(await long.result, -1);
    expect(worker.debugRetirements, 0);
  });

  test('solange gearbeitet wird, beendet es sich nicht', () async {
    final worker =
        MapWorker.isolate(idleTimeout: const Duration(milliseconds: 100));
    addTearDown(worker.dispose);
    for (var i = 0; i < 6; i++) {
      await worker.submit('wald', _echo, i).result;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    expect(worker.debugRetirements, 0);
  });

  test('ComputeGate: nie mehr als die Grenze zugleich, keiner geht verloren',
      () async {
    final gate = ComputeGate(2);
    var peak = 0;
    final jobs = [
      for (var i = 0; i < 8; i++)
        gate.run(() async {
          if (gate.running > peak) peak = gate.running;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return i;
        }),
    ];
    expect(await Future.wait(jobs), List.generate(8, (i) => i));
    expect(peak, 2);
    expect(gate.running, 0);
  });

  test('Riverpod: fünf Fensterwechsel während einer Rechnung ⇒ zwei Rechnungen',
      () async {
    // Wie beim Schwenken: Der Provider wird je Kamera-Stillstand neu
    // gebaut. Der erste rechnet, die drei mittleren sagt Riverpod ab
    // (verworfen) oder die Spur (ersetzt), der letzte rechnet.
    final ran = <int>[];
    final release = Completer<void>();
    final worker = MapWorker.custom((fn, params, slots) async {
      ran.add(params! as int);
      if (ran.length == 1) await release.future;
      return params;
    });
    final window = StateProvider<int>((ref) => 0);
    final fill = FutureProvider<int>((ref) =>
        runOnMapWorker(ref, 'wald', _echo, ref.watch(window)));
    final container = ProviderContainer(
        overrides: [mapWorkerProvider.overrideWithValue(worker)]);
    addTearDown(container.dispose);
    container.listen(fill, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    for (var i = 1; i <= 4; i++) {
      container.read(window.notifier).state = i;
      container.read(fill); // neu bauen, wie es die Karte tut
      await Future<void>.delayed(Duration.zero);
    }
    release.complete();
    expect(await container.read(fill.future), 4);
    expect(ran, [0, 4]);
  });

  test('Riverpod: Ebene aus, während ein Auftrag wartet ⇒ er rechnet nie',
      () async {
    final ran = <int>[];
    final release = Completer<void>();
    final worker = MapWorker.custom((fn, params, slots) async {
      ran.add(params! as int);
      if (ran.length == 1) await release.future;
      return params;
    });
    final window = StateProvider<int>((ref) => 0);
    final fill = FutureProvider.autoDispose<int>((ref) =>
        runOnMapWorker(ref, 'wald', _echo, ref.watch(window)));
    final container = ProviderContainer(
        overrides: [mapWorkerProvider.overrideWithValue(worker)]);
    addTearDown(container.dispose);
    final sub = container.listen(fill, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    container.read(window.notifier).state = 1;
    container.read(fill); // Auftrag 1 wartet hinter Auftrag 0
    await Future<void>.delayed(Duration.zero);
    sub.close(); // Ebene aus: niemand will das Bild mehr
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ran, [0]);
  });

  test('ein abgesagter Auftrag landet nicht im Wochendigest', () {
    expect(worthReporting(const MapWorkerSuperseded()), isFalse);
    expect(worthReporting(MapWorkerError('x', '')), isTrue,
        reason: 'ein echter Rechenfehler ist ein Befund');
  });
}
