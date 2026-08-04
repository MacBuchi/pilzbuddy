// Benutzername ändern (Issue #194).
//
// Der Name ist eine suchbare Identität (Freundessuche per Präfix), und
// seit Patch 013 ist er auch über Groß-/Kleinschreibung hinweg einmalig.
// Der Fake spiegelt genau das; den echten Beweis führt der unique-Index
// in der Datenbank, den der Schema Check einspielt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Öffnet den Dialog aus dem Profil-Tab — Muster wie in
/// change_password_flow_test.dart: erst heranscrollen, dann tippen.
Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Profil'));
  await settle(tester);
  final tile = find.text('Benutzername ändern');
  for (var i = 0; i < 6 && tile.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester, frames: 4);
  }
  await tester.ensureVisible(tile);
  await settle(tester);
  await tester.tap(tile);
  await settle(tester);
}

Finder get _field => find.widgetWithText(TextField, 'Neuer Benutzername');
Finder get _saveButton => find.widgetWithText(FilledButton, 'Speichern');

void main() {
  testWidgets('Umbenennen greift wirklich — im Profilkopf und im Backend',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await tester.enterText(_field, 'steinpilzsucher');
    await settle(tester);
    await tester.tap(_saveButton);
    await settle(tester);

    // Der Effekt, nicht nur der Aufruf.
    expect(backend.users.single.username, 'steinpilzsucher');
    expect(find.widgetWithText(TextField, 'Neuer Benutzername'), findsNothing,
        reason: 'Nach dem Speichern schließt der Dialog.');
    // Zum Profilkopf zurückscrollen — die Liste baut nur, was im Bild
    // ist, und wir stehen noch bei den Kacheln weiter unten.
    for (var i = 0;
        i < 6 && find.text('steinpilzsucher').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await settle(tester, frames: 4);
    }
    expect(find.text('steinpilzsucher'), findsWidgets,
        reason: 'Der Profilkopf muss den neuen Namen sofort zeigen — '
            'Read-after-write, kein alter Zwischenstand.');
    await drainSnackbars(tester);
  });

  testWidgets('Der Knopf bleibt gesperrt für zu kurz und für unverändert',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    // Vorbefüllt mit dem aktuellen Namen: unverändert gibt es nichts zu
    // speichern.
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);

    await tester.enterText(_field, 'ab');
    await settle(tester);
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull,
        reason: 'Mindestlänge wie bei der Registrierung.');

    await tester.enterText(_field, 'abc');
    await settle(tester);
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);
  });

  testWidgets('Ein nur anders geschriebener Name ist vergeben', (tester) async {
    // „Marcus" gegen „marcus" — genau die Lücke, die Patch 013 schließt.
    // Ohne die case-insensitive Prüfung ginge dieser Test grün durch und
    // live stünden zwei für Suchende gleiche Konten in der Tabelle.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.addUser(username: 'Steinpilzsucher');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await tester.enterText(_field, 'steinpilzsucher');
    await settle(tester);
    await tester.tap(_saveButton);
    await settle(tester);

    expect(find.text('Dieser Benutzername ist schon vergeben.'),
        findsOneWidget);
    expect(backend.userById(me.id).username, 'testpilz',
        reason: 'Ein abgelehnter Wechsel darf nichts ändern.');
  });

  testWidgets('Abbrechen ändert nichts', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await tester.enterText(_field, 'anderername');
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
    await settle(tester);

    expect(backend.users.single.username, 'testpilz');
  });
}
