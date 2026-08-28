// Die Höhenlinien-Ebene von Hand: FAB → Blatt → an, was die Legende
// sagt, und die zwei Fälle, in denen bewusst nichts zu sehen ist —
// zu weit draußen und ohne Gitter.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/map/elevation_contour_providers.dart';
import 'package:pilzbuddy/features/map/elevation_contours.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/elevation_providers.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart'
    show mapIdleBoundsProvider;
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart';

import '../fakes/fake_backend.dart';
import '../fakes/map_ui.dart';
import '../fakes/test_app.dart';

void main() {
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  FakeBackend loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  /// Ein Gitter um die Kartenmitte (51,1634 / 10,4477) mit einem
  /// gleichmäßigen Hang nach Osten: eine 20-m-Stufe je 0,02°-Wabe
  /// (~1,4 km), also gut ein Prozent Gefälle — ein Mittelgebirgshang.
  ///
  /// **Der Hang ist der Punkt des Tests:** Seit 1.99.0 fällt die
  /// Äquidistanz aus dem Gelände, nicht aus einer Zoomtabelle. Ein
  /// flaches Gitter bekäme bei JEDEM Maßstab die feinste Stufe und
  /// bewiese damit nichts.
  ElevationGrid testGrid() {
    const cols = 150, rows = 100;
    return ElevationGrid(
      values: Uint8List.fromList([
        for (var y = 0; y < rows; y++)
          for (var x = 0; x < cols; x++) x,
      ]),
      width: cols,
      height: rows,
      west: 9.0,
      east: 9.0 + cols * 0.02,
      north: 52.0,
      south: 52.0 - rows * 0.02,
      hexLonStep: 0.02,
      hexLatStep: 0.02,
    );
  }

  List<Override> withGrid(ElevationGrid? grid) => [
        elevationLoaderProvider.overrideWithValue(() async => grid),
      ];

  /// Setzt Stillstand von Hand — Bodenauflösung und Sichtfenster, wie
  /// sie die Karte über der Mitte melden würde.
  ///
  /// [metersPerPixel] ist der Maßstab: rund 25 m je Pixel entspricht
  /// dem Landschaftsblick, 300 der Deutschlandübersicht (dort zeichnet
  /// die Ebene nichts mehr, siehe `contourMaxMetersPerPixel`).
  ///
  /// **Erst nach einem `settle` aufrufen:** Die echte Karte meldet beim
  /// Aufbau selbst Stillstand und überschriebe diese Werte sonst wieder
  /// — der Test wäre dann von der Reihenfolge der Frames abhängig statt
  /// von dem, was er prüft.
  void idleAt(ProviderContainer container, double metersPerPixel) {
    final degPerPixel = metersPerPixel / (111320 * 0.629);
    final halfLon = degPerPixel * 1080 / 2;
    final halfLat = degPerPixel * 1920 / 2 * 0.629;
    container.read(mapIdleGroundResolutionProvider.notifier).state =
        metersPerPixel;
    container.read(mapIdleBoundsProvider.notifier).state = MapViewBounds(
      west: 10.4477 - halfLon,
      east: 10.4477 + halfLon,
      north: 51.1634 + halfLat,
      south: 51.1634 - halfLat,
    );
  }

  testWidgets('die Zeile ist immer da — auch ohne Gitter, dann sagt es das '
      'Blatt', (tester) async {
    // Ein `ref.watch` auf das Gitter im Karten-Screen packte 3,4 MB bei
    // jedem App-Start aus. Die Regel „kein Fehler ohne Fehlermeldung"
    // hält trotzdem — sie steht nur im Blatt statt im Verschwinden des
    // Knopfs. Seit 1.99.4 macht der Wald es genauso; vorher war dieser
    // Knopf hier die Ausnahme.
    await pumpApp(tester, loggedInBackend(), extraOverrides: withGrid(null));
    await openMapLayers(tester);
    expect(find.text('Höhenlinien'), findsOneWidget);

    await tester.tap(find.text('Höhenlinien'));
    await settle(tester);
    expect(find.textContaining('lässt sich nicht laden'), findsOneWidget);

    // Und der Schalter ist tot, statt eine Ebene zu versprechen.
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.onChanged, isNull);
  });

  testWidgets('das Blatt nennt Auflösung und Quelle', (tester) async {
    await pumpApp(tester, loggedInBackend(),
        extraOverrides: withGrid(testGrid()));
    await openLayerSheet(tester, 'Höhenlinien');

    expect(find.text('Höhenlinien einblenden'), findsOneWidget);
    expect(find.textContaining('≈ 270 m'), findsOneWidget,
        reason: 'die Auflösung gehört ins Blatt, wie bei den Waldtypen');
    expect(find.textContaining('Im Flachland'), findsOneWidget,
        reason: 'sonst sieht eine leere Karte nach einem Fehler aus');
    expect(find.textContaining('Copernicus DEM'), findsOneWidget);
    expect(find.textContaining('ohne Verbindung'), findsOneWidget,
        reason: 'die Ebene baut kein Netz auf, und das ist ihr Argument');
  });

  testWidgets('standardmäßig aus — niemand bekommt Linien ungefragt',
      (tester) async {
    await pumpApp(tester, loggedInBackend(),
        extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);
    expect(container.read(contourLayerEnabledProvider), isFalse);
    expect(find.byType(PolylineLayer), findsNothing);
  });

  testWidgets('an: Linien liegen auf der Karte, unter den Markern',
      (tester) async {
    await pumpApp(tester, loggedInBackend(),
        useRealMap: true, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);

    await openLayerSheet(tester, 'Höhenlinien');
    await tester.tap(find.text('Höhenlinien einblenden'));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20)); // Blatt schließen
    await settle(tester);

    idleAt(container, 25);
    // Gerechnet wird im Isolate — wie bei Wald und Regen unter
    // runAsync auf den Provider warten, nicht auf eine geratene Frist.
    final contours = await tester
        .runAsync(() => container.read(elevationContoursProvider.future));
    await settle(tester);

    expect(contours, isNotNull);
    expect(contours!.equidistanceM, 20,
        reason: 'nah dran trägt dieser Hang die feinste Stufe');
    expect(contours.lines, isNotEmpty);

    final layers =
        tester.widgetList<PolylineLayer>(find.byType(PolylineLayer)).toList();
    expect(layers, hasLength(1));
    final drawn = layers.single.polylines;
    expect(drawn, hasLength(contours.lines.length));
    expect(drawn.first.color.toARGB32() & 0x00FFFFFF,
        AppColors.contourLine.toARGB32() & 0x00FFFFFF);

    // Unter den Markern: In der Kinderliste der Karte kommt die
    // Linienebene VOR jedem MarkerLayer. Eine Linie über einem Spot
    // machte ihn unauffindbar.
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final polylineAt = map.children.indexWhere((c) => c is PolylineLayer);
    final markerAt = map.children.indexWhere((c) => c is MarkerLayer);
    expect(polylineAt, greaterThanOrEqualTo(0));
    expect(markerAt, greaterThan(polylineAt));

    // Und die Zahlen: MapLibre setzt sie selbst, der Canvas-Renderer
    // braucht Marker. Ohne sie sagt die Linie nur „hier ist es steiler
    // als dort" (Betreiber, 2026-08-21).
    final labels = container.read(contourLabelsProvider);
    expect(labels, isNotEmpty);
    expect(labels.every((l) => l.level % contourIndexEveryM == 0), isTrue);
    expect(find.text('${labels.first.level}'), findsWidgets);
  });

  testWidgets('zu weit draußen: keine Linien, und die Legende sagt es',
      (tester) async {
    await pumpApp(tester, loggedInBackend(),
        useRealMap: true, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);
    container.read(contourLayerEnabledProvider.notifier).state = true;
    await settle(tester);

    // 400 m je Pixel: Ein Pixel deckt mehr Boden ab als eine Wabe breit
    // ist — eine Linie daraus wäre eine Karikatur.
    idleAt(container, 400);
    final contours = await tester
        .runAsync(() => container.read(elevationContoursProvider.future));
    await settle(tester);

    expect(contours, isNull);
    expect(find.byType(PolylineLayer), findsNothing);
    expect(find.textContaining('erst näher dran'), findsOneWidget,
        reason: 'eine Ebene, die still nichts zeigt, sieht kaputt aus');
  });

  testWidgets('die Legende nennt die Äquidistanz, die WIRKLICH liegt',
      (tester) async {
    await pumpApp(tester, loggedInBackend(),
        useRealMap: true, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);
    container.read(contourLayerEnabledProvider.notifier).state = true;
    await settle(tester);
    // Gröberer Maßstab, DERSELBE Hang: Jetzt liegen 20-m-Linien zu
    // dicht, und die Regel greift zur nächsten Stufe. Genau das muss in
    // der Legende stehen — nicht, was die Zoomstufe „wollte".
    idleAt(container, 150);
    await tester
        .runAsync(() => container.read(elevationContoursProvider.future));
    await settle(tester);

    expect(find.textContaining('Höhenlinien alle 50 m'), findsOneWidget);
  });

  testWidgets('der Schalter ist sitzungslokal — nichts wird gemerkt',
      (tester) async {
    // Wie bei Wald und Regen: Eine über Nacht vergessene Ebene verwirrt
    // mehr, als der eine Tipp zum Wiedereinschalten kostet. Der Beweis
    // ist ein FRISCHER Container: Läse der Provider die Einstellungen,
    // stünde dort jetzt „an".
    await pumpApp(tester, loggedInBackend(),
        extraOverrides: withGrid(testGrid()));
    await openLayerSheet(tester, 'Höhenlinien');
    await tester.tap(find.text('Höhenlinien einblenden'));
    await settle(tester);
    expect(containerOf(tester).read(contourLayerEnabledProvider), isTrue);

    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    expect(fresh.read(contourLayerEnabledProvider), isFalse);
  });
}
