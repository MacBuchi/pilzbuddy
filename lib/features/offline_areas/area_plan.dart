// Die Planung eines gespeicherten Kartenbereichs (#630, Stufe 2), pur:
// welche Kacheln eine FORM von Zoom [kAreaMinZoom] bis zum Zoom des
// Archivs berührt, und welche Kachel-Ids das im Archiv sind. Die Größe
// kommt später aus dem Verzeichnis des Archivs (jede Kachel nennt dort
// ihre Bytes) — hier wird nur GEZÄHLT, nicht geschätzt.
//
// Übernommen aus TrailBuddy (`lib/features/offline_areas/area_plan.dart`),
// ohne dessen Orte-Zellen. Zwei Formen ([AreaShape]): ein Rahmen
// ([RectShape], der Kartenausschnitt) und eine Kachelmenge
// ([TileSetShape], die Form von „Um meine Spots"). Ein Rechteck um
// verstreute Spots bestünde vor allem aus Land dazwischen — bei TrailBuddy
// lief das Rechteck um alle Trails auf 40 779 Kacheln, über der Obergrenze.
// Ein Archiv braucht kein Rechteck; sein Rahmen im Header ist die Hülle.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart' show ZXY;

/// Unter Zoom 8 liegt die mitgelieferte Übersicht (Zoom 0–7), die hat
/// jedes Gerät. Ein Bereich beginnt darüber.
const kAreaMinZoom = 8;

/// Mehr Kacheln als das speichert die App nicht in EINEM Bereich: Bei
/// Zoom 13 sind das rund 1 000 km × 400 km, weit mehr als ein
/// Wochenende, und die Kachelliste selbst (Nachschlagen jeder Kachel im
/// Verzeichnis) würde spürbar. Wer mehr will, speichert zwei Bereiche.
const kAreaMaxTiles = 40000;

/// Der Umkreis um jeden Spot bei „Um meine Spots": Eine Kachel gehört
/// dazu, wenn ein Spot ihr näher als so viele Kilometer kommt. Größer als
/// TrailBuddys 1 km entlang der Trails, weil ein Spot ein Punkt ist und
/// man auf dem Weg dorthin auch Karte braucht.
const kAreaSpotRadiusKm = 2.0;

/// Der Zoom, in dem eine [TileSetShape] ihre Kacheln merkt — fest, damit
/// die Form nicht vom Zoom des Hosts abhängt: Ein höherer Zoom des
/// Archivs sind die Kinder dieser Kacheln, ein niedrigerer die Eltern.
const kAreaShapeZoom = 13;

/// Ein Rahmen in Grad, Süden/Westen/Norden/Osten.
class AreaBounds {
  const AreaBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(LatLng p) =>
      p.latitude >= south &&
      p.latitude <= north &&
      p.longitude >= west &&
      p.longitude <= east;

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  Map<String, dynamic> toJson() =>
      {'s': south, 'w': west, 'n': north, 'e': east};

  factory AreaBounds.fromJson(Map<String, dynamic> j) => AreaBounds(
        south: (j['s'] as num).toDouble(),
        west: (j['w'] as num).toDouble(),
        north: (j['n'] as num).toDouble(),
        east: (j['e'] as num).toDouble(),
      );
}

/// Eine Kachel im Web-Mercator-Raster.
typedef TileXYZ = ({int z, int x, int y});

/// Die Breite, an der Web-Mercator endet.
const _maxMercatorLat = 85.05112878;

/// Spalte und Zeile der Kachel, in der [lon]/[lat] bei Zoom [z] liegt.
({int x, int y}) tileAt(double lat, double lon, int z) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final latRad = lat.clamp(-_maxMercatorLat, _maxMercatorLat) * math.pi / 180;
  final y =
      ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
              2 *
              n)
          .floor()
          .clamp(0, n - 1);
  return (x: x, y: y);
}

/// Alle Kacheln, die [bounds] von [minZoom] bis [maxZoom] berühren.
List<TileXYZ> tilesCovering(AreaBounds bounds,
    {int minZoom = kAreaMinZoom, required int maxZoom}) {
  final out = <TileXYZ>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final nw = tileAt(bounds.north, bounds.west, z);
    final se = tileAt(bounds.south, bounds.east, z);
    for (var x = nw.x; x <= se.x; x++) {
      for (var y = nw.y; y <= se.y; y++) {
        out.add((z: z, x: x, y: y));
      }
    }
  }
  return out;
}

/// Wie viele Kacheln [tilesCovering] liefern würde — ohne die Liste zu
/// bauen (für die Obergrenze, bevor jemand 40 000 Einträge anlegt).
int countTilesCovering(AreaBounds bounds,
    {int minZoom = kAreaMinZoom, required int maxZoom}) {
  var count = 0;
  for (var z = minZoom; z <= maxZoom; z++) {
    final nw = tileAt(bounds.north, bounds.west, z);
    final se = tileAt(bounds.south, bounds.east, z);
    count += (se.x - nw.x + 1) * (se.y - nw.y + 1);
  }
  return count;
}

int tileIdOf(TileXYZ t) => ZXY(t.z, t.x, t.y).toTileId();

/// Der Rahmen einer Kachel (Umkehrung von [tileAt]).
AreaBounds tileBounds(int z, int x, int y) {
  final n = 1 << z;
  double lat(int row) =>
      math.atan(_sinh(math.pi * (1 - 2 * row / n))) * 180 / math.pi;
  return AreaBounds(
    south: lat(y + 1),
    west: x / n * 360 - 180,
    north: lat(y),
    east: (x + 1) / n * 360 - 180,
  );
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

/// Die Form eines Bereichs: Rahmen oder Kachelmenge.
sealed class AreaShape {
  const AreaShape();

  /// Die Hülle (Rahmen im Archiv-Header, „auf der Karte zeigen").
  AreaBounds get hull;

  List<TileXYZ> tiles({int minZoom = kAreaMinZoom, required int maxZoom});

  /// Wie viele Kacheln [tiles] liefern würde.
  int countTiles({int minZoom = kAreaMinZoom, required int maxZoom});

  Map<String, dynamic> toJson();

  static AreaShape fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'tiles' => TileSetShape(
            zoom: j['zoom'] as int,
            keys: {for (final k in j['keys'] as List) k as int},
          ),
        _ => RectShape(
            AreaBounds.fromJson(j['bounds'] as Map<String, dynamic>)),
      };

  /// Die Kacheln um die Punkte, [radiusKm] in jede Richtung — null ohne
  /// Punkte. Ein Quadrat statt eines Kreises: an den Ecken eine Kachel
  /// zu viel ist die harmlose Richtung.
  static TileSetShape? aroundPoints(Iterable<LatLng> points,
      {double radiusKm = kAreaSpotRadiusKm, int zoom = kAreaShapeZoom}) {
    final keys = <int>{};
    final dLat = radiusKm / 111.0;
    for (final p in points) {
      final dLon = radiusKm /
          (111.0 * math.max(0.2, math.cos(p.latitude * math.pi / 180)));
      final nw = tileAt(p.latitude + dLat, p.longitude - dLon, zoom);
      final se = tileAt(p.latitude - dLat, p.longitude + dLon, zoom);
      for (var x = nw.x; x <= se.x; x++) {
        for (var y = nw.y; y <= se.y; y++) {
          keys.add(TileSetShape.keyOf(x, y, zoom));
        }
      }
    }
    return keys.isEmpty ? null : TileSetShape(zoom: zoom, keys: keys);
  }
}

/// Ein Rahmen — der aktuelle Kartenausschnitt.
class RectShape extends AreaShape {
  const RectShape(this.bounds);

  final AreaBounds bounds;

  @override
  AreaBounds get hull => bounds;

  @override
  List<TileXYZ> tiles({int minZoom = kAreaMinZoom, required int maxZoom}) =>
      tilesCovering(bounds, minZoom: minZoom, maxZoom: maxZoom);

  @override
  int countTiles({int minZoom = kAreaMinZoom, required int maxZoom}) =>
      countTilesCovering(bounds, minZoom: minZoom, maxZoom: maxZoom);

  @override
  Map<String, dynamic> toJson() => {'type': 'rect', 'bounds': bounds.toJson()};
}

/// Eine Menge Kacheln bei [zoom] (Schlüssel aus [keyOf]). Andere Zooms
/// folgen daraus: Eltern darunter, Kinder darüber.
class TileSetShape extends AreaShape {
  const TileSetShape({required this.zoom, required this.keys});

  final int zoom;
  final Set<int> keys;

  static int keyOf(int x, int y, int zoom) => (x << zoom) | y;

  ({int x, int y}) _xy(int key) =>
      (x: key >> zoom, y: key & ((1 << zoom) - 1));

  /// Die Kacheln bei Zoom [z] — als Menge, weil Eltern mehrfach kommen.
  Set<int> _keysAt(int z) {
    if (z == zoom) return keys;
    if (z < zoom) {
      final d = zoom - z;
      return {
        for (final k in keys) keyOf(_xy(k).x >> d, _xy(k).y >> d, z),
      };
    }
    final d = z - zoom;
    return {
      for (final k in keys)
        for (var dx = 0; dx < (1 << d); dx++)
          for (var dy = 0; dy < (1 << d); dy++)
            keyOf((_xy(k).x << d) + dx, (_xy(k).y << d) + dy, z),
    };
  }

  @override
  List<TileXYZ> tiles({int minZoom = kAreaMinZoom, required int maxZoom}) => [
        for (var z = minZoom; z <= maxZoom; z++)
          for (final k in _keysAt(z)) (z: z, x: k >> z, y: k & ((1 << z) - 1)),
      ];

  @override
  int countTiles({int minZoom = kAreaMinZoom, required int maxZoom}) {
    var count = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      count += z > zoom ? keys.length << (2 * (z - zoom)) : _keysAt(z).length;
    }
    return count;
  }

  @override
  AreaBounds get hull {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final k in keys) {
      final b = tileBounds(zoom, _xy(k).x, _xy(k).y);
      s = math.min(s, b.south);
      n = math.max(n, b.north);
      w = math.min(w, b.west);
      e = math.max(e, b.east);
    }
    return AreaBounds(south: s, west: w, north: n, east: e);
  }

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'tiles', 'zoom': zoom, 'keys': keys.toList()..sort()};
}

/// Lesbare Größe, wie sie Dialog und Liste zeigen.
String formatBytes(int bytes) {
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} kB';
  if (bytes < 1000 * 1000 * 1000) {
    return '${(bytes / 1e6).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
  return '${(bytes / 1e9).toStringAsFixed(2).replaceAll('.', ',')} GB';
}
