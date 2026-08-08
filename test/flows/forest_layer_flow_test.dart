// Die Waldtypen-Ebene (#213) von Hand: FAB → Blatt → an, die
// Exklusivität mit dem Regen, die Spot-Zeile — und dass ohne Gitter
// alles still fehlt.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';
import 'package:pilzbuddy/features/map/widgets/map_legend.dart'
    show mapIdleCenterProvider;

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';
import '../forest_grid_test.dart' show forestOf;
import '../rain_fill_test.dart' show decodePng;

void main() {
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Ein DACH-großes Gitter, zwei Zeilen: Die Kartenmitte (51,1634°)
  /// liegt knapp ÜBER der Gittermitte (51,05°), also in Zeile 0 — die
  /// ist Laub, damit die Spot-Zeile etwas Konkretes zu sagen hat.
  ForestGrid testGrid() => forestOf([
        [11, 11, 11], // 10 % Nadel → Laub (Nordhälfte, mit Kartenmitte)
        [96, 96, 96], // 95 % Nadel (Südhälfte)
      ], west: 5.8, east: 15.4, north: 55.1, south: 47.0);

  List<Override> withGrid(ForestGrid? grid) => [
        forestGridLoaderProvider.overrideWithValue(() async => grid),
      ];

  testWidgets('FAB → Blatt → einschalten legt die Fläche auf die Karte',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withGrid(testGrid()));

    await tester.tap(find.byTooltip('Waldtypen'));
    await settle(tester);
    expect(find.text('Waldtypen einblenden'), findsOneWidget);
    expect(find.textContaining('250-m-Raster'), findsOneWidget);
    expect(find.textContaining('Copernicus'), findsOneWidget);

    await tester.tap(find.text('Waldtypen einblenden'));
    // Der Fill rechnet im Isolate — wie beim Regen (settleRain) unter
    // runAsync auf den Provider selbst warten, nicht auf eine geratene
    // Frist.
    final container = containerOf(tester);
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);
    // Legende erscheint im Blatt …
    expect(find.text('Nadelwald'), findsOneWidget);

    // … und auf der Karte liegt das Overlay mit den GITTER-Grenzen.
    await tester.tapAt(const Offset(20, 20)); // Blatt schließen
    await settle(tester);
    final overlays = tester
        .widgetList<OverlayImageLayer>(find.byType(OverlayImageLayer))
        .toList();
    expect(overlays, hasLength(1));
    final image = overlays.single.overlayImages.single as OverlayImage;
    expect(image.bounds.north, 55.1);
    expect(image.bounds.west, 5.8);
  });

  testWidgets('Regen und Wald liegen GLEICHZEITIG auf der Karte (#232)',
      (tester) async {
    // Die Umkehrung der früheren Exklusivität: Mit den Teil-Ebenen
    // (#231) ist die Kombination lesbar — Regen über der Waldklasse,
    // die einen interessiert, ist genau die Pilzfrage.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);

    // Regen an (direkt am Zustand — das Regen-Blatt hat eigene Tests).
    container.read(rainLayerProvider.notifier).state = RainLayer.last30d;
    await settle(tester);

    await tester.tap(find.byTooltip('Waldtypen'));
    await settle(tester);
    expect(find.text('Blendet dafür die Regenebene aus.'), findsNothing,
        reason: 'der Hinweis auf die alte Exklusivität wäre eine Lüge');
    await tester.tap(find.text('Waldtypen einblenden'));
    await settle(tester);

    expect(container.read(forestLayerEnabledProvider), isTrue);
    expect(container.read(rainLayerProvider), RainLayer.last30d,
        reason: 'Wald an darf den Regen nicht mehr abschalten');

    // Und im Regen-Blatt schaltet eine Ebenen-Wahl den Wald nicht ab.
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    await tester.tap(find.text('Letzte 24 Stunden'));
    await settle(tester);
    expect(container.read(forestLayerEnabledProvider), isTrue);
    expect(container.read(rainLayerProvider), RainLayer.last24h);
  });

  testWidgets('abgewählte Klassen verschwinden aus Fläche und Legende '
      '(#231)', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);

    await tester.tap(find.byTooltip('Waldtypen'));
    await settle(tester);
    await tester.tap(find.text('Waldtypen einblenden'));
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);

    // Laub und Misch abwählen — übrig bleibt Nadel.
    await tester.tap(find.text('Laubwald'));
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);
    await tester.tap(find.text('Mischwald'));
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);
    expect(container.read(forestClassesProvider), {ForestClass.conifer});

    // Auf der Karte ist die Laub-Zeile des Gitters jetzt durchsichtig,
    // die Nadel-Zeile nicht — die Checkbox wirkt bis ins Bild.
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    final fill = container.read(forestFillProvider).valueOrNull;
    expect(fill, isNotNull);
    final png = decodePng(fill!.png);
    expect(png.pixels[3], 0, reason: 'Zeile 0 (Laub) ist abgewählt');
    expect(png.pixels[png.width * 4 + 3], isPositive,
        reason: 'Zeile 1 (Nadel) bleibt');

    // Die Karten-Legende ist seit #235 eine Skala: Ihre Achsen-Enden
    // bleiben stehen, aber die abgewählten Segmente sind blass.
    expect(find.text('Laub'), findsOneWidget,
        reason: 'Achsen-Label der Skala, keine Klassen-Zeile');
    Container segmentOf(Color colour, double alpha) =>
        tester.widget<Container>(find.byWidgetPredicate((w) =>
            w is Container &&
            w.color == colour.withValues(alpha: alpha)));
    expect(segmentOf(AppColors.forestConifer, 0.55), isNotNull,
        reason: 'gewählte Klasse voll sichtbar');
    expect(segmentOf(AppColors.forestBroadleaf, 0.15), isNotNull,
        reason: 'abgewählte Klasse blass');
  });

  testWidgets('die Karten-Legende zeigt aktive Ebenen; das X merkt sich '
      'das Aus (#231)', (tester) async {
    final (backend, _) = loggedInBackend();
    final settings = FakeSettings();
    await pumpApp(tester, backend,
        settings: settings, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);

    // Ebene direkt am Zustand an (den Blatt-Weg prüft der Test oben).
    await tester.runAsync(() => container.read(forestGridProvider.future));
    container.read(forestLayerEnabledProvider.notifier).state = true;
    await settle(tester);
    expect(find.text('Waldtypen'), findsOneWidget,
        reason: 'Legende liegt auf der Karte');

    // Das X blendet aus — persistent.
    await tester.tap(find.byTooltip('Legende ausblenden'));
    await settle(tester);
    expect(find.text('Waldtypen'), findsNothing);
    expect(settings.mapLegendEnabled, isFalse,
        reason: 'das X überlebt den Neustart');

    // Zurück geht es über den Schalter im Ebenen-Blatt (im Blatt muss
    // man dafür ans Ende scrollen — das Blatt ist seit den Checkboxen
    // scrollbar).
    await tester.tap(find.byTooltip('Waldtypen'));
    await settle(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -220));
    await settle(tester);
    await tester.tap(find.text('Legende in Karte anzeigen'));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(find.text('Waldtypen'), findsOneWidget);
    expect(settings.mapLegendEnabled, isTrue);
  });

  testWidgets('Fadenkreuz-Werte: Kamera-Stillstand setzt den Messstrich '
      'in die Legende (#235)', (tester) async {
    // Echte Karte: flutter_map meldet onMapReady und MoveEnd — daran
    // hängt der Idle-Provider, an dem die Legende rechnet.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);

    await tester.runAsync(() => container.read(forestGridProvider.future));
    container.read(forestLayerEnabledProvider.notifier).state = true;
    await settle(tester);

    // onMapReady hat die Startmitte gemeldet (Zeile 0 des Gitters:
    // Byte 11 = 10 % Nadel → Laubfaktor 0,90) — Strich und Titelwert da.
    expect(container.read(mapIdleCenterProvider), isNotNull,
        reason: 'die Karte meldet ihre Mitte beim Bereitwerden');
    expect(find.textContaining('Laubfaktor 0,90'), findsOneWidget);
    expect(find.byKey(const Key('legend-forest-marker')), findsOneWidget);

    // Karte nach Norden ziehen → Mitte wandert nach SÜDEN in Zeile 1
    // (Byte 96 = 95 % Nadel → 0,05). Der Wert folgt dem Stillstand.
    await tester.drag(find.byType(FlutterMap), const Offset(0, -220));
    await settle(tester);
    expect(find.textContaining('Laubfaktor 0,05'), findsOneWidget);
  });

  testWidgets('Die Spot-Zeile nennt die Klasse am Spot', (tester) async {
    final (backend, me) = loggedInBackend();
    // Kartenmitte (51.1634, 10.4477) → Zeile 0 des Gitters, Laub.
    backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    await pumpApp(tester, backend, extraOverrides: withGrid(testGrid()));

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);

    expect(find.textContaining('Wald hier: überwiegend Laubwald'),
        findsOneWidget);
    expect(find.textContaining('(10 % Nadel)'), findsOneWidget);
    expect(find.textContaining('Stand 2021'), findsOneWidget);
  });

  testWidgets('Ohne Gitter fehlt alles still', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    // Kein extraOverride: Die globale Naht liefert null.
    await pumpApp(tester, backend);

    expect(find.byTooltip('Waldtypen'), findsNothing,
        reason: 'ein Knopf auf ein fehlendes Asset wäre ein Fehler ohne '
            'Fehlermeldung');

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    expect(find.textContaining('Wald hier'), findsNothing);
  });
}
