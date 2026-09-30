// Die Planung eines gespeicherten Kartenbereichs (#630): welche Kacheln
// ein Rahmen berührt, die Obergrenze, die Kachelmenge um die Spots, die
// Größenangabe.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:pilzbuddy/features/offline_areas/area_plan.dart';

void main() {
  test('Kachel einer Koordinate: bekannte Werte, Ränder geklemmt', () {
    expect(tileAt(0, 0, 1), (x: 1, y: 1));
    expect(tileAt(85, -180, 3), (x: 0, y: 0));
    expect(tileAt(-85, 179.999, 3), (x: 7, y: 7));
    expect(tileAt(47.9, 11.6, 13), (x: 4359, y: 2851));
  });

  test('ein Rahmen berührt je Zoom ein Rechteck; die Ids sind Hilbert-Ids',
      () {
    const bounds =
        AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7);
    final tiles = tilesCovering(bounds, minZoom: 12, maxZoom: 13);
    expect(tiles.where((t) => t.z == 12).length, greaterThanOrEqualTo(2));
    expect(tiles.length, countTilesCovering(bounds, minZoom: 12, maxZoom: 13));
    for (final t in tiles) {
      expect(ZXY.fromTileId(tileIdOf(t)), ZXY(t.z, t.x, t.y));
    }
    // Bei Zoom 8 beginnt der Bereich: darunter liegt die Übersicht.
    expect(tilesCovering(bounds, maxZoom: 8).every((t) => t.z == kAreaMinZoom),
        isTrue);
  });

  test('ganz DACH überschreitet die Obergrenze, ein Wochenendgebiet nicht', () {
    const dach = AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5);
    expect(countTilesCovering(dach, maxZoom: 13), greaterThan(kAreaMaxTiles));
    const weekend =
        AreaBounds(south: 47.4, west: 11.0, north: 47.9, east: 11.8);
    expect(countTilesCovering(weekend, maxZoom: 13), lessThan(kAreaMaxTiles));
  });

  group('Kachelmenge um die Spots', () {
    // Zwei Spots 60 km auseinander: ein Rahmen um beide wäre 60 km breit,
    // die Kacheln um die Spots sind zwei kleine Flecken.
    const near = LatLng(47.90, 11.60);
    const far = LatLng(47.90, 12.40);

    test('nur die Kacheln um die Spots, nicht das Land dazwischen', () {
      final shape = AreaShape.aroundPoints(const [near, far])!;
      final rect = RectShape(shape.hull);
      expect(shape.countTiles(minZoom: 13, maxZoom: 13),
          lessThan(rect.countTiles(minZoom: 13, maxZoom: 13) ~/ 4));
      final z13 = shape.tiles(minZoom: 13, maxZoom: 13);
      for (final p in const [near, far]) {
        final t = tileAt(p.latitude, p.longitude, 13);
        expect(z13, contains((z: 13, x: t.x, y: t.y)));
      }
      for (final t in z13) {
        final b = tileBounds(13, t.x, t.y);
        expect(b.west < 11.7 || b.east > 12.3, isTrue,
            reason: 'Kachel mitten im Dazwischen: $t');
      }
    });

    test('der Umkreis reicht in jede Richtung', () {
      final shape = AreaShape.aroundPoints(const [near])!;
      final hull = shape.hull;
      // 2 km sind ~0,018° Breite.
      expect(near.latitude - hull.south, greaterThan(kAreaSpotRadiusKm / 111));
      expect(hull.north - near.latitude, greaterThan(kAreaSpotRadiusKm / 111));
      expect(hull.contains(near), isTrue);
    });

    test('Eltern darunter, Kinder darüber, gezählt wie geliefert', () {
      final shape = AreaShape.aroundPoints(const [near])!;
      final z12 = shape.tiles(minZoom: 12, maxZoom: 12).toSet();
      for (final t in shape.tiles(minZoom: 13, maxZoom: 13)) {
        expect(z12, contains((z: 12, x: t.x >> 1, y: t.y >> 1)));
      }
      expect(shape.tiles(minZoom: 14, maxZoom: 14).length,
          shape.keys.length * 4);
      expect(shape.countTiles(minZoom: 8, maxZoom: 14),
          shape.tiles(minZoom: 8, maxZoom: 14).length);
      final all = shape.tiles(maxZoom: 14);
      expect(all.toSet().length, all.length);
    });

    test('JSON-Rundlauf, und ohne Spots keine Form', () {
      final shape = AreaShape.aroundPoints(const [near])!;
      final back = AreaShape.fromJson(shape.toJson());
      expect(back, isA<TileSetShape>());
      expect((back as TileSetShape).keys, shape.keys);
      expect(back.zoom, kAreaShapeZoom);
      expect(
          AreaShape.fromJson(const RectShape(
                  AreaBounds(south: 1, west: 2, north: 3, east: 4))
              .toJson()),
          isA<RectShape>());
      expect(AreaShape.aroundPoints(const []), isNull);
    });
  });

  test('tileBounds ist die Umkehrung von tileAt', () {
    final t = tileAt(47.9, 11.6, 13);
    final b = tileBounds(13, t.x, t.y);
    expect(b.contains(const LatLng(47.9, 11.6)), isTrue);
    expect(tileAt(b.north - 1e-9, b.west + 1e-9, 13), (x: t.x, y: t.y));
  });

  test('Größen lesbar, deutsch', () {
    expect(formatBytes(512000), '512 kB');
    expect(formatBytes(12400000), '12,4 MB');
    expect(formatBytes(2800000000), '2,80 GB');
  });
}
