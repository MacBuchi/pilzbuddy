// Szenarien rund um Anmeldung, Registrierung und Abmeldung —
// komplette App gegen das In-Memory-Backend (siehe test/fakes/).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('Ausgeloggt startet die App auf dem Login-Screen',
      (tester) async {
    final backend = FakeBackend();
    await pumpApp(tester, backend);

    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'E-Mail'), findsOneWidget);
    expect(find.text('Neuer Spot'), findsNothing);
  });

  testWidgets('Falsches Passwort zeigt eine verständliche Fehlermeldung',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);

    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'testpilz@test.de');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort'), 'falsches-passwort');
    await tester.tap(find.text('Anmelden'));
    await settle(tester);

    expect(find.text('E-Mail oder Passwort falsch.'), findsOneWidget);
    expect(find.text('Neuer Spot'), findsNothing);
    await drainSnackbars(tester);
  });

  testWidgets('Login mit richtigen Daten führt zur Karte', (tester) async {
    final backend = FakeBackend()
      ..addUser(username: 'testpilz', password: 'PilzTest#2026!');
    await pumpApp(tester, backend);

    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'testpilz@test.de');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort'), 'PilzTest#2026!');
    await tester.tap(find.text('Anmelden'));
    await settle(tester);

    expect(find.text('Neuer Spot'), findsOneWidget);
    expect(backend.currentUserId, isNotNull);
  });

  testWidgets('Registrierung meldet direkt an und landet auf der Karte',
      (tester) async {
    final backend = FakeBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await settle(tester);
    expect(find.text('Konto erstellen'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Benutzername'), 'neuerpilz');
    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'neu@test.de');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort (mind. 6 Zeichen)'),
        'geheim123');
    await tester.tap(find.text('Konto erstellen'));
    await settle(tester);

    expect(find.text('Neuer Spot'), findsOneWidget);
    expect(backend.users.single.username, 'neuerpilz');
    expect(backend.currentUserId, backend.users.single.id);
  });

  testWidgets('Vergebener Benutzername wird beim Registrieren abgefangen',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);

    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Benutzername'), 'testpilz');
    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'zweit@test.de');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort (mind. 6 Zeichen)'),
        'geheim123');
    await tester.tap(find.text('Konto erstellen'));
    await settle(tester);

    expect(find.text('Dieser Benutzername ist schon vergeben.'), findsOneWidget);
    expect(backend.users, hasLength(1));
    await drainSnackbars(tester);
  });

  testWidgets('Login- und Registrier-Felder hängen in einer AutofillGroup',
      (tester) async {
    // Ohne AutofillGroup meldet Flutter die Felder nicht beim Autofill-Dienst
    // an — Passwortmanager sehen das Formular dann gar nicht (Issue #68).
    void expectInAutofillGroup(String label) {
      expect(
        find.ancestor(
          of: find.widgetWithText(TextField, label),
          matching: find.byType(AutofillGroup),
        ),
        findsOneWidget,
        reason: 'Feld „$label" braucht eine AutofillGroup',
      );
    }

    final backend = FakeBackend();
    await pumpApp(tester, backend);

    expectInAutofillGroup('E-Mail');
    expectInAutofillGroup('Passwort');

    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await settle(tester);

    expectInAutofillGroup('Benutzername');
    expectInAutofillGroup('E-Mail');
    expectInAutofillGroup('Passwort (mind. 6 Zeichen)');
  });

  testWidgets('Abmelden führt zurück zum Login-Screen', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    expect(find.text('Neuer Spot'), findsOneWidget);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.byTooltip('Abmelden'));
    await settle(tester);

    expect(find.text('Anmelden'), findsOneWidget);
    expect(backend.currentUserId, isNull);
  });
}
