// Startverhalten mit und ohne Empfang (#277, Muster aus MitFahrBar).
//
// **Push ist ein reiner ONLINE-Weg.** Genau deshalb steht dieser Test
// hier: Die App wird im Wald benutzt, und sie muss ohne Verbindung
// vollständig hochkommen — der Push-Pfad darf daran nichts ändern,
// weder beim Start noch beim Anfassen des Schalters.
//
// Der gefährliche Teil ist nicht der Fehler, sondern das Hängen: Der
// `PushListener` hängt sich beim ERSTEN Frame an einen Nachrichtenstrom,
// und `getToken` wartet im Funkloch, bis eine Frist zuschlägt. Beides
// passiert also in jeder Sitzung, auch in der, in der niemand
// Benachrichtigungen will.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/push_messaging.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  const offline = [ConnectivityResult.none];

  Future<Finder> pushToggle(WidgetTester tester) async {
    await tester.tap(find.text('Profil'));
    await settle(tester);
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

  testWidgets('mit Empfang kommt die App hoch', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: FakeSettings());

    expect(find.text('Karte'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ohne Empfang kommt die App genauso hoch', (tester) async {
    // Der Kaltstart im Wald. Nichts am Push-Pfad darf ihn aufhalten:
    // Der PushListener hängt sich beim ersten Frame ein, und das muss
    // ohne Netz genauso durchlaufen.
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend,
        settings: FakeSettings(), connectivity: offline);

    expect(find.text('Karte'), findsOneWidget,
        reason: 'ohne Verbindung muss die Karte trotzdem stehen');
    expect(find.text('Profil'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'ein Fehler aus dem Push-Pfad darf den Start nicht '
            'erreichen — er ist ein Nebenfeature');
  });

  testWidgets('ohne Empfang ist auch das Profil bedienbar', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend,
        settings: FakeSettings(), connectivity: offline);

    final toggle = await pushToggle(tester);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ohne Empfang nennt der Schalter die VERBINDUNG als Grund, '
      'nicht die Berechtigung', (tester) async {
    // Der Fehler, den dieser Test festhält: Bis hierher gab `getToken`
    // im Funkloch dasselbe nackte `null` zurück wie eine abgelehnte
    // Berechtigung — und die App schickte jemanden in die
    // Android-Einstellungen, wo alles längst richtig stand.
    final settings = FakeSettings();
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend,
        settings: settings,
        connectivity: offline,
        extraOverrides: [
          // Kein Token, aber NICHT abgelehnt — genau das liefert ein
          // `getToken`, das ins Leere läuft.
          pushTokenProvider
              .overrideWithValue(() async => (token: null, denied: false)),
        ]);

    final toggle = await pushToggle(tester);
    await tester.tap(toggle);
    await settle(tester);

    expect(find.textContaining('Verbindung'), findsOneWidget,
        reason: 'im Funkloch ist die Verbindung der Grund');
    expect(find.textContaining('nicht erlaubt'), findsNothing,
        reason: 'eine Berechtigungs-Erklärung wäre hier schlicht falsch');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(settings.pushToken, isNull,
        reason: 'ohne Token ist dieses Gerät nicht eingetragen');
  });

  testWidgets('MIT Empfang bleibt die Berechtigungs-Erklärung erhalten',
      (tester) async {
    // Gegenstück zum Test darüber: Wer wirklich ablehnt, soll auch
    // weiterhin den Weg in die Einstellungen genannt bekommen.
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: FakeSettings(), extraOverrides: [
      pushTokenProvider
          .overrideWithValue(() async => (token: null, denied: true)),
    ]);

    final toggle = await pushToggle(tester);
    await tester.tap(toggle);
    await settle(tester);

    expect(find.textContaining('nicht erlaubt'), findsOneWidget);
    expect(find.textContaining('Verbindung'), findsNothing);
  });
}
