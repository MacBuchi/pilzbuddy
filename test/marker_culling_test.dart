// Das Viewport-Culling ist der Kern von Migrationsstufe 4: Der
// WidgetLayer des maplibre-Pakets positioniert JEDEN Marker in jedem
// Frame auf dem UI-Isolate (kein eigenes Culling, TODO im Paket) — und
// genau in dieser Schicht saß der ANR aus #151. Gefiltert wird deshalb
// bei Kamera-Idle mit einer puren, hier vollständig geprüften Funktion.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/map_view/map_view.dart';
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart';

MapViewMarker _at(double lat, double lon) => MapViewMarker(
      point: LatLng(lat, lon),
      width: 44,
      height: 44,
      child: const SizedBox(),
    );

// München-Ausschnitt: 1° breit, 0,5° hoch.
const _bounds = MapViewBounds(west: 11.0, east: 12.0, south: 48.0, north: 48.5);

void main() {
  test('innerhalb bleibt, weit außerhalb fliegt raus', () {
    final inside = _at(48.2, 11.5);
    final farNorth = _at(52.5, 11.5);
    final farWest = _at(48.2, 5.0);
    final result =
        visibleMarkers([inside, farNorth, farWest], _bounds);
    expect(result, [inside]);
  });

  test('der Rand (25 % je Seite) zählt noch als sichtbar', () {
    // 25 % von 1° Breite = 0,25°; 25 % von 0,5° Höhe = 0,125°.
    final justOutsideEast = _at(48.2, 12.2); // 0,2° drüber → im Rand
    final beyondMargin = _at(48.2, 12.3); // 0,3° drüber → draußen
    final justAboveNorth = _at(48.6, 11.5); // 0,1° drüber → im Rand
    final result = visibleMarkers(
        [justOutsideEast, beyondMargin, justAboveNorth], _bounds);
    expect(result, [justOutsideEast, justAboveNorth],
        reason: 'Ohne Rand ploppen Marker beim Wischen sichtbar am '
            'Bildschirmrand auf — der Puffer lädt sie eine Idle-Phase '
            'früher.');
  });

  test('Reihenfolge bleibt erhalten (Zeichenreihenfolge = Stapelung)', () {
    final a = _at(48.1, 11.2);
    final b = _at(48.2, 11.4);
    final c = _at(48.3, 11.6);
    expect(visibleMarkers([c, a, b], _bounds), [c, a, b]);
  });

  test('leere Liste und leeres Sichtfenster sind kein Sonderfall', () {
    expect(visibleMarkers(const [], _bounds), isEmpty);
    const degenerate =
        MapViewBounds(west: 11.5, east: 11.5, south: 48.2, north: 48.2);
    final onPoint = _at(48.2, 11.5);
    expect(visibleMarkers([onPoint], degenerate), [onPoint]);
  });
}
