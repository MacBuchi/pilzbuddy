// Die Mini-Karte im Fund-Blatt (#373).
//
// Sie ist die ZWEITE Stelle im Projekt, die `flutter_map` direkt
// instanziiert. Zwei Invarianten standen bis dahin nur in
// `flutter_map_view.dart` und hängen an JEDER `MapOptions` — die prüft
// dieser Test hier noch einmal, denn eine Kopie erbt keine Wächter.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/finite_camera_constraint.dart';
import 'package:pilzbuddy/features/map/map_view/flutter_map_view.dart'
    show tileProviderFactoryProvider;
import 'package:pilzbuddy/features/map/widgets/mini_map.dart';

import 'fakes/test_app.dart';

void main() {
  const spot = LatLng(51.1634, 10.4477);

  Future<MapOptions> pumpMiniMap(
    WidgetTester tester, {
    required MiniMapMode mode,
    LatLng center = spot,
    double? accuracyM,
    ValueChanged<LatLng>? onCenterChanged,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tileProviderFactoryProvider.overrideWithValue(FakeTileProvider.new),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MiniMap(
            mode: mode,
            center: center,
            reference: spot,
            accuracyM: accuracyM,
            onCenterChanged: onCenterChanged,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    return tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
  }

  testWidgets('Der Kamera-Wächter hängt an JEDER MapOptions, nicht nur an '
      'der großen Karte', (tester) async {
    // Wortgleich zur Zusicherung in flows/map_view_test.dart: Ohne ihn
    // reicht EIN nicht-endlicher Kamerazustand aus einem Gesten-Grenzfall
    // für graue Flächen und den Allokationssturm aus #151 — und eine
    // Kopie erbt den Wächter nicht.
    final options = await pumpMiniMap(tester, mode: MiniMapMode.pick);

    expect(options.cameraConstraint, isA<FiniteCameraConstraint>());
  });

  testWidgets('Die Kacheln kommen aus der Naht, nicht aus dem Netz',
      (tester) async {
    await pumpMiniMap(tester, mode: MiniMapMode.pick);

    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.tileProvider, isA<FakeTileProvider>(),
        reason: 'sonst holt jeder Testlauf echte OSM-Kacheln');
  });

  testWidgets('Im Anschau-Modus nimmt die Karte KEINE Gesten an',
      (tester) async {
    // Das ist zugleich der Gesten-Beweis: Ohne Drag-Erkenner geht der
    // Wischer an den SingleChildScrollView des Blattes durch, und das
    // Formular lässt sich weiter scrollen.
    final options = await pumpMiniMap(tester,
        mode: MiniMapMode.fix, accuracyM: 8);

    expect(options.interactionOptions.flags, InteractiveFlag.none);
  });

  testWidgets('Im Wähl-Modus behält die Karte den Wischer — ohne Drehen '
      'und ohne Schwung', (tester) async {
    final options = await pumpMiniMap(tester, mode: MiniMapMode.pick);
    final flags = options.interactionOptions.flags;

    expect(InteractiveFlag.hasDrag(flags), isTrue,
        reason: 'die absorbierenden Erkenner von flutter_map hängen daran');
    expect(InteractiveFlag.hasRotate(flags), isFalse);
    expect(InteractiveFlag.hasFlingAnimation(flags), isFalse,
        reason: 'in 180 px schießt der Schwung über das Ziel hinaus');
  });

  testWidgets('Der Genauigkeitskreis misst in METERN', (tester) async {
    // Der wichtigste Test des Bauteils: Fällt `useRadiusInMeter` weg,
    // werden aus ±8 Metern still 8 Pixel — und nichts an der Oberfläche
    // schreit.
    await pumpMiniMap(tester, mode: MiniMapMode.fix, accuracyM: 8);

    final circles =
        tester.widget<CircleLayer>(find.byType(CircleLayer)).circles;
    expect(circles.every((c) => c.useRadiusInMeter), isTrue);
    expect(circles.map((c) => c.radius), contains(8.0));
  });

  testWidgets('Im Wähl-Modus gibt es keinen Streukreis', (tester) async {
    // Eine gewählte Stelle hat keinen Messfehler; ein Kreis darum wäre
    // eine erfundene Zahl in Bildform.
    await pumpMiniMap(tester, mode: MiniMapMode.pick, accuracyM: 8);

    final circles =
        tester.widget<CircleLayer>(find.byType(CircleLayer)).circles;
    expect(circles, hasLength(1),
        reason: 'nur der 20-m-Ring um den Spot');
  });

  testWidgets('Verschieben meldet die neue Mitte — im Anschau-Modus nicht',
      (tester) async {
    final picked = <LatLng>[];
    await pumpMiniMap(tester,
        mode: MiniMapMode.pick, onCenterChanged: picked.add);
    await tester.drag(find.byType(FlutterMap), const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 100));
    expect(picked, isNotEmpty);
    expect(picked.last.latitude, isNot(spot.latitude));

    final ignored = <LatLng>[];
    await pumpMiniMap(tester,
        mode: MiniMapMode.fix, accuracyM: 8, onCenterChanged: ignored.add);
    await tester.drag(find.byType(FlutterMap), const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ignored, isEmpty);
  });

  group('miniMapZoomFor', () {
    test('ein kleiner Kreis wird näher gezeigt als ein großer', () {
      final tight =
          miniMapZoomFor(radiusMeters: 5, boxPixels: 180, latitude: 51.16);
      final wide =
          miniMapZoomFor(radiusMeters: 25, boxPixels: 180, latitude: 51.16);
      expect(tight, greaterThan(wide));
    });

    test('bleibt in den Grenzen, in denen es OSM-Kacheln gibt', () {
      expect(
          miniMapZoomFor(
              radiusMeters: 0.01, boxPixels: 180, latitude: 51.16),
          lessThanOrEqualTo(18.5));
      expect(
          miniMapZoomFor(
              radiusMeters: 100000, boxPixels: 180, latitude: 51.16),
          greaterThanOrEqualTo(14.0));
    });

    test('der Kreis passt in den Kasten', () {
      const box = 180.0;
      const radius = 8.0;
      const lat = 51.16;
      final zoom =
          miniMapZoomFor(radiusMeters: radius, boxPixels: box, latitude: lat);
      // Rückrechnung: Meter je Pixel bei diesem Zoom.
      final metersPerPixel = 156543.03392 *
          math.cos(lat * math.pi / 180) /
          math.pow(2, zoom);
      expect(2 * radius / metersPerPixel, lessThan(box),
          reason: 'sonst ragt der Streukreis über den Rand hinaus');
    });
  });
}
