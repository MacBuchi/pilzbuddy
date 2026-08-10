// Der Vorab-Kanal (#269): ein Schalter im Profil unter „Über PilzBuddy",
// Vorgabe AUS.
//
// Warum das ein eigener Flow-Test ist: Der Schalter hebt für dieses Gerät
// genau den Schutz auf, den die Kanaltrennung (#262) für alle anderen
// aufbaut — jeder Merge baut ein Release, aber als Prerelease, und
// `/releases/latest` liefert grundsätzlich keine. Ein still auf „an"
// stehender Schalter wäre also keine Kleinigkeit, sondern der Unterschied
// zwischen „freigegeben" und „irgendein Zwischenstand".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/update_check.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  /// Zum Schalter im Abschnitt „Über PilzBuddy" scrollen.
  ///
  /// In Schritten statt in einem Rutsch: Die Liste ist LAZY, der Eintrag
  /// existiert also erst, wenn er in die Nähe des Bildes kommt — und ein
  /// zu weiter Zug schiebt ihn oben wieder hinaus (dort trifft kein
  /// `tap` mehr, so beim ersten Lauf dieses Tests passiert).
  Future<void> openAbout(WidgetTester tester) async {
    await tester.tap(find.text('Profil'));
    await settle(tester);
    final schalter = find.text('Vorabversionen erhalten');
    for (var i = 0; i < 8 && schalter.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
  }

  testWidgets('Vorgabe aus, Umlegen wird gemerkt', (tester) async {
    final settings = FakeSettings();
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: settings);

    await openAbout(tester);
    final tile = find.ancestor(
        of: find.text('Vorabversionen erhalten'),
        matching: find.byType(SwitchListTile));
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse,
        reason: 'Vorgabe AUS — den Vorab-Kanal wählt man ausdrücklich');

    await tester.tap(find.text('Vorabversionen erhalten'));
    await settle(tester);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    expect(container.read(prereleaseUpdatesProvider), isTrue);
    expect(settings.prereleaseUpdatesEnabled, isTrue,
        reason: 'eine Kanal-Entscheidung trifft man nicht bei jedem Start neu');

    // Neustart mit denselben Einstellungen: Die Wahl steht noch.
    await pumpApp(tester, backend, settings: settings);
    final again = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    expect(again.read(prereleaseUpdatesProvider), isTrue);
  });

  testWidgets('ein gemerktes „an" gilt nur, wo der Update-Weg läuft',
      (tester) async {
    // Der Riegel sitzt im Provider, nicht nur in der Oberfläche: Wäre er
    // nur dort, käme ein auf einem Android-Gerät gesetztes „an" im
    // Play-Build oder im Web durch und die App fragte GitHub nach
    // Ständen, die sie von dort gar nicht installieren darf.
    final settings = FakeSettings(prereleaseUpdatesEnabled: true);
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: settings);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    expect(container.read(prereleaseUpdatesProvider), updateChecksApply,
        reason: 'der gespeicherte Wert gilt genau dann, wenn es einen '
            'Update-Weg gibt');
  });
}
