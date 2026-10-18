// Der Weg des Browsers (#689, B2) auf der VM: Im Web Worker reisen keine
// Dart-Objekte, nur Bytes. Jede Rechnung des Zeichen-Wegs muss deshalb
// über ihre Codecs GENAU das rechnen, was sie mit den Objekten selbst
// rechnet — sonst malte der Browser still ein anderes Bild als Android.
//
// Bewiesen wird es dreifach: das Format selbst (Ausrichtung, Grenzen),
// je Typ ein Rundlauf Feld für Feld, und jede Rechnung einmal direkt und
// einmal über Codecs und `MapWorkerHost` — Bild gegen Bild.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/core/map_worker.dart';
import 'package:pilzbuddy/core/map_worker_host.dart';
import 'package:pilzbuddy/core/map_worker_transport.dart';
import 'package:pilzbuddy/core/wire.dart';
import 'package:pilzbuddy/data/rain_stack_data.dart';
import 'package:pilzbuddy/features/ampel/ampel_fill.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/map/contours.dart';
import 'package:pilzbuddy/features/map/elevation_contours.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/forest_fill.dart' show allForestClasses;
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/gbif_fill.dart';
import 'package:pilzbuddy/features/map/map_worker_tasks.dart';
import 'package:pilzbuddy/features/map/protected_areas.dart';
import 'package:pilzbuddy/features/offline_areas/area_tile_key.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';

import 'elevation_contours_test.dart' show elevationOf;
import 'forest_ampel_fill_test.dart' show levelsOf;
import 'forest_grid_test.dart' show hexOf;
import 'gbif_finds_test.dart' show findsOf;
import 'rain_grid_test.dart' show encode;

T roundTrip<T>(WireCodec<T> codec, T value) {
  final bytes = codec.encode(value);
  return codec.decode(bytes.buffer, bytes.length);
}

/// Die Leitung des Browsers ohne Browser: kodiert wie `map_worker_web.dart`
/// und rechnet im echten [MapWorkerHost].
class _Loopback implements MapWorkerTransport {
  _Loopback(this.host);
  final MapWorkerHost host;
  MapWorkerReplies? _replies;
  int jobs = 0;

  @override
  Future<void> open(MapWorkerReplies replies) async => _replies = replies;

  @override
  void slot(MapWorkerTask<Object?, Object?> task, String name,
          Object? value) =>
      host.slot(task.id, name, task.slotCodec(name).encode(value));

  @override
  void drop(String name) => host.drop(name);

  @override
  void job(int id, MapWorkerTask<Object?, Object?> task, Object? params) {
    jobs++;
    final encoded = task.encodeParams(params);
    scheduleMicrotask(() {
      try {
        _replies!.result(id, task.decodeResult(host.run(task.id, encoded)));
      } catch (e, s) {
        _replies!.error(id, '$e', '$s');
      }
    });
  }

  @override
  void close() => _replies = null;
}

void main() {
  final random = math.Random(689);
  Uint8List bytesOf(int n, int max) =>
      Uint8List.fromList(List.generate(n, (_) => random.nextInt(max)));

  group('Format', () {
    test('typisierte Felder kommen auch nach ungerader Länge ausgerichtet an',
        () {
      final w = WireWriter(8) // klein: zwingt mehrfaches Wachsen
        ..u8(1)
        ..float32s(Float32List.fromList([1.5, -2.25]))
        ..u8(2)
        ..int16s(Int16List.fromList([-300, 400]))
        ..u8(3)
        ..float64s(Float64List.fromList([math.pi]))
        ..uint16s(Uint16List.fromList([65535]))
        ..int32s(Int32List.fromList([-1 << 31]))
        ..string('Stäubling — ä')
        ..int64(1 << 52)
        ..int64(-123456789)
        ..dateTime(DateTime.utc(2026, 10, 18, 7, 30))
        ..dateTime(DateTime(2026, 10, 18))
        ..nullable<int>(null, (_) {});
      final out = w.finish();
      final r = WireReader(out.buffer, out.length);
      expect(r.u8(), 1);
      expect(r.float32s(), [1.5, -2.25]);
      expect(r.u8(), 2);
      expect(r.int16s(), [-300, 400]);
      expect(r.u8(), 3);
      expect(r.float64s(), [math.pi]);
      expect(r.uint16s(), [65535]);
      expect(r.int32s(), [-1 << 31]);
      expect(r.string(), 'Stäubling — ä');
      expect(r.int64(), 1 << 52);
      expect(r.int64(), -123456789);
      expect(r.dateTime(), DateTime.utc(2026, 10, 18, 7, 30));
      final local = r.dateTime();
      expect(local, DateTime(2026, 10, 18));
      expect(local.isUtc, isFalse);
      expect(r.nullable(r.int64), isNull);
      expect(r.done, isTrue, reason: 'nichts geschrieben, was keiner liest');
    });

    test('eine Sicht mitten aus einem größeren Feld reist nur mit sich selbst',
        () {
      final big = Uint16List.fromList(List.generate(100, (i) => i));
      final view = Uint16List.sublistView(big, 10, 13);
      final w = WireWriter()..uint16s(view);
      final out = w.finish();
      expect(WireReader(out.buffer, out.length).uint16s(), [10, 11, 12]);
    });
  });

  group('je Typ: jedes Feld kommt zurück', () {
    test('FillWindow, Wald, Höhe', () {
      const window = FillWindow(
          west: 10.1, east: 10.9, north: 50.7, south: 50.2,
          width: 333, height: 222);
      final w = roundTrip(fillWindowCodec, window);
      expect([w.west, w.east, w.north, w.south, w.width, w.height],
          [10.1, 10.9, 50.7, 50.2, 333, 222]);

      final forest = hexOf([
        [1, 11, 21],
        [31, 41, 51],
      ]);
      final f = roundTrip(forestGridCodec, forest);
      expect(
          [f.values, f.width, f.height, f.west, f.east, f.north, f.south,
            f.referenceYear, f.hexLonStep, f.hexLatStep],
          [forest.values, 3, 2, forest.west, forest.east, forest.north,
            forest.south, 2024, 0.004, 0.003]);
      final square = roundTrip(forestGridCodec, ForestGrid(
          values: Uint8List(1), width: 1, height: 1, west: 1, east: 2,
          north: 3, south: 0, referenceYear: 2020));
      expect(square.isHex, isFalse, reason: 'null bleibt null');

      final elevation = elevationOf([
        [1, 2],
        [3, 4],
      ], west: 9.5, north: 47.5, lonStep: 0.02, latStep: 0.015);
      final e = roundTrip(elevationGridCodec, elevation);
      expect(
          [e.values, e.width, e.height, e.west, e.east, e.north, e.south,
            e.hexLonStep, e.hexLatStep],
          [elevation.values, 2, 2, 9.5, elevation.east, 47.5,
            elevation.south, 0.02, 0.015]);
    });

    test('Schutzgebiete', () {
      final areas = ProtectedAreas(
        width: 5,
        height: 2,
        west: 9,
        north: 48,
        lonStep: 0.1,
        latStep: 0.05,
        rows: [
          Uint16List.fromList([0, 2, 1]),
          Uint16List.fromList([1, 3, 2]),
        ],
        areas: const [
          ProtectedArea(kind: ProtectedKind.coreZone, name: 'Kern'),
          ProtectedArea(kind: ProtectedKind.natureReserve, name: ''),
        ],
        extract: '2026-09-23',
      );
      final p = roundTrip(protectedAreasCodec, areas);
      expect([p.width, p.height, p.west, p.north, p.lonStep, p.latStep,
          p.rows, p.extract], [5, 2, 9, 48, 0.1, 0.05, areas.rows,
          '2026-09-23']);
      expect([for (final a in p.areas) (a.kind, a.name)], [
        (ProtectedKind.coreZone, 'Kern'),
        (ProtectedKind.natureReserve, ''),
      ]);
    });

    test('Ampel-Stufen samt aller wahlweisen Felder', () {
      final grid = AmpelLevelGrid(
        rainFactor: Float32List.fromList([0.25, 0.5]),
        meanC: Float32List.fromList([12.5, 13]),
        stationHeightM: Int16List.fromList([-5, 1800]),
        valid: Uint8List.fromList([1, 0]),
        moistureMean: Float32List.fromList([0.3, 0.4]),
        moistureValid: Uint8List.fromList([0, 1]),
        milder: Float32List.fromList([-1.5, 2]),
        milderValid: Uint8List.fromList([1, 1]),
        width: 2,
        height: 1,
        west: 6,
        east: 17,
        north: 55,
        south: 45,
        newest: DateTime.utc(2026, 10, 17),
      );
      final l = roundTrip(ampelLevelsCodec, AmpelLevels([grid, grid]));
      expect(l.grids, hasLength(2));
      final g = l.grids.last;
      expect(
          [g.rainFactor, g.meanC, g.stationHeightM, g.valid, g.moistureMean,
            g.moistureValid, g.milder, g.milderValid, g.width, g.height,
            g.west, g.east, g.north, g.south, g.newest],
          [grid.rainFactor, grid.meanC, grid.stationHeightM, grid.valid,
            grid.moistureMean, grid.moistureValid, grid.milder,
            grid.milderValid, 2, 1, 6, 17, 55, 45, grid.newest]);
    });

    test('Wald-Auftrag mit allen ausgelieferten Ampel-Klassen', () {
      // Die Klassen vergleicht das Ampel-Gedächtnis nach Inhalt
      // (`ampelSameClasses`) — kommen sie verändert an, rechnet der
      // Worker jedes Bild neu, und mit einem verlorenen Logit falsch.
      expect(ampelShippedClasses.where((c) => c.logit != null), isNotEmpty,
          reason: 'sonst prüfte der Test das Logit nicht');
      final params = (
        classes: {ForestClass.mixed, ForestClass.conifer},
        window: const FillWindow(
            west: 1, east: 2, north: 3, south: 0, width: 4, height: 5),
        ampelClasses: ampelShippedClasses,
        blocks: ['forestBlock#a', 'forestBlock#b'],
      );
      final p = roundTrip(forestFillParamsCodec, params);
      expect(p.classes, params.classes);
      expect(p.blocks, params.blocks);
      expect(ampelSameClasses(p.ampelClasses!, ampelShippedClasses), isTrue);
      for (final (i, c) in p.ampelClasses!.indexed) {
        final o = ampelShippedClasses[i];
        expect(
            [c.name, c.optimumC, c.verhaltenAbove, c.guenstigAbove,
              c.logit?.rain, c.logit?.temp, c.logit?.temp2,
              c.logit?.moisture, c.logit?.moistureTemp, c.logit?.milder],
            [o.name, o.optimumC, o.verhaltenAbove, o.guenstigAbove,
              o.logit?.rain, o.logit?.temp, o.logit?.temp2,
              o.logit?.moisture, o.logit?.moistureTemp, o.logit?.milder]);
      }
      expect(roundTrip(forestFillParamsCodec,
              (classes: params.classes, window: params.window,
                ampelClasses: null, blocks: const <String>[]))
          .ampelClasses, isNull);
    });

    test('Fundorte', () {
      final finds = findsOf([
        (species: 0, lat: 51.0, lon: 10.0, uncertaintyM: 25, count: 1,
          year: 2024),
        (species: 1, lat: 48.0, lon: 12.0, uncertaintyM: null, count: 11,
          year: null),
      ], species: ['Steinpilz', 'Rotkappe']);
      final g = roundTrip(gbifFindsCodec, finds);
      expect(
          [g.speciesIndex, g.latQ, g.lonQ, g.uncertaintyM, g.count,
            g.yearOffset, g.species, g.datasets, g.countries, g.west, g.east,
            g.north, g.south, g.observations, g.unknownUncertaintyM, g.doi,
            g.fetchedOn],
          [finds.speciesIndex, finds.latQ, finds.lonQ, finds.uncertaintyM,
            finds.count, finds.yearOffset, finds.species, finds.datasets,
            finds.countries, finds.west, finds.east, finds.north,
            finds.south, finds.observations, finds.unknownUncertaintyM,
            finds.doi, finds.fetchedOn]);
    });

    test('Regenstapel und Regenverlauf', () {
      final stack = RainStackData(
        kind: RainStackKind.alps,
        info: RainStackInfo(
          width: 2,
          height: 1,
          west: 10,
          east: 14,
          north: 55,
          south: 47,
          days: [
            RainStackDay(
                date: DateTime.utc(2026, 10, 1),
                file: 'alps_rain_20261001.bin.gz',
                sha256: 'abc',
                origin: 'alps_origin_20261001.bin.gz',
                originSha256: 'def'),
            RainStackDay(date: DateTime.utc(2026, 10, 2), file: 'b'),
          ],
        ),
        days: [
          (date: DateTime.utc(2026, 10, 1), gzipped: const [1, 2, 3]),
        ],
        origins: [
          (date: DateTime.utc(2026, 10, 1), gzipped: Uint8List(2)),
        ],
      );
      final s = roundTrip(rainStackDataCodec, stack);
      expect(s.kind, RainStackKind.alps);
      final i = s.info;
      expect([i.width, i.height, i.west, i.east, i.north, i.south],
          [2, 1, 10, 14, 55, 47]);
      expect(
          [for (final d in i.days)
            [d.date, d.file, d.sha256, d.origin, d.originSha256]],
          [
            [DateTime.utc(2026, 10, 1), 'alps_rain_20261001.bin.gz', 'abc',
              'alps_origin_20261001.bin.gz', 'def'],
            [DateTime.utc(2026, 10, 2), 'b', null, null, null],
          ]);
      expect([for (final d in s.days) [d.date, d.gzipped]], [
        [DateTime.utc(2026, 10, 1), [1, 2, 3]]
      ]);
      expect([for (final d in s.origins) [d.date, d.gzipped]], [
        [DateTime.utc(2026, 10, 1), [0, 0]]
      ]);

      final course = RainCourse([
        RainDay(date: DateTime.utc(2026, 10, 1), mm: 12,
            source: RainSource.alps, origin: 5),
        RainDay(date: DateTime.utc(2026, 10, 2), mm: null),
      ]);
      final c = roundTrip(rainCourseCodec, course);
      expect([for (final d in c.days) (d.date, d.mm, d.source, d.origin)], [
        (DateTime.utc(2026, 10, 1), 12, RainSource.alps, 5),
        (DateTime.utc(2026, 10, 2), null, RainSource.radar, 0),
      ]);
    });

    test('Höhenlinien samt GeoJSON', () {
      const contours = ElevationContours(
        lines: [
          ContourLine(
              level: 1200,
              points: [LatLng(47.1, 11.2), LatLng(47.3, 11.4)],
              cells: 17,
              index: true),
          ContourLine(level: 1220, points: [], cells: 0),
        ],
        equidistanceM: 20,
        key: 'fenster_20',
        geoJson: (normal: '{"a":1}', index: '{"b":2}'),
      );
      final c = roundTrip(elevationContoursCodec, contours);
      expect([for (final l in c.lines) (l.level, l.cells, l.index)],
          [(1200, 17, true), (1220, 0, false)]);
      expect([for (final l in c.lines) l.points], [
        const [LatLng(47.1, 11.2), LatLng(47.3, 11.4)],
        const <LatLng>[],
      ]);
      expect([c.equidistanceM, c.key, c.geoJson],
          [20, 'fenster_20', (normal: '{"a":1}', index: '{"b":2}')]);
    });
  });

  group('jede Rechnung: über Codecs dasselbe wie direkt', () {
    // Ein Wald aus 24×18 Waben über allen drei Klassen, Höhe auf demselben
    // Raster (Direktindex), Stufen-Gitter darüber.
    final rows = [
      for (var y = 0; y < 18; y++) [for (var x = 0; x < 24; x++) 1 + random.nextInt(100)],
    ];
    final forest = hexOf(rows);
    final elevation = ElevationGrid(
      values: bytesOf(forest.values.length, 120),
      width: forest.width,
      height: forest.height,
      west: forest.west,
      east: forest.east,
      north: forest.north,
      south: forest.south,
      hexLonStep: forest.hexLonStep!,
      hexLatStep: forest.hexLatStep!,
    );
    final levels = levelsOf([
      for (var y = 0; y < 6; y++)
        [
          for (var x = 0; x < 6; x++)
            AmpelLevel.values[random.nextInt(AmpelLevel.values.length)],
        ],
    ], west: forest.west, east: forest.east, north: forest.north,
        south: forest.south);
    final protected = ProtectedAreas(
      width: forest.width,
      height: forest.height,
      west: forest.west,
      north: forest.north,
      lonStep: forest.hexLonStep!,
      latStep: forest.hexLatStep!,
      rows: [
        for (var y = 0; y < forest.height; y++)
          y.isEven ? Uint16List.fromList([3, 6, 1]) : Uint16List(0),
      ],
      areas: const [
        ProtectedArea(kind: ProtectedKind.natureReserve, name: 'Test'),
      ],
    );
    final window = FillWindow(
        west: forest.west,
        east: forest.east,
        north: forest.north,
        south: forest.south,
        width: 240,
        height: 160);

    late MapWorkerHost host;
    late _Loopback loopback;
    late MapWorker worker;
    setUp(() {
      host = MapWorkerHost(mapWorkerTasks);
      loopback = _Loopback(host);
      worker = MapWorker.transport(() => loopback);
    });
    tearDown(() => worker.dispose());

    Future<void> same<P, R>(MapWorkerTask<P, R> task, P params,
        Map<String, Object?> slots) async {
      final direct = task.run(MapWorkerSlots(slots), params);
      final viaWire =
          await worker.submit('probe', task, params, slots: slots).result;
      if (direct is Uint8List) {
        expect(direct.length, greaterThan(100), reason: 'ein echtes Bild');
      }
      final codec = task.result;
      expect(codec.encode(viaWire).buffer.asUint8List(
              0, codec.encode(viaWire).length),
          codec.encode(direct).buffer.asUint8List(
              0, codec.encode(direct).length),
          reason: task.id);
    }

    test('Wald grob, mit und ohne Ampel', () async {
      final params = (
        classes: allForestClasses,
        window: window,
        ampelClasses: ampelShippedClasses,
        blocks: const <String>[],
      );
      await same(forestFillTask, params,
          {'forest': forest, 'protected': protected});
      await same(forestAmpelFillTask, params, {
        'forest': forest,
        'protected': protected,
        'ampelLevels': levels,
        'elevation': elevation,
      });
      await same(forestAmpelFillTask, params, {
        'forest': forest,
        'protected': null,
        'ampelLevels': levels,
        'elevation': null,
      });
      expect(loopback.jobs, 3, reason: 'jede lief wirklich über die Leitung');
    });

    test('Wald fein: Blöcke als Familie, hinausgefallene werden frei',
        () async {
      final a = hexOf(rows.sublist(0, 9));
      final b = hexOf(rows.sublist(9));
      ({
        Set<ForestClass> classes,
        FillWindow window,
        List<AmpelClass>? ampelClasses,
        List<String> blocks
      }) paramsOf(List<String> blocks) => (
            classes: allForestClasses,
            window: window,
            ampelClasses: ampelShippedClasses,
            blocks: blocks,
          );
      await same(forestFillFineTask, paramsOf(['forestBlock#a', 'forestBlock#b']),
          {'forestBlock#a': a, 'forestBlock#b': b, 'protected': protected});
      await same(forestAmpelFillFineTask, paramsOf(['forestBlock#b']), {
        'forestBlock#b': b,
        'protected': protected,
        'ampelLevels': levels,
        'elevation': elevation,
      });
      expect(host.slotNames, isNot(contains('forestBlock#a')),
          reason: 'der Worker hält nur die Blöcke des Fensters');
      expect(host.slotNames, contains('forestBlock#b'));
    });

    test('Fundorte, Bereichs-Entwurf, Höhenlinien, Regenverlauf', () async {
      final finds = findsOf([
        for (var i = 0; i < 40; i++)
          (
            species: i % 2,
            lat: forest.south + random.nextDouble() * (forest.north - forest.south),
            lon: forest.west + random.nextDouble() * (forest.east - forest.west),
            uncertaintyM: i.isEven ? 30 : null,
            count: 1 + i % 3,
            year: 2020,
          ),
      ], species: ['Steinpilz', 'Pfifferling']);
      await same(gbifFillTask, (window: window, paint: gbifPaintFor(finds)),
          {'gbifFinds': finds});

      const areaWindow = FillWindow(
          west: 11.5, east: 11.7, north: 47.3, south: 47.2,
          width: 200, height: 160);
      int keyAt(double lat, double lon) {
        const n = 1 << kAreaShapeZoom;
        final x = ((lon + 180) / 360 * n).floor();
        final r = lat * math.pi / 180;
        final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
                2 *
                n)
            .floor();
        return areaTileKey(x, y, kAreaShapeZoom);
      }
      await same(areaEditFillTask, (
        window: areaWindow,
        adds: {keyAt(47.25, 11.55)},
        removes: {keyAt(47.28, 11.62)},
      ), {
        'areaStored': {keyAt(47.28, 11.62), keyAt(47.22, 11.65)},
      });

      final middle = 9.5;
      final cone = elevationOf([
        for (var y = 0; y < 20; y++)
          [
            for (var x = 0; x < 20; x++)
              math.max(
                  0,
                  12 -
                      math
                          .sqrt((x - middle) * (x - middle) +
                              (y - middle) * (y - middle))
                          .round()),
          ],
      ]);
      final contourParams = (
        window: FillWindow(
            west: cone.west, east: cone.east, north: cone.north,
            south: cone.south, width: 256, height: 256),
        metersPerPixel: 5.0,
      );
      final contours = await worker
          .submit('probe', contoursTask, contourParams,
              slots: {'elevation': cone})
          .result;
      expect(contours!.lines, isNotEmpty);
      expect(contours.geoJson, isNotNull,
          reason: 'GeoJSON im selben Auftrag, kein zweiter Weg');
      await same(contoursTask, contourParams, {'elevation': cone});

      List<int> day(int mm) => encode([
            [mm, 255]
          ]);
      final stacks = [
        RainStackData(
          info: const RainStackInfo(
              width: 2, height: 1, west: 10, east: 14, north: 55,
              south: 47, days: []),
          days: [
            for (var d = 0; d < 5; d++)
              (date: DateTime.utc(2026, 10, 1 + d), gzipped: day(d * 3)),
          ],
        ),
      ];
      await same(legendRainCourseTask, (lat: 51.0, lon: 11.0),
          {'rainStacks': stacks});
    });

    test('ein Fehler im Worker trifft nur den Auftrag', () async {
      await expectLater(
          worker.submit('probe', forestFillTask, (
            classes: allForestClasses,
            window: window,
            ampelClasses: null,
            blocks: const <String>[],
          ), slots: {'protected': null}).result,
          throwsA(isA<MapWorkerError>()),
          reason: 'das Fach „forest" fehlt');
      await same(forestFillTask, (
        classes: allForestClasses,
        window: window,
        ampelClasses: null,
        blocks: const <String>[],
      ), {'forest': forest, 'protected': null});
    });
  });

  test('jede Rechnung steht im Register, jede Kennung einmal', () {
    // Eine Rechnung, die nicht im Register steht, kennt der Worker nicht —
    // im Browser schlüge dann jeder ihrer Aufträge fehl.
    final ids = [for (final t in mapWorkerTasks) t.id];
    expect(ids.toSet(), hasLength(ids.length));
    final declared = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final m
          in RegExp(r'(?:const|final) (\w+) =\s*MapWorkerTask<').allMatches(source)) {
        declared.add('${file.path}:${m.group(1)}');
      }
    }
    expect(declared, hasLength(mapWorkerTasks.length));
    expect(declared,
        everyElement(startsWith('lib/features/map/map_worker_tasks.dart:')),
        reason: 'Rechnungen gehören in die Flutter-freie Datei');
  });
}
