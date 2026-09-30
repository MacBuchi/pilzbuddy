// Zeichnen, Radieren und Beschneiden der Kartenbereiche (#630, Stufe 2b):
// welche Kacheln ein Strich trifft, die Umrechnung vom Bildschirm, der
// Entwurf gegen den gespeicherten Bestand, das Herausschreiben ohne Netz
// und das Bild, das beides auf der Karte zeigt.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart';
import 'package:pilzbuddy/features/offline_areas/area_draw.dart';
import 'package:pilzbuddy/features/offline_areas/area_edit_fill.dart';
import 'package:pilzbuddy/features/offline_areas/area_plan.dart';
import 'package:pilzbuddy/features/offline_areas/area_providers.dart';
import 'package:pilzbuddy/features/offline_areas/area_store.dart';
import 'package:pilzbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:pmtiles/pmtiles.dart';

int _key(int x, int y) => TileSetShape.keyOf(x, y, kAreaShapeZoom);

LatLng _centre(int x, int y) =>
    tileBounds(kAreaShapeZoom, x, y).center;

/// Ein Bereich aus Kacheln bei Zoom 13, samt Archiv (Zoom 8–13).
Future<StoredArea> _area(MemoryAreaStore store, String id, Set<int> keys) async {
  final shape = TileSetShape(zoom: kAreaShapeZoom, keys: keys);
  final tiles = shape.tiles(maxZoom: kAreaShapeZoom);
  final hull = shape.hull;
  final bytes = writePmTiles(
      tiles: [
        for (final t in tiles)
          TileToWrite(t.z, t.x, t.y,
              Uint8List.fromList(utf8.encode('t${t.z}/${t.x}/${t.y}'))),
      ],
      tileCompression: Compression.none,
      bounds: TileBounds(
          west: hull.west, south: hull.south, east: hull.east, north: hull.north));
  await store.putArchive(id, bytes);
  final area = StoredArea(
    id: id,
    name: id,
    shape: shape,
    bounds: hull,
    minZoom: kAreaMinZoom,
    maxZoom: kAreaShapeZoom,
    build: '20260928',
    tiles: tiles.length,
    bytes: bytes.length,
    savedAt: DateTime.utc(2026, 9, 30),
  );
  store.areas = [...store.areas, area];
  return area;
}

void main() {
  group('tilesTouchedByRing', () {
    test('ein Ring um neun Kacheln trifft alle neun, auch die Mitte', () {
      // Von der Mitte der Kachel (100,100) zur Mitte von (102,102): Der
      // Rand läuft durch acht, die neunte liegt nur innen.
      final ring = [
        _centre(100, 100),
        _centre(102, 100),
        _centre(102, 102),
        _centre(100, 102),
      ];
      final keys = tilesTouchedByRing(ring, zoom: kAreaShapeZoom)!;
      expect(keys, {
        for (var x = 100; x <= 102; x++)
          for (var y = 100; y <= 102; y++) _key(x, y),
      });
    });

    test('ein Strich über halb Europa wird nicht ausgewertet', () {
      final ring = [const LatLng(60, -10), const LatLng(35, 30)];
      expect(tilesTouchedByRing(ring), isNull);
    });

    test('ein Punkt ist kein Strich', () {
      expect(tilesTouchedByRing([const LatLng(47.9, 11.6)]), isEmpty);
    });
  });

  test('Bildschirm → Koordinate: Ecken und Mitte in Web-Mercator', () {
    const bounds =
        MapViewBounds(west: 11.0, east: 12.0, south: 47.0, north: 48.0);
    const size = Size(400, 600);
    final nw = unprojectFromBounds(bounds, size, Offset.zero);
    final se = unprojectFromBounds(bounds, size, const Offset(400, 600));
    expect(nw.latitude, closeTo(48, 1e-9));
    expect(nw.longitude, closeTo(11, 1e-9));
    expect(se.latitude, closeTo(47, 1e-9));
    expect(se.longitude, closeTo(12, 1e-9));
    // Die Mitte des Bildes liegt in Mercator in der Mitte — also
    // nördlicher als die Mitte der Breitengrade.
    final mid = unprojectFromBounds(bounds, size, const Offset(200, 300));
    expect(mid.latitude, greaterThan(47.5));
    expect(mid.latitude, lessThan(47.51));
  });

  test('keysAt: Rahmen und Kachelmenge sprechen dieselbe Sprache', () {
    final b = tileBounds(kAreaShapeZoom, 200, 300);
    final inner = AreaBounds(
        south: b.south + 1e-6,
        west: b.west + 1e-6,
        north: b.north - 1e-6,
        east: b.east - 1e-6);
    expect(RectShape(inner).keysAt(kAreaShapeZoom), {_key(200, 300)});
    final set = TileSetShape(zoom: kAreaShapeZoom, keys: {_key(200, 300)});
    expect(set.keysAt(kAreaShapeZoom - 1),
        {TileSetShape.keyOf(100, 150, kAreaShapeZoom - 1)});
  });

  group('Entwurf', () {
    late ProviderContainer container;
    late MemoryAreaStore store;
    AreaDraftNotifier draft() => container.read(areaDraftProvider.notifier);

    setUp(() async {
      store = MemoryAreaStore();
      await _area(store, 'a', {_key(10, 10), _key(11, 10)});
      container = ProviderContainer(
          overrides: [areaStoreProvider.overrideWithValue(store)]);
      await container.read(storedAreasProvider.future);
      // Der Bestand wird beobachtet, solange der Entwurf rechnet.
      container.listen(storedTileKeysProvider, (_, _) {});
      draft().start();
    });
    tearDown(() => container.dispose());

    test('dazu nimmt nur, was nicht liegt; weg nur, was liegt', () {
      draft().addAll({_key(10, 10), _key(12, 10)});
      expect(container.read(areaDraftProvider)!.adds, {_key(12, 10)});
      draft().removeAll({_key(11, 10), _key(12, 10), _key(99, 99)});
      final d = container.read(areaDraftProvider)!;
      expect(d.adds, isEmpty, reason: 'wegwischen nimmt das Dazu zurück');
      expect(d.removes, {_key(11, 10)});
    });

    test('ein Werkzeug gilt für EINEN Strich; derselbe Knopf nimmt es zurück',
        () {
      draft().arm(AreaDrawTool.add);
      expect(container.read(areaDraftProvider)!.tool, AreaDrawTool.add);
      draft().arm(AreaDrawTool.add);
      expect(container.read(areaDraftProvider)!.tool, isNull);
      draft().arm(AreaDrawTool.add);
      draft().applyStroke({_key(20, 20)});
      final d = container.read(areaDraftProvider)!;
      expect(d.adds, {_key(20, 20)});
      expect(d.tool, isNull, reason: 'danach ist die Karte wieder frei');
      // Ohne Werkzeug tut ein Strich nichts.
      draft().applyStroke({_key(21, 21)});
      expect(container.read(areaDraftProvider)!.adds, {_key(20, 20)});
    });

    test('Rückgängig geht Schritt für Schritt zurück, leere Schritte zählen '
        'nicht', () {
      draft().addAll({_key(20, 20)});
      draft().addAll({_key(20, 20)}); // ändert nichts
      draft().addAll({_key(21, 20)});
      expect(container.read(areaDraftProvider)!.history, hasLength(2));
      draft().undo();
      expect(container.read(areaDraftProvider)!.adds, {_key(20, 20)});
      draft().undo();
      expect(container.read(areaDraftProvider)!.isEmpty, isTrue);
    });

    test('Beschneiden: eine Kachel weg schreibt den Bereich neu, alle weg '
        'löscht ihn', () async {
      final areas = container.read(storedAreasProvider.notifier);
      final one = await areas.planTrim({_key(11, 10)});
      expect(one.trims.single.shape!.keys, {_key(10, 10)});
      // Zoom 13 und 12 verlieren je eine Kachel — (10,10) und (11,10)
      // haben dieselben Eltern ab Zoom 12, die bleiben.
      expect(one.freedTiles, 1);
      await areas.applyTrim(one);
      final after = store.areas.single;
      expect(after.shape.keysAt(kAreaShapeZoom), {_key(10, 10)});
      final archive = await PmTilesArchive.fromBytes(store.archives['a']!);
      expect(archive.header.numberOfAddressedTiles, after.tiles);
      expect(await archive.lookup(const ZXY(kAreaShapeZoom, 11, 10).toTileId()),
          isNull);
      await archive.close();

      final all = await areas.planTrim({_key(10, 10)});
      expect(all.trims.single.shape, isNull);
      await areas.applyTrim(all);
      expect(store.areas, isEmpty);
      expect(store.archives, isEmpty);
    });
  });

  test('das Bild: hell, was liegt; dunkel, was nicht; Schraffur auf dem '
      'Entwurf', () {
    // Drei Kacheln nebeneinander: liegt, liegt und fällt weg, kommt dazu.
    final a = tileBounds(kAreaShapeZoom, 50, 60);
    final c = tileBounds(kAreaShapeZoom, 52, 60);
    final window = FillWindow(
        west: a.west,
        east: c.east,
        north: a.north,
        south: a.south,
        width: 60,
        height: 20);
    final png = areaEditFillPng(
      window: window,
      stored: {_key(50, 60), _key(51, 60)},
      adds: {_key(52, 60)},
      removes: {_key(51, 60)},
    );
    final image = img.decodePng(png)!;
    int alpha(int x, int y) => image.getPixel(x, y).a.toInt();
    // Liegt: durchsichtig, überall.
    for (var x = 0; x < 20; x++) {
      for (var y = 0; y < 20; y++) {
        expect(alpha(x, y), 0);
      }
    }
    // Fällt weg: hell mit dunkler Schraffur — Pixel sind entweder
    // durchsichtig oder dunkle Tinte, nie die Abdunkelung.
    final removeInk = <int>{};
    for (var x = 22; x < 38; x++) {
      for (var y = 2; y < 18; y++) {
        final p = image.getPixel(x, y);
        removeInk.add(p.a.toInt());
        if (p.a > 0) expect(p.r.toInt(), kAreaInkDark.r);
      }
    }
    expect(removeInk, {0, kAreaInkDark.a});
    // Kommt dazu: abgedunkelt mit heller Schraffur.
    final addInk = <int>{};
    for (var x = 42; x < 58; x++) {
      for (var y = 2; y < 18; y++) {
        addInk.add(alpha(x, y));
      }
    }
    expect(addInk, {kAreaMaskAlpha, kAreaInkLight.a});
    // Ohne Entwurf: dunkel, wo nichts liegt — und keine Schraffur.
    final plain = img.decodePng(areaEditFillPng(
        window: window, stored: {_key(50, 60)}, adds: {}, removes: {}))!;
    expect(plain.getPixel(50, 10).a.toInt(), kAreaMaskAlpha);
    expect(plain.getPixel(5, 10).a.toInt(), 0);
  });
}
