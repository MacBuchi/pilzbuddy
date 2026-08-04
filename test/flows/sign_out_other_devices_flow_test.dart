// Andere Geräte abmelden (Issue #196).
//
// Der Fall dahinter: Passwort auf verlorenem Gerät geändert — das alte
// Passwort gilt dort nicht mehr, die laufende Sitzung aber schon. Der
// Knopf beendet sie. Zwei Dinge müssen stimmen: Es wird wirklich
// widerrufen, und die EIGENE Sitzung bleibt — ein Knopf, der einen
// selbst mit abmeldet, wäre schlimmer als keiner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Profil'));
  await settle(tester);
  final tile = find.text('Andere Geräte abmelden');
  for (var i = 0; i < 6 && tile.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester, frames: 4);
  }
  await tester.ensureVisible(tile);
  await settle(tester);
  await tester.tap(tile);
  await settle(tester);
}

FakeBackend _signedIn() {
  final backend = FakeBackend();
  final me = backend.addUser(username: 'testpilz');
  backend.signInAs(me.id);
  return backend;
}

void main() {
  testWidgets('Bestätigen widerruft — und die eigene Sitzung bleibt',
      (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    expect(find.textContaining('Dieses Gerät bleibt angemeldet'),
        findsOneWidget,
        reason: 'Die Rückfrage muss sagen, was passiert — sonst traut '
            'sich niemand zu tippen.');
    await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
    await settle(tester);

    expect(backend.otherSessionsRevoked, 1);
    expect(backend.currentUserId, isNotNull,
        reason: 'Die eigene Sitzung darf der Widerruf nicht mitreißen.');
    expect(find.text('Alle anderen Geräte wurden abgemeldet.'),
        findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Abbrechen widerruft nichts', (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
    await settle(tester);

    expect(backend.otherSessionsRevoked, 0,
        reason: 'Die Rückfrage existiert genau dafür, dass ein Fehltipp '
            'folgenlos bleibt.');
  });
}
