// Die Waldtypen-Ebene (#213) von Hand: FAB → Blatt → an, die
// Exklusivität mit dem Regen, die Spot-Zeile — und dass ohne Gitter
// alles still fehlt.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';
import '../forest_grid_test.dart' show forestOf;

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

  testWidgets('Wald an schaltet Regen ab — und umgekehrt', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withGrid(testGrid()));
    final container = containerOf(tester);

    // Regen an (direkt am Zustand — das Regen-Blatt hat eigene Tests).
    container.read(rainLayerProvider.notifier).state = RainLayer.last30d;
    await settle(tester);

    await tester.tap(find.byTooltip('Waldtypen'));
    await settle(tester);
    expect(find.text('Blendet dafür die Regenebene aus.'), findsOneWidget);
    await tester.tap(find.text('Waldtypen einblenden'));
    await settle(tester);

    expect(container.read(forestLayerEnabledProvider), isTrue);
    expect(container.read(rainLayerProvider), RainLayer.off,
        reason: 'zwei halbtransparente Flächen übereinander sind unlesbar');

    // Umgekehrt: Regen wieder an nimmt den Wald raus (Regen-Blatt-Weg).
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    await tester.tap(find.text('Letzte 30 Tage'));
    await settle(tester);
    expect(container.read(forestLayerEnabledProvider), isFalse);
    expect(container.read(rainLayerProvider), RainLayer.last30d);
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
