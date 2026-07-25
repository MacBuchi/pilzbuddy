// „Passwort vergessen" — vom Anfordern des Codes bis zum neuen Passwort,
// komplette App gegen das In-Memory-Backend (siehe test/fakes/).
//
// Der Reset läuft absichtlich über den Zahlencode aus der Mail und nicht
// über deren Link: Der Link ist an das Gerät gebunden, das ihn angefordert
// hat (PKCE-Verifier im lokalen Speicher), und stirbt daher, wenn die Mail
// woanders geöffnet wird. Siehe AuthRepository.sendPasswordResetCode.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Erst ins Bild holen, dann tippen: Der Reset-Modus zeigt vier Felder und
/// einen Hinweis, damit rutscht der Knopf im kleinen Test-Viewport unter den
/// sichtbaren Rand — ein Tap daneben warnt nur, statt zu scheitern, und der
/// Test liefe stumm ins Leere.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

/// Bringt den Login-Screen in den Code-Modus: E-Mail eintragen, Code
/// anfordern. Die Vorbedingung der meisten Tests hier.
Future<void> _requestCode(WidgetTester tester, String email) async {
  await _tap(tester, find.text('Passwort vergessen?'));
  await tester.enterText(find.widgetWithText(TextField, 'E-Mail'), email);
  await _tap(tester, find.text('Code anfordern'));
}

void main() {
  testWidgets('Passwort vergessen fragt nur die E-Mail ab', (tester) async {
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);

    await _tap(tester, find.text('Passwort vergessen?'));

    expect(find.byType(TextField), findsOneWidget,
        reason: 'Im Reset-Modus gibt es kein Passwortfeld — nur die E-Mail. '
            'Sonst tippt man dort das vergessene Passwort ein.');
    expect(find.text('Code anfordern'), findsOneWidget);
  });

  testWidgets('Unbekannte Adresse verrät nicht, dass es kein Konto gibt',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);

    await _requestCode(tester, 'gibtesnicht@test.de');

    // Dieselbe Meldung wie im Erfolgsfall, und die Anfrage ist trotzdem
    // vermerkt: Wer hier unterscheidet, baut ein Konto-Orakel.
    expect(find.textContaining('Wenn es zu gibtesnicht@test.de ein Konto gibt'),
        findsOneWidget);
    expect(backend.passwordResets, ['gibtesnicht@test.de']);
    expect(find.widgetWithText(TextField, 'Code aus der Mail'), findsOneWidget);
  });

  testWidgets('Falscher Code lässt niemanden in die App', (tester) async {
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testpilz@test.de');

    await tester.enterText(
        find.widgetWithText(TextField, 'Code aus der Mail'), '000000');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort'), 'NeuesPilz#2026!');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'NeuesPilz#2026!');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.textContaining('Code ist falsch oder abgelaufen'),
        findsOneWidget);
    expect(find.text('Neuer Spot'), findsNothing,
        reason: 'Ein falscher Code darf die Karte nicht öffnen.');
    expect(backend.currentUserId, isNull);
  });

  testWidgets('Zwei verschiedene Passwörter werden abgefangen',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testpilz@test.de');

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort'), 'NeuesPilz#2026!');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'Tippfehler#2026!');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.textContaining('stimmen nicht überein'), findsOneWidget);
    expect(backend.currentUserId, isNull,
        reason: 'Der Code wurde gar nicht erst eingelöst.');
  });

  testWidgets('Zu kurzes Passwort wird abgefangen', (tester) async {
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testpilz@test.de');

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort'), 'kurz');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'), 'kurz');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.textContaining('mindestens'), findsOneWidget);
    expect(backend.currentUserId, isNull);
  });

  testWidgets('Richtiger Code setzt das Passwort und führt in die App',
      (tester) async {
    final backend = FakeBackend()
      ..addUser(username: 'testpilz', password: 'AltesPilz#2026!');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testpilz@test.de');

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort'), 'NeuesPilz#2026!');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'NeuesPilz#2026!');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.text('Neuer Spot'), findsOneWidget,
        reason: 'Nach dem Ändern öffnet das userUpdated-Ereignis die App.');
    expect(backend.currentUserId, isNotNull);
    // Der Effekt, nicht nur der Aufruf: das Passwort ist wirklich neu.
    expect(backend.users.single.password, 'NeuesPilz#2026!');
  });

  testWidgets('Eine Recovery-Sitzung allein öffnet die App nicht',
      (tester) async {
    final backend = FakeBackend();
    final user = backend.addUser(username: 'testpilz');
    await pumpApp(tester, backend);

    // Genau der Zustand direkt nach dem Einlösen des Codes: gültige
    // Sitzung, aber das neue Passwort ist noch nicht gesetzt. Reagierte
    // der Router darauf, läge die Karte mitten im Reset offen — und die
    // Nutzerin wäre angemeldet, ohne ihr Passwort zu kennen. Ohne den
    // Filter in lib/core/router.dart wird dieser Test rot.
    backend.setCurrentUser(user, AuthChangeEvent.passwordRecovery);
    await settle(tester);

    expect(find.text('Neuer Spot'), findsNothing);
    expect(find.text('Anmelden'), findsOneWidget,
        reason: 'Erst das geänderte Passwort (userUpdated) darf hereinlassen.');
  });

  testWidgets('Zurück zur Anmeldung stellt das Passwortfeld wieder her',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);

    await _tap(tester, find.text('Passwort vergessen?'));
    await _tap(tester, find.text('Zurück zur Anmeldung'));

    expect(find.widgetWithText(TextField, 'Passwort'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Passwort vergessen?'), findsOneWidget);
  });
}
