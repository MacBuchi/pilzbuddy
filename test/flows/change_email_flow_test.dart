// E-Mail-Adresse ändern (Issue #193).
//
// Die Adresse ist die Konto-Identität: Freundessuche und Reset-Code
// hängen an ihr. Der Wechsel verlangt das aktuelle Passwort und die
// Codes aus BEIDEN Postfächern — der Fake spiegelt genau die Semantik,
// die tool/auth_reset_check.sh gegen echtes GoTrue gemessen hat: ein
// Code allein ändert nichts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Profil'));
  await settle(tester);
  final tile = find.text('E-Mail-Adresse ändern');
  for (var i = 0; i < 6 && tile.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester, frames: 4);
  }
  await tester.ensureVisible(tile);
  await settle(tester);
  await tester.tap(tile);
  await settle(tester);
}

Future<void> _requestChange(WidgetTester tester,
    {String password = 'geheim123',
    String newEmail = 'neu@test.de'}) async {
  await tester.enterText(
      find.widgetWithText(TextField, 'Aktuelles Passwort'), password);
  await tester.enterText(
      find.widgetWithText(TextField, 'Neue E-Mail-Adresse'), newEmail);
  await settle(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
  await settle(tester);
}

FakeBackend _signedIn() {
  final backend = FakeBackend();
  final me = backend.addUser(username: 'testpilz', email: 'alt@test.de');
  backend.signInAs(me.id);
  return backend;
}

void main() {
  testWidgets('Der komplette Wechsel: Passwort, beide Codes, neue Adresse',
      (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    expect(find.text('Bisher: alt@test.de'), findsOneWidget,
        reason: 'Wovon gewechselt wird, muss dastehen.');
    await _requestChange(tester);

    // Codephase: beide Codes, feste Beschriftung je Postfach.
    expect(find.textContaining('Zwei Mails sind unterwegs'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Code an die bisherige Adresse'),
        backend.emailChangeOldCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Code an die neue Adresse'),
        backend.emailChangeNewCode);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Bestätigen'));
    await settle(tester);

    expect(backend.users.single.email, 'neu@test.de');
    expect(find.text('Deine E-Mail-Adresse ist geändert.'), findsOneWidget);
    expect(backend.currentUserId, isNotNull,
        reason: 'Der Wechsel bringt eine frische Sitzung — er darf '
            'niemanden aussperren.');
    expect(find.text('neu@test.de'), findsOneWidget,
        reason: 'Die Kachel muss die neue Adresse SOFORT zeigen — am '
            'Emulator stand ohne den authState-Draht die alte da, bis '
            'irgendetwas anderes neu baute.');
    await drainSnackbars(tester);
  });

  testWidgets('Ein falsches aktuelles Passwort stößt nichts an',
      (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await _requestChange(tester, password: 'falsch888');

    expect(find.text('Das aktuelle Passwort stimmt nicht.'), findsOneWidget);
    expect(backend.pendingEmailChange, isNull,
        reason: 'Ohne Passwort keine Mails — sonst könnte ein gestohlenes '
            'Session-Token den Umzug anstoßen.');
    expect(find.widgetWithText(TextField, 'Aktuelles Passwort'),
        findsOneWidget,
        reason: 'Der Dialog bleibt in der ersten Phase.');
  });

  testWidgets('Eine vergebene Adresse wird beim Namen genannt',
      (tester) async {
    final backend = _signedIn();
    backend.addUser(username: 'anderer', email: 'belegt@test.de');
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await _requestChange(tester, newEmail: 'belegt@test.de');

    expect(find.text('Für diese Adresse gibt es schon ein Konto.'),
        findsOneWidget);
  });

  testWidgets('Ein Code allein ändert nichts — auch nicht mit einem '
      'falschen zweiten', (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);
    await _requestChange(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Code an die bisherige Adresse'),
        backend.emailChangeOldCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Code an die neue Adresse'),
        '000000');
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Bestätigen'));
    await settle(tester);

    expect(find.textContaining('falsch oder abgelaufen'), findsOneWidget);
    expect(backend.users.single.email, 'alt@test.de',
        reason: 'Genau die Zusicherung von Secure email change: ein '
            'Postfach allein reicht nicht.');
  });

  testWidgets('Abbrechen in der Codephase lässt die Adresse stehen',
      (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);
    await _requestChange(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
    await settle(tester);

    expect(backend.users.single.email, 'alt@test.de');
  });
}
