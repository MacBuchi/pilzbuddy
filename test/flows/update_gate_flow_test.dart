// Sperre für zu alte Clients (Issue #80). Der Schwerpunkt liegt auf den
// Fällen, in denen NICHT gesperrt werden darf: die App wird im Wald ohne
// Empfang benutzt, und wer dort ausgesperrt wird, hat keine Karte mehr.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_info.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  testWidgets('Version unter der Mindestversion sperrt die App',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        appVersion: '1.24.0',
        appConfig:
            FakeAppConfigRepository(minimumSupportedVersion: '1.26.0'));

    expect(find.text('Update erforderlich'), findsOneWidget);
    expect(find.textContaining('Installiert: 1.24.0'), findsOneWidget);
    expect(find.textContaining('Benötigt ab: 1.26.0'), findsOneWidget);
    // Die App dahinter ist weg, nicht nur überdeckt.
    expect(find.text('Neuer Spot'), findsNothing);
    expect(find.text('Karte'), findsNothing);
  });

  testWidgets('Genau die Mindestversion läuft normal weiter', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        appVersion: '1.26.0',
        appConfig:
            FakeAppConfigRepository(minimumSupportedVersion: '1.26.0'));

    expect(find.text('Update erforderlich'), findsNothing);
    expect(find.text('Neuer Spot'), findsOneWidget);
  });

  testWidgets('Neuere Version als die Mindestversion läuft normal weiter',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        appVersion: '1.27.3',
        appConfig:
            FakeAppConfigRepository(minimumSupportedVersion: '1.26.0'));

    expect(find.text('Update erforderlich'), findsNothing);
    expect(find.text('Neuer Spot'), findsOneWidget);
  });

  // Der wichtigste Fall: ohne Empfang scheitert der Abruf, und die App muss
  // trotzdem starten — sonst nimmt die Sperre genau dort die Karte weg, wo
  // sie gebraucht wird.
  testWidgets('Fehlgeschlagener Abruf sperrt nicht', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        appVersion: '1.0.0',
        appConfig: FakeAppConfigRepository(fails: true));

    expect(find.text('Update erforderlich'), findsNothing);
    expect(find.text('Neuer Spot'), findsOneWidget);
  });

  testWidgets('Ohne Mindestversion in der Datenbank sperrt nichts',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, appVersion: '1.0.0');

    expect(find.text('Update erforderlich'), findsNothing);
    expect(find.text('Neuer Spot'), findsOneWidget);
  });

  testWidgets('Unbekannte eigene Version sperrt nicht', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        appVersion: AppInfo.unknownVersion,
        appConfig:
            FakeAppConfigRepository(minimumSupportedVersion: '1.26.0'));

    expect(find.text('Update erforderlich'), findsNothing);
    expect(find.text('Neuer Spot'), findsOneWidget);
  });

  testWidgets('Die Sperre greift auch vor der Anmeldung', (tester) async {
    final backend = FakeBackend();
    await pumpApp(tester, backend,
        appVersion: '1.24.0',
        appConfig:
            FakeAppConfigRepository(minimumSupportedVersion: '1.26.0'));

    expect(find.text('Update erforderlich'), findsOneWidget);
    expect(find.text('Anmelden'), findsNothing);
  });
}
