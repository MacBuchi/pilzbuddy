// Der Push-Schalter im Profil (#277).
//
// Der Punkt dieser Tests ist nicht, dass ein Schalter umspringt, sondern
// dass er die WAHRHEIT zeigt: Beim Einschalten hängt ein Systemdialog
// dazwischen, und wer dort ablehnt, bekommt kein Token. Ein Schalter, der
// dann trotzdem auf „an" stünde, wäre die teuerste Sorte Lüge — man merkt
// sie erst, wenn eine erwartete Meldung ausbleibt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/push_messaging.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  Future<FakeSettings> openProfile(WidgetTester tester, FakeBackend backend,
      {FakeSettings? settings, List<Override> extra = const []}) async {
    final used = settings ?? FakeSettings();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: used, extraOverrides: extra);
    await tester.tap(find.text('Profil'));
    await settle(tester);
    return used;
  }

  /// Der Schalter, nachdem er wirklich im Baum ist.
  ///
  /// Das Profil ist eine LAZY Liste: Weiter unten stehende Einträge
  /// existieren gar nicht, bis dorthin gescrollt wurde — `ensureVisible`
  /// scheitert dann mit „No element" statt mit einer Aussage über den
  /// Schalter.
  Future<Finder> pushToggle(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Benachrichtigungen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    return find.ancestor(
        of: find.text('Benachrichtigungen'),
        matching: find.byType(SwitchListTile));
  }

  testWidgets('ab Werk aus — und der Schalter ist da', (tester) async {
    final backend = FakeBackend();
    await openProfile(tester, backend);
    final toggle = await pushToggle(tester);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse,
        reason: 'Benachrichtigungen sind ab Werk aus');
    expect(find.text('Testnachricht senden'), findsNothing,
        reason: 'ohne eingetragenes Gerät gibt es nichts zu testen');
  });

  testWidgets('einschalten trägt das Gerät ein und merkt sich das Token',
      (tester) async {
    final backend = FakeBackend();
    final settings = await openProfile(tester, backend);
    final toggle = await pushToggle(tester);
    await tester.tap(toggle);
    await settle(tester);

    expect(settings.pushToken, 'test-token',
        reason: 'ohne gemerktes Token wüsste die App beim Abschalten '
            'nicht, welche Zeile zu löschen ist');
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text('Testnachricht senden'), findsOneWidget,
        reason: 'erst jetzt gibt es etwas zu beweisen');
  });

  testWidgets('wer die Berechtigung ablehnt, sieht den Schalter '
      'zurückspringen', (tester) async {
    final backend = FakeBackend();
    // Kein Token = abgelehnt. Genau der Weg, den ein Systemdialog nimmt,
    // den jemand wegtippt.
    final settings = await openProfile(tester, backend, extra: [
      pushTokenProvider.overrideWithValue(() async => null),
    ]);
    final toggle = await pushToggle(tester);
    await tester.tap(toggle);
    await settle(tester);

    expect(tester.widget<SwitchListTile>(toggle).value, isFalse,
        reason: 'der Schalter zeigt das Ergebnis, nicht den Wunsch');
    expect(settings.pushToken, isNull);
    expect(find.textContaining('nicht erlaubt'), findsOneWidget,
        reason: 'und sagt auch, woran es lag');
  });

  testWidgets('ausschalten löscht das gemerkte Token wieder',
      (tester) async {
    final backend = FakeBackend();
    final settings = await openProfile(tester, backend);
    final toggle = await pushToggle(tester);
    await tester.tap(toggle);
    await settle(tester);
    expect(settings.pushToken, isNotNull, reason: 'Vorspann: erst an');

    await tester.tap(toggle);
    await settle(tester);
    expect(settings.pushToken, isNull,
        reason: 'kein Token heißt: dieses Gerät bekommt nichts mehr');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('Testnachricht senden'), findsNothing);
  });
}
