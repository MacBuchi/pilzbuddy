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
import 'package:pilzbuddy/features/map/widgets/map_legend.dart'
    show mapIdleCenterProvider;

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
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

    expect(find.textContaining('Linien alle 50 m'), findsOneWidget);
  });

  testWidgets('der Schalter überlebt den Neustart (#349)', (tester) async {
    // **Hier stand bis 1.105.0 das Gegenteil**: „sitzungslokal — nichts
    // wird gemerkt", begründet mit „eine über Nacht vergessene Ebene
    // verwirrt mehr, als der eine Tipp zum Wiedereinschalten kostet".
    // Der Betreiber hat das am 2026-08-28 kassiert (#349), und das
    // Argument war ohnehin dahin: Seit #347 sagt die Zahl am
    // Ebenen-Knopf, welche Ebenen liegen — die Verwirrung, gegen die die
    // Regel stand, gibt es nicht mehr.
    //
    // Der Beweis ist ein zweiter Aufbau mit derselben
    // Einstellungs-Instanz — siehe die Anmerkung weiter unten, warum
    // dazwischen ein leerer Frame stehen MUSS.
    final settings = FakeSettings();
    await pumpApp(tester, loggedInBackend(),
        settings: settings, extraOverrides: withGrid(testGrid()));
    await openLayerSheet(tester, 'Höhenlinien');
    await tester.tap(find.text('Höhenlinien einblenden'));
    await settle(tester);
    expect(containerOf(tester).read(contourLayerEnabledProvider), isTrue);
    expect(settings.contourLayerEnabled, isTrue,
        reason: 'der Schalter merkt selbst — nicht der Aufrufer');

    // **Der Neustart braucht einen leeren Frame dazwischen.** Ein
    // zweiter `pumpApp` allein ist KEINER: Flutter erkennt denselben
    // `ProviderScope` an derselben Stelle wieder, hält sein Element am
    // Leben und damit den ganzen Container — die Provider behalten
    // schlicht ihren Zustand. Der Test war damit grün, auch als
    // `RememberedFlag.build()` die Einstellungen gar nicht mehr las
    // (in der Gegenprobe gemessen). `pumpWidget(SizedBox())` wirft das
    // Element weg, und erst der Aufbau danach liest wirklich neu.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, loggedInBackend(),
        settings: settings, extraOverrides: withGrid(testGrid()));
    expect(containerOf(tester).read(contourLayerEnabledProvider), isTrue,
        reason: 'nach dem Neustart liegt die Ebene wieder');
  });

  testWidgets('Das Ebenen-Blatt packt das Höhengitter NICHT aus',
      (tester) async {
    // Die Zeile trägt seit dem Entwirren die Ablesung („hier 220 m") —
    // und genau da liegt die Falle: `elevationAtProvider` beobachtet das
    // Gitter, und beobachten IST laden (3,4 MB, CLAUDE.md). Ausgerechnet
    // dieses Blatt öffnet man, um die Höhenlinien erst ANZUSCHALTEN.
    // Ohne die Bedingung am Schalter wäre der Wert in der Zeile ein
    // Auspacken bei jedem Öffnen — dieselbe Rechnung, die 1.99.4 aus dem
    // Startpfad genommen hat.
    var loads = 0;
    // **`useRealMap` ist hier keine Kulisse, sondern die Bedingung.**
    // Die Ablesung hängt an `mapIdleCenterProvider`, und den füllt erst
    // eine Karte, die Stillstand meldet. Ohne sie bleibt die Mitte
    // `null`, die Ablesung feuert nie — und der Test wäre grün, auch
    // wenn der Wert ungeprüft in der Zeile stünde. Beim Schreiben genau
    // so passiert: Die Gegenprobe (Ablesung ohne Bedingung geholt) lief
    // durch, weil der Fall gar nicht eintrat.
    await pumpApp(tester, loggedInBackend(), useRealMap: true,
        extraOverrides: [
          elevationLoaderProvider.overrideWithValue(() async {
            loads++;
            return testGrid();
          }),
        ]);
    await settle(tester);
    expect(loads, 0, reason: 'der Start fasst das Gitter nicht an');
    expect(containerOf(tester).read(mapIdleCenterProvider), isNotNull,
        reason: 'ohne gemeldete Mitte prüfte dieser Test nichts');

    await openMapLayers(tester);
    // Die Zusage zuerst — sonst schlüge bei einer Regression die
    // Textzeile an und nicht das, worum es geht.
    expect(loads, 0, reason: 'auch das Ebenen-Blatt lädt das Gitter nicht');
    expect(find.text('Höhenlinien'), findsOneWidget,
        reason: 'die Zeile steht trotzdem da');
    expect(find.text('Gelände, auf dem Gerät gerechnet'), findsOneWidget,
        reason: 'ausgeschaltet nennt die Zeile keinen Wert — es gibt '
            'keinen, ohne ihn zu holen');
  });

  testWidgets('Eingeschaltet steht die Ablesung in der Zeile',
      (tester) async {
    // Dieselbe Zahl wie in der Legende, damit Blatt und Karte nicht zwei
    // Wahrheiten haben. Sichtbar erst, wenn die Ebene an ist — dann ist
    // das Gitter ohnehin geladen, weil die Karte es zeichnet.
    await pumpApp(tester, loggedInBackend(),
        useRealMap: true, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);
    container.read(contourLayerEnabledProvider.notifier).set(true);
    await settle(tester);
    idleAt(container, 150);
    await tester
        .runAsync(() => container.read(elevationContoursProvider.future));
    await settle(tester);

    // Die Ablesung selbst ist ein FutureProvider — ohne diesen Schritt
    // steht sie beim ersten Bildaufbau noch auf `null`, und der Test
    // prüfte die Wartezeit statt der Zusage.
    final centre = container.read(mapIdleCenterProvider);
    expect(centre, isNotNull);
    await tester.runAsync(() => container.read(elevationAtProvider(
        (lat: centre!.latitude, lon: centre.longitude)).future));
    await settle(tester);

    await openMapLayers(tester);
    expect(
        find.descendant(
            of: layerRow('Höhenlinien'),
            matching: find.textContaining('hier ')),
        findsOneWidget,
        reason: 'die Ablesung am Fadenkreuz steht in der Zeile');
    expect(
        find.descendant(
            of: layerRow('Höhenlinien'),
            matching: find.textContaining(' m')),
        findsOneWidget);
  });
}
