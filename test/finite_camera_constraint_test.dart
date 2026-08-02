// Der Wächter gegen nicht-endliche Kamerazustände (#151/#141).
//
// Ein einziger NaN-/Infinity-Kamerazustand aus einem Gesten-Grenzfall lässt
// den MarkerLayer endlos Weltkopien erzeugen (ANR, #151) und die
// Kachelberechnung werfen (graue Flächen, #141). `latlong2` prüft
// Koordinaten nicht (keine Asserts im Konstruktor) — kaputte Werte sind
// also auch hier im Test konstruierbar, genau wie im Feld.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/finite_camera_constraint.dart';

void main() {
  MapCamera camera({
    double zoom = 12,
    LatLng? center,
    double rotation = 0,
  }) =>
      MapCamera(
        crs: const Epsg3857(),
        center: center ?? const LatLng(48.1, 11.5),
        zoom: zoom,
        rotation: rotation,
        nonRotatedSize: const Size(400, 800),
      );

  group('FiniteCameraConstraint.constrain', () {
    const constraint = FiniteCameraConstraint();

    test('lässt eine endliche Kamera unverändert durch', () {
      final c = camera();
      expect(constraint.constrain(c), same(c));
    });

    test('verwirft NaN und Infinity in Center und Rotation', () {
      // Zoom fehlt hier mit Absicht: flutter_maps MapCamera-Konstruktor
      // asserted `zoom.isFinite` — im Debug (also auch hier im Test) ist
      // eine NaN-Zoom-Kamera gar nicht konstruierbar. Im Release-Build
      // sind Asserts gestrichen, dort ist die Zoom-Prüfung des Wächters
      // das einzige Netz. Center und Rotation asserted flutter_map NICHT,
      // die sind der beweisbare Weg — und `latlong2` prüft Koordinaten
      // ebenfalls nicht.
      expect(
          constraint
              .constrain(camera(center: const LatLng(double.nan, 11.5))),
          isNull);
      expect(
          constraint
              .constrain(camera(center: const LatLng(48.1, double.infinity))),
          isNull);
      expect(constraint.constrain(camera(rotation: double.nan)), isNull);
    });
  });

  testWidgets(
      'Die Engstelle greift: move() auf kaputte Werte lässt die Kamera stehen',
      (tester) async {
    // Nicht nur die eigene Klasse testen, sondern den Vertrag mit
    // flutter_map: JEDE Bewegung läuft durch constrain(), und `null`
    // macht sie zum No-op (`moveRaw` in map_controller_impl.dart). Würde
    // flutter_map diesen Vertrag ändern, wäre der Wächter wirkungslos —
    // dann soll dieser Test rot werden, nicht erst das Feld.
    final controller = MapController();
    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        mapController: controller,
        options: const MapOptions(
          initialCenter: LatLng(48.1, 11.5),
          initialZoom: 12,
          cameraConstraint: FiniteCameraConstraint(),
        ),
        // Keine Layer nötig — getestet wird nur die Kamera-Engstelle.
        children: const [],
      ),
    ));

    // Nur der Center-Weg — NaN-Zoom scheitert im Debug schon an
    // flutter_maps eigenem Assert (siehe oben).
    expect(controller.move(const LatLng(double.nan, double.nan), 12), isFalse);
    expect(controller.camera.zoom, 12);
    expect(controller.camera.center, const LatLng(48.1, 11.5));

    // Gültige Bewegungen gehen weiterhin durch.
    expect(controller.move(const LatLng(50.0, 9.0), 10), isTrue);
    expect(controller.camera.zoom, 10);
  });
}
