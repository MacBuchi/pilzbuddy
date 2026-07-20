// Konto-Löschung: Bestätigung, Kaskade und der Weg zurück zum Login.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _openProfileBottom(WidgetTester tester) async {
  await tester.tap(find.text('Profil'));
  await settle(tester);
  // Bis ans Listenende scrollen — `scrollUntilVisible` schiebt den Eintrag
  // nur knapp ins Bild, wo er die untere Navigationsleiste überlappt.
  for (var i = 0; i < 6; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await settle(tester, frames: 4);
  }
}

void main() {
  testWidgets('Löschen entfernt Konto und alle abhängigen Daten',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final freund = backend.addUser(username: 'lilli92');
    backend.signInAs(me.id);
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    backend.addFriendship(freund.id, me.id, status: 'accepted');
    await pumpApp(tester, backend);

    await _openProfileBottom(tester);
    await tester.tap(find.text('Konto löschen'));
    await settle(tester);
    expect(find.text('Konto endgültig löschen?'), findsOneWidget);

    // Solange der Benutzername nicht stimmt, bleibt der Knopf gesperrt.
    final deleteButton =
        find.widgetWithText(FilledButton, 'Endgültig löschen');
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);

    await tester.enterText(
        find.widgetWithText(TextField, 'Benutzername'), 'testpilz');
    await settle(tester, frames: 3);
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNotNull);

    await tester.tap(deleteButton);
    await settle(tester);

    // Kaskade wie im Schema: Nutzer, Spots und Freundschaften sind weg …
    expect(backend.users.any((u) => u.id == me.id), isFalse);
    expect(backend.spots, isEmpty);
    expect(backend.friendships, isEmpty);
    // … der Freund selbst bleibt natürlich bestehen.
    expect(backend.users.single.username, 'lilli92');
    // … und die App landet abgemeldet auf dem Login.
    expect(backend.currentUserId, isNull);
    expect(find.text('Anmelden'), findsOneWidget);
  });

  testWidgets('Falscher Benutzername löscht nichts', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(ownerId: me.id);
    await pumpApp(tester, backend);

    await _openProfileBottom(tester);
    await tester.tap(find.text('Konto löschen'));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Benutzername'), 'testpilzz');
    await settle(tester, frames: 3);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Endgültig löschen'))
            .onPressed,
        isNull);

    await tester.tap(find.text('Abbrechen'));
    await settle(tester);

    expect(backend.users, hasLength(1));
    expect(backend.spots, hasLength(1));
    expect(backend.currentUserId, me.id);
  });

  test('Die öffentliche Lösch-Seite liegt im Web-Verzeichnis', () {
    // Play verlangt eine Web-URL, die ohne installierte App erreichbar ist.
    // `flutter build web` kopiert web/ nach build/web — die Datei wird als
    // echte Datei vor dem SPA-Fallback (404.html) ausgeliefert.
    final page = File('web/konto-loeschen.html');
    expect(page.existsSync(), isTrue);

    final html = page.readAsStringSync();
    expect(html, contains('Konto löschen'));
    // Der Hinweis auf das öffentlich gebliebene Feedback ist der Punkt, der
    // sonst überrascht — er muss auf der Seite stehen.
    expect(html, contains('GitHub'));
  });
}
