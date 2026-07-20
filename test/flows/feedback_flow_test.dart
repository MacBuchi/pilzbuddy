// Das gelbe Melde-Banner auf der Karte: Feedback absenden und ausblenden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

const _bannerText = '💡 Wunsch, Fehler oder Pilzart melden!';

void main() {
  FakeBackend loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  testWidgets('Melde-Banner sendet eine Bug-Meldung ans Backend',
      (tester) async {
    final backend = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text(_bannerText));
    await settle(tester);
    expect(find.text('Wünsch dir was!'), findsOneWidget);
    // Transparenz-Hinweis: Feedback landet öffentlich auf GitHub.
    expect(find.textContaining('öffentlich im GitHub-Projekt'), findsOneWidget);

    await tester.tap(find.text('🐛 Bug'));
    await settle(tester, frames: 4);
    await tester.enterText(
        find.widgetWithText(TextField, 'Was ist passiert?'),
        'Beim Löschen eines Spots bleibt der Marker stehen');
    await tester.tap(find.text('Senden'));
    await settle(tester);

    expect(backend.feedback.single['type'], 'bug');
    expect(backend.feedback.single['message'],
        'Beim Löschen eines Spots bleibt der Marker stehen');
    await drainSnackbars(tester);
  });

  testWidgets('Das Melde-Banner bleibt nach dem Absenden stehen',
      (tester) async {
    // Früher blendete jedes abgeschickte Feedback das Banner aus — das wirkte,
    // als wäre die Meldemöglichkeit verschwunden (Issue #72).
    final backend = loggedInBackend();
    await pumpApp(tester, backend);
    expect(find.text(_bannerText), findsOneWidget);

    await tester.tap(find.text(_bannerText));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Dein Wunsch'), 'Fotos zu Funden');
    await tester.tap(find.widgetWithText(FilledButton, 'Senden'));
    await settle(tester);

    expect(backend.feedback, hasLength(1));
    expect(find.text(_bannerText), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Das X blendet das Melde-Banner aus', (tester) async {
    await pumpApp(tester, loggedInBackend());

    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.text(_bannerText),
        matching: find.byType(Row),
      ),
      matching: find.byIcon(Icons.close),
    ));
    await settle(tester);

    expect(find.text(_bannerText), findsNothing);
  });
}
