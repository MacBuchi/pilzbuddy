// „Passwort vergessen" — vom Anfordern des Codes bis zum neuen Passwort,
// komplette App gegen das In-Memory-Backend (siehe test/fakes/).
//
// Der Reset läuft absichtlich über den Zahlencode aus der Mail und nicht
// über deren Link: Der Link ist an das Gerät gebunden, das ihn angefordert
// hat (PKCE-Verifier im lokalen Speicher), und stirbt daher, wenn die Mail
// woanders geöffnet wird. Siehe AuthRepository.sendPasswordResetCode.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/errors.dart';
import 'package:pilzbuddy/core/widgets/form_notice.dart';
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
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'NeuesPilz#2026!');
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
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'NeuesPilz#2026!');
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
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'kurz');
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
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'NeuesPilz#2026!');
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

  testWidgets('Ein bekannt unsicheres Passwort wird abgelehnt',
      (tester) async {
    // Leaked Password Protection ist im Dashboard aktiv — „zu kurz" wäre
    // hier die falsche Erklärung, das Passwort ist lang genug.
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testpilz@test.de');

    await tester.enterText(find.widgetWithText(TextField, 'Code aus der Mail'),
        FakeBackend.resetCode);
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
        'passwort123');
    await tester.enterText(
        find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
        'passwort123');
    await _tap(tester, find.text('Neues Passwort speichern'));

    expect(find.textContaining('zu unsicher'), findsOneWidget);
    expect(find.text('Neuer Spot'), findsNothing);
  });

  testWidgets('Der Code lässt sich erneut anfordern', (tester) async {
    // Ohne diesen Knopf ist eine im Spam gelandete Mail eine Sackgasse:
    // Die Registrierung hat ihn seit 1.31.0, der Reset fehlte.
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testpilz@test.de');

    // Gerade ist eine Mail rausgegangen — erst läuft die Wartezeit.
    expect(find.textContaining('Erneut senden in'), findsOneWidget);
    await passResendCooldown(tester);

    await _tap(tester, find.text('Code nicht angekommen? Erneut senden'));

    expect(backend.passwordResets, ['testpilz@test.de', 'testpilz@test.de']);
    expect(find.textContaining('ein neuer Code'), findsOneWidget);
  });

  testWidgets('Auch das erneute Anfordern verrät kein Konto', (tester) async {
    // Dieselbe Meldung wie bei einer bekannten Adresse — sonst wäre der
    // zweite Tap das Orakel, das der erste vermeidet.
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'gibtesnicht@test.de');
    await passResendCooldown(tester);

    await _tap(tester, find.text('Code nicht angekommen? Erneut senden'));

    expect(find.textContaining('Wenn es zu gibtesnicht@test.de ein Konto gibt'),
        findsOneWidget);
    expect(backend.passwordResets.length, 2);
  });

  testWidgets('Ohne Adresse behauptet das Erneut-Senden keine Mail',
      (tester) async {
    // Der Fall aus dem Wochendigest KW34, gesehen in 1.98.0 und 1.99.0:
    // Das E-Mail-Feld steht auch im Code-Modus da und lässt sich leeren.
    // Die Prüfung gab es nur im ersten Weg — der zweite fragte trotzdem
    // an, GoTrue antwortete „Password recovery requires an email" (400),
    // und die App meldete unbeirrt „ein neuer Code ist unterwegs".
    final backend = FakeBackend()..addUser(username: 'testpilz');
    await pumpApp(tester, backend);
    await _requestCode(tester, 'testpilz@test.de');
    await passResendCooldown(tester);

    await tester.enterText(find.widgetWithText(TextField, 'E-Mail'), '');
    await _tap(tester, find.text('Code nicht angekommen? Erneut senden'));

    expect(find.textContaining('gültige E-Mail-Adresse'), findsOneWidget);
    expect(find.textContaining('ein neuer Code'), findsNothing);
    expect(tester.widget<FormNotice>(find.byType(FormNotice)).tone,
        NoticeTone.error);
    expect(backend.passwordResets, ['testpilz@test.de'],
        reason: 'Es darf keine zweite Anfrage rausgegangen sein.');
  });

  testWidgets('Ein abgelehnter Mailversand landet nicht im Fehlerbericht',
      (tester) async {
    // 23 der 31 Berichte in KW34 waren genau das: Googles Prüf-Robots
    // klicken den Login-Screen durch, und GoTrue lehnt ab, sobald das
    // Mail-Limit greift (bewusst 3/h, Brevo liefert 300/Tag portfolioweit).
    // Ein normaler Vorgang, der den Wochendigest anführt, verstopft ihn
    // für die echten Funde — dieselbe Lehre wie #124 und #136.
    final reported = <String>[];
    setErrorSink((context, _, _) => reported.add(context));
    addTearDown(() => setErrorSink(null));

    final backend = FakeBackend()
      ..addUser(username: 'testpilz')
      ..passwordResetMailLimit = 0;
    await pumpApp(tester, backend);

    await _requestCode(tester, 'testpilz@test.de');

    expect(reported, isEmpty);
    // Nach außen bleibt es bei der einen Auskunft: Eine sichtbare
    // Ablehnung wäre wieder ein Konto-Orakel.
    expect(find.textContaining('Wenn es zu testpilz@test.de ein Konto gibt'),
        findsOneWidget);
  });

  group('Transparenz im Formular (Issue #131)', () {
    testWidgets('Das Auge macht das Passwort sichtbar', (tester) async {
      final backend = FakeBackend()..addUser(username: 'testpilz');
      await pumpApp(tester, backend);

      final field = find.widgetWithText(TextField, 'Passwort');
      expect(tester.widget<TextField>(field).obscureText, isTrue);

      await _tap(
          tester,
          find.descendant(
              of: field, matching: find.byIcon(Icons.visibility_outlined)));

      expect(tester.widget<TextField>(field).obscureText, isFalse,
          reason: 'Wer sein Passwort nicht sehen kann, tippt es blind falsch.');
    });

    testWidgets('Die Übereinstimmung wird schon beim Tippen angezeigt',
        (tester) async {
      final backend = FakeBackend()..addUser(username: 'testpilz');
      await pumpApp(tester, backend);
      await _requestCode(tester, 'testpilz@test.de');

      // Solange nichts wiederholt wurde, ist Schweigen richtig.
      expect(find.textContaining('stimmen'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
          'NeuesPilz#2026!');
      await tester.enterText(
          find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
          'NeuesPilz#202');
      await settle(tester);
      expect(find.text('Passwörter stimmen noch nicht überein'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
          'NeuesPilz#2026!');
      await settle(tester);

      expect(find.text('Passwörter stimmen überein'), findsOneWidget,
          reason: 'Ohne Live-Abgleich merkt man den Tippfehler erst beim '
              'Absenden (Issue #131).');
    });
  });
}
