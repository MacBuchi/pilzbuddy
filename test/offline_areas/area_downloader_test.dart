// Der Download eines Kartenbereichs (#630), gegen ein Quellarchiv aus dem
// eigenen Schreiber: Der Plan zählt und misst, der Download holt über den
// `tiles()`-Strom, legt ein Archiv ab, das der Leser beider Engines
// öffnet, meldet Fortschritt, und ein Abbruch hinterlässt nichts.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:pilzbuddy/features/map/online_map.dart';
import 'package:pilzbuddy/features/offline_areas/area_downloader.dart';
import 'package:pilzbuddy/features/offline_areas/area_plan.dart';
import 'package:pilzbuddy/features/offline_areas/area_store.dart';
import 'package:pilzbuddy/features/offline_areas/pmtiles_writer.dart';

const _manifest = MapManifest(
    file: 'dach-20260928.pmtiles', maxZoom: 10, sourceBuild: '20260928');

/// Ein Quellarchiv: Zoom 8–10 über einem Rechteck, das größer ist als der
/// Bereich, den die Tests speichern.
Future<PmTilesArchive> _source() async {
  const wide = AreaBounds(south: 47.0, west: 10.0, north: 48.5, east: 12.5);
  final tiles = [
    for (final t in tilesCovering(wide, maxZoom: 10))
      TileToWrite(t.z, t.x, t.y,
          Uint8List.fromList(utf8.encode('t${t.z}/${t.x}/${t.y}' * (1 + t.x % 4)))),
  ];
  return PmTilesArchive.fromBytes(writePmTiles(
      tiles: tiles,
      tileCompression: Compression.none,
      bounds: const TileBounds(west: 10, south: 47, east: 12.5, north: 48.5)));
}

const _bounds = AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7);

void main() {
  late PmTilesArchive source;
  late MemoryAreaStore store;

  setUp(() async {
    source = await _source();
    store = MemoryAreaStore();
  });

  AreaDownloader make() => AreaDownloader(
        archive: source,
        manifest: _manifest,
        store: store,
        chunkSize: 7,
        now: () => DateTime.utc(2026, 9, 28, 19),
      );

  test('der Plan zählt die Kacheln des Hosts und summiert ihre Bytes',
      () async {
    final plan = await make().plan(const RectShape(_bounds));
    expect(plan.maxZoom, 10);
    expect(plan.tiles, isNotEmpty);
    var expected = 0;
    for (final t in plan.tiles) {
      expected += (await source.lookup(tileIdOf(t)))!.length;
    }
    expect(plan.bytes, expected);
    // Außerhalb der Quelle: keine Kachel, keine Bytes — kein Fehler.
    final sea = await make().plan(const RectShape(
        AreaBounds(south: 30, west: -30, north: 30.1, east: -29.9)));
    expect(sea.tiles, isEmpty);
    expect(sea.bytes, 0);
  });

  test('Download: jede Kachel Byte für Byte, Index, Fortschritt', () async {
    final downloader = make();
    final shape = AreaShape.aroundPoints(
        const [LatLng(47.92, 11.62), LatLng(47.92, 12.30)])!;
    final plan = await downloader.plan(shape);
    final progress = <AreaProgress>[];
    final area = await downloader.download(plan,
        name: 'Um meine Spots', onProgress: progress.add);

    final stored =
        await PmTilesArchive.fromBytes((await store.readArchive(area.id))!);
    expect(stored.header.numberOfAddressedTiles, plan.tiles.length);
    for (final t in plan.tiles) {
      final id = tileIdOf(t);
      expect((await stored.tile(id)).compressedBytes(),
          (await source.tile(id)).compressedBytes());
    }
    expect(area.bytes, greaterThan(0));
    expect(area.build, '20260928');
    expect((await store.list()).single.id, area.id);
    // Die Form bleibt im Index — „Aktualisieren" braucht sie.
    final back = StoredArea.fromJson(area.toJson());
    expect((back.shape as TileSetShape).keys, shape.keys);

    expect(progress.first.writing, isFalse);
    expect(progress.where((p) => !p.writing).last.done, plan.tiles.length);
    expect(progress.last.writing, isTrue);
  });

  test('zu groß wird abgelehnt, bevor eine Kachel nachgeschlagen ist', () {
    const dach = AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5);
    final downloader = AreaDownloader(
        archive: source,
        manifest: const MapManifest(
            file: 'dach-20260928.pmtiles', maxZoom: 13, sourceBuild: '20260928'),
        store: store);
    expect(() => downloader.plan(const RectShape(dach)),
        throwsA(isA<AreaTooLarge>()));
  });

  test('ein Bereich ohne Kachel des Hosts wird nicht geschrieben', () async {
    final downloader = make();
    final sea = await downloader.plan(const RectShape(
        AreaBounds(south: 30, west: -30, north: 30.1, east: -29.9)));
    await expectLater(
        downloader.download(sea, name: 'Meer'), throwsStateError);
    expect(await store.list(), isEmpty);
  });

  test('ein zweiter Bereich mit derselben Id ersetzt den ersten', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    await downloader.download(plan, name: 'A', id: 'x');
    await downloader.download(plan, name: 'B', id: 'x');
    expect((await store.list()).map((a) => a.name), ['B']);
  });

  test('Abbruch: nichts geschrieben, nichts im Index', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    var calls = 0;
    await expectLater(
        downloader.download(plan,
            name: 'Abbruch', isCancelled: () => ++calls > 1),
        throwsA(isA<AreaCancelled>()));
    expect(store.archives, isEmpty);
    expect(await store.list(), isEmpty);
  });
}
