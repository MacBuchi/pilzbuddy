// Die gruppierte Knopfspalte auf der Karte (#347).
//
// Der Anlass war eine Messung: zehn Knöpfe, 604 px hoch auf einem
// 915-px-Schirm, seit 1.98.0 in einem `FittedBox(scaleDown)` — jeder
// neue Knopf machte die anderen kleiner. Was diese Datei festhält, ist
// nicht die Zahl, sondern die drei Zusagen, ohne die die Gruppierung ein
// Rückschritt wäre:
//
//   1. Die Spalte wächst nicht heimlich wieder.
//   2. Der Zustand geht nicht verloren — der Zähler trägt ihn.
//   3. Der Ausgang aus einer laufenden Tour bleibt EIN Tipp weit weg,
//      und das Standort-Teilen bleibt daneben erreichbar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/ampel/ampel_map_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_tour.dart';
import '../fakes/map_ui.dart';
import '../fakes/test_app.dart';

void main() {
  FakeBackend signedIn() {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    return backend;
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  Finder fab(String tag) => find.byWidgetPredicate(
      (widget) => widget is FloatingActionButton && widget.heroTag == tag);

  testWidgets('fünf Knöpfe, und die alten sind wirklich weg', (tester) async {
    // Der Wächter gegen das langsame Zurückwachsen. Er nennt die
    // erlaubten Kennungen einzeln: Ein elfter Knopf ist dann keine
    // stille Änderung mehr, sondern eine, die hier vorbeimuss.
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, signedIn());

    for (final tag in ['layers', 'filter', 'trip', 'locate', 'add']) {
      expect(fab(tag), findsOneWidget, reason: 'Knopf „$tag" fehlt');
    }
    // Die aufgelösten: Sie dürfen nicht nebenher weiterleben, sonst wäre
    // nichts gewonnen.
    for (final tag in [
      'offline',
      'forest',
      'terrain',
      'rain',
      'refresh',
      'share-location',
      'tour',
    ]) {
      expect(fab(tag), findsNothing, reason: 'Knopf „$tag" steht noch da');
    }
    // Ohne laufende Tour steht auch kein Stopp-Knopf da.
    expect(tourStopButton(), findsNothing);
  });

  testWidgets('der Zähler nennt, wie viele Ebenen an sind', (tester) async {
    // Der Ersatz für die vier eingefärbten Knöpfe. Für alle, die die
    // Legende ausgeschaltet haben, ist er die einzige Stelle, an der die
    // Karte noch sagt, dass etwas an ist.
    await pumpApp(tester, signedIn());
    final container = containerOf(tester);

    expect(find.descendant(of: fab('layers'), matching: find.text('1')),
        findsNothing);

    container.read(forestLayerEnabledProvider.notifier).state = true;
    await settle(tester);
    expect(find.descendant(of: fab('layers'), matching: find.text('1')),
        findsOneWidget);
  });

  testWidgets('die Ampel aus dem Ebenen-Blatt zieht Wald und Zustimmung mit',
      (tester) async {
    // Dieselbe Kette wie im Regen-Blatt, und das ist der Punkt: Sie steht
    // seit #347 EINMAL (`setAmpelLayerEnabled`). Ohne Waldebene hätte das
    // Leuchten nichts, worauf es liegen könnte; ohne die Zustimmung keine
    // Daten. Eine zweite Bedienstelle, die nur den einen Schalter
    // umlegte, ergäbe eine Ampel, die nichts zeigt.
    final settings = FakeSettings(ampelPreviewEnabled: true);
    await pumpApp(tester, signedIn(), settings: settings);
    final container = containerOf(tester);

    expect(container.read(forestLayerEnabledProvider), isFalse);
    expect(container.read(rainCourseEnabledProvider), isFalse);

    await toggleLayer(tester, 'Pilzampel');

    expect(container.read(ampelLayerEnabledProvider), isTrue);
    expect(container.read(forestLayerEnabledProvider), isTrue,
        reason: 'ohne Waldwaben hätte das Leuchten keinen Träger');
    expect(container.read(rainCourseEnabledProvider), isTrue);
    expect(settings.rainCourseEnabled, isTrue,
        reason: 'die Zustimmung muss den Neustart überleben');
  });

  testWidgets('läuft eine Tour, steht ihr Ausgang NEBEN dem Unterwegs-Knopf',
      (tester) async {
    // Die Entscheidung, die den Entwurf gerettet hat. Der erste Anlauf
    // machte „Unterwegs" bei laufender Tour selbst zum Stopp-Knopf —
    // damit wäre das Standort-Teilen während einer Tour unerreichbar
    // gewesen. Beides muss dastehen: ein Tipp zum Beenden, und der Weg
    // zum Teilen bleibt offen.
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      signedIn(),
      tourStore: FakeTourStore(),
      tourFix: FakeTourFix(),
      tourBridge: FakeTourServiceBridge(),
    );

    expect(tourStopButton(), findsNothing);

    await startTour(tester);

    expect(tourStopButton(), findsOneWidget,
        reason: 'ein Tipp zum Beenden, nicht zwei');
    expect(fab('trip'), findsOneWidget,
        reason: 'und „Unterwegs" bleibt daneben stehen — sonst käme man '
            'während einer Tour nicht mehr ans Standort-Teilen');

    // Und der Weg dorthin trägt auch wirklich.
    await openTrip(tester);
    expect(find.text('Standort mit Buddies teilen'), findsOneWidget);
    expect(find.text('Pilztour beenden'), findsOneWidget);
  });
}
