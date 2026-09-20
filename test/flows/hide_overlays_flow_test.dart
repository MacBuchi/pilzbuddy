// Der Vorhang über den Datenflächen (#464).
//
// Der Wunsch kam mit einem Grund, und der Grund entscheidet den
// Zuschnitt: „wenn man sich auf der OSM-/Online-Karte orientieren will".
// Es geht also NICHT darum, die Bedienelemente wegzublenden, sondern die
// halbdurchsichtigen Flächen, die über der Karte liegen — Wald, Ampel,
// Regen, Höhenlinien. Grundkarte und Marker bleiben; eine Orientierung
// ohne die eigenen Spots wäre keine.
//
// Geprüft wird an der echten Oberfläche, weil der teure Fehler nicht
// „lässt sich nicht ausblenden" wäre, sondern „kommt nicht mehr zurück"
// — der Knopf verspricht einen Rückweg.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/map_overlays.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';
import 'package:pilzbuddy/features/map/widgets/map_legend.dart';

import '../fakes/fake_backend.dart';
import '../fakes/map_ui.dart';
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

  ForestGrid testGrid() => forestOf([
        [11, 11, 11],
        [96, 96, 96],
      ], west: 5.8, east: 15.4, north: 55.1, south: 47.0);

  List<Override> withGrid() => [
        forestGridLoaderProvider.overrideWithValue(() async => testGrid()),
      ];

  Finder hideButton() => find.byTooltip('Ebenen ausblenden');
  Finder showButton() => find.byTooltip('Ebenen einblenden');

  testWidgets('Ohne eingeschaltete Ebene gibt es den Knopf nicht',
      (tester) async {
    // Alle Ebenen stehen ab Werk auf aus. Ein Knopf, der nichts
    // auszublenden hat, wäre der fünfte in einer Leiste, die #440
    // mühsam auf vier gebracht hat.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withGrid());

    expect(hideButton(), findsNothing);
    expect(showButton(), findsNothing);
  });

  testWidgets('Mit einer Ebene erscheint er — und nimmt die Fläche weg',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withGrid());
    final container = containerOf(tester);

    await openLayerSheet(tester, 'Waldtypen');
    await tester.tap(find.text('Waldtypen einblenden'));
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);

    expect(tester.widgetList(find.byType(OverlayImageLayer)), hasLength(1));
    expect(hideButton(), findsOneWidget);

    await tester.tap(hideButton());
    await settle(tester);

    expect(tester.widgetList(find.byType(OverlayImageLayer)), isEmpty,
        reason: 'die Fläche ist weg');
    expect(showButton(), findsOneWidget,
        reason: 'der Knopf sagt jetzt das Gegenteil — er IST der Rückweg');
  });

  testWidgets('Der Schalter selbst bleibt an — und die Fläche kommt zurück',
      (tester) async {
    // Die Zusage des Betreibers: „beim Einschalten sollten alle
    // vorausgewählten Ebenen berücksichtigt werden." Sie fällt hier
    // heraus, statt hergestellt zu werden: Der Vorhang fasst die
    // Einstellungen nicht an, es gibt also keinen Schnappschuss, der
    // falsch sein könnte.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withGrid());
    final container = containerOf(tester);

    await openLayerSheet(tester, 'Waldtypen');
    await tester.tap(find.text('Waldtypen einblenden'));
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);

    await tester.tap(hideButton());
    await settle(tester);
    expect(container.read(forestLayerEnabledProvider), isTrue,
        reason: 'ausgeblendet ist nicht ausgeschaltet');

    await tester.tap(showButton());
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);

    expect(tester.widgetList(find.byType(OverlayImageLayer)), hasLength(1));
    expect(hideButton(), findsOneWidget);
  });

  testWidgets('Die Legende verschwindet mit den Flächen', (tester) async {
    // Sie nennt jede aktive Ebene samt Farbskala. Sie weiter
    // aufzuzählen, während die Karte nackt ist, wäre die Behauptung
    // einer Ebene, die niemand sieht.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withGrid());
    final container = containerOf(tester);

    await openLayerSheet(tester, 'Waldtypen');
    await tester.tap(find.text('Waldtypen einblenden'));
    await tester.runAsync(() => container.read(forestFillProvider.future));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    // Gemessen wird der PLATZ, nicht ein Text: Eingeklappt nennt die
    // Legende die Klassen gar nicht (das tut nur das Panel), sie ist
    // dann eine 40-px-Schiene. „Ist sie da?" ist hier also eine Frage
    // nach ihrer Größe — und `find.byType` wäre die falsche: Das Widget
    // bleibt im Baum, es baut nur nichts mehr.
    expect(tester.getSize(find.byType(MapLegend)).height, greaterThan(0));

    await tester.tap(hideButton());
    await settle(tester);

    expect(tester.getSize(find.byType(MapLegend)), Size.zero,
        reason: 'die Legende erklärt nichts, was nicht dasteht');
  });

  testWidgets('Der Vorhang dreht auch den Regen ab', (tester) async {
    // Der Regen ist der einzige, der den Umweg über
    // `drawnRainLayerProvider` nimmt: Aus der gewählten Ebene folgen
    // Grenzen, Darstellung, Fläche UND das DWD-Bild. Wird sie nicht auf
    // `off` gedreht, bliebe das DWD-Bild liegen, während Wald und
    // Höhenlinien verschwinden — der halbe Vorhang.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withGrid());
    final container = containerOf(tester);

    container.read(rainLayerProvider.notifier).state = RainLayer.now;
    await settle(tester);
    expect(container.read(drawnRainLayerProvider), RainLayer.now);

    await tester.tap(hideButton());
    await settle(tester);

    expect(container.read(drawnRainLayerProvider), RainLayer.off,
        reason: 'gezeichnet wird nichts …');
    expect(container.read(rainLayerProvider), RainLayer.now,
        reason: '… gewählt bleibt die Ebene');
  });

  testWidgets('Ein Neustart hebt den Vorhang', (tester) async {
    // Sitzungsgrenze wie bei der Banner-Stummschaltung (#425): Ein
    // Zustand, der ein Feature wegnimmt und den Neustart überdauert,
    // wird als Fehler gemeldet statt als eigene Entscheidung erkannt.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withGrid());
    final container = containerOf(tester);
    container.read(forestLayerEnabledProvider.notifier).state = true;
    await settle(tester);

    await tester.tap(hideButton());
    await settle(tester);
    expect(container.read(mapOverlaysHiddenProvider), isTrue);

    // Leerer Frame dazwischen, sonst ist es kein Neustart, sondern ein
    // zweiter Aufbau derselben Riverpod-Wurzel.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester, backend, extraOverrides: withGrid());

    expect(containerOf(tester).read(mapOverlaysHiddenProvider), isFalse);
  });
}
