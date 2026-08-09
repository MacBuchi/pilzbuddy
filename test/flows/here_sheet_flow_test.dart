// „Was ist hier?" (#245): Tipp auf die Karten-Legende öffnet die Werte
// des Spot-Blatts für eine beliebige Stelle.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/widgets/map_legend.dart'
    show mapIdleCenterProvider;

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

  /// Wie im Waldebenen-Test: Nordhälfte Laub, Südhälfte Nadel. Die
  /// Kartenmitte (51,1634°) liegt in der Nordhälfte.
  ForestGrid testGrid() => forestOf([
        [11, 11, 11],
        [96, 96, 96],
      ], west: 5.8, east: 15.4, north: 55.1, south: 47.0);

  List<Override> withGrid(ForestGrid? grid) => [
        forestGridLoaderProvider.overrideWithValue(() async => grid),
      ];

  /// Waldebene an und die Kamera „zum Stehen bringen" — ohne
  /// Stillstands-Mitte zeigt die Legende keine Werte und öffnet nichts.
  Future<void> showLegend(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Waldtypen'));
    await settle(tester);
    await tester.tap(find.text('Waldtypen einblenden'));
    final container = containerOf(tester);
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20)); // Blatt schließen
    await settle(tester);
    container.read(mapIdleCenterProvider.notifier).state =
        const LatLng(51.1634, 10.4477);
    await settle(tester);
  }

  testWidgets('Tipp auf die Legende öffnet die Werte dieser Stelle',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withGrid(testGrid()));
    await showLegend(tester);

    // Die Legende zeigt den Laubfaktor …
    expect(find.textContaining('Laubfaktor'), findsOneWidget);
    await tester.tap(find.textContaining('Laubfaktor'));
    await settle(tester);

    // … und das Blatt die volle Auskunft zu genau diesem Punkt.
    expect(find.text('Was ist hier?'), findsOneWidget);
    expect(find.textContaining('51,1634 N'), findsOneWidget);
    expect(find.textContaining('10,4477 O'), findsOneWidget);
    expect(find.textContaining('Wald hier:'), findsOneWidget);
    expect(find.textContaining('Laubwald'), findsOneWidget);
    // Der Regenteil bietet sich an (er ist ab Werk aus) — genau wie im
    // Spot-Blatt, damit niemand ungefragt Daten nachlädt.
    expect(find.textContaining('Regen'), findsWidgets);
  });

  testWidgets('ohne Kamera-Stillstand öffnet der Tipp nichts',
      (tester) async {
    // Die Legende steht dann ohne Werte da; ein Blatt über „nichts" wäre
    // eine leere Auskunft, und der Tipp gehört der Karte.
    //
    // Der Zustand wird hier von Hand hergestellt: Die echte Karte meldet
    // ihren ersten Stillstand sofort nach dem Aufbau, es gibt also kaum
    // ein Zeitfenster dafür — die Absicherung muss trotzdem stimmen,
    // sonst hinge sie an einer Zusage der Engine.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withGrid(testGrid()));
    await showLegend(tester);

    final container = containerOf(tester);
    container.read(mapIdleCenterProvider.notifier).state = null;
    await settle(tester);

    expect(find.text('Waldtypen'), findsOneWidget,
        reason: 'Legende ohne Messwerte');
    await tester.tap(find.text('Waldtypen'));
    await settle(tester);
    expect(find.text('Was ist hier?'), findsNothing);
  });
}
