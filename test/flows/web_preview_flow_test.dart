// Der Vorschau-Kanal der Web-App (#388).
//
// Zwei Hälften, und die zweite ist die wichtigere: Der Verweis im Profil
// führt HIN, der Streifen sorgt dafür, dass auch merkt, wer über ein
// Lesezeichen oder einen Link dort landet. Ohne ihn wäre die Vorschau von
// der echten App nicht zu unterscheiden — und jemand meldete Fehler aus
// Code, den es so nie gegeben hat.
//
// Beides hängt an `webChannelProvider` und nicht an `kIsWeb` bzw.
// `AppDistribution.isPreviewBuild`: Die sind `const` und im Test nicht
// umschaltbar. Ohne die Naht wäre hier gar nichts prüfbar — dieselbe
// Lehre wie bei `offlineMapsSupportedProvider`.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_distribution.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> openAbout(WidgetTester tester) async {
    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Über PilzBuddy'), 300);
    await settle(tester);
  }

  testWidgets('Auf Android gibt es weder Streifen noch Verweis',
      (tester) async {
    // Der Normalfall — und der Beleg, dass die bestehenden Suiten
    // unberührt bleiben: `WebChannel.none` ist die Vorgabe.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    expect(find.textContaining('Entwicklungsstand'), findsNothing);
    await openAbout(tester);
    expect(find.text('Entwicklungsversion öffnen'), findsNothing);
    expect(find.text('Zur freigegebenen Version'), findsNothing);
  });

  testWidgets('Die freigegebene Web-App bietet den Weg zur Vorschau an',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: [
      webChannelProvider.overrideWithValue(WebChannel.stable),
    ]);

    // Kein Streifen — das hier IST die echte App.
    expect(find.textContaining('Entwicklungsstand'), findsNothing);
    await openAbout(tester);
    expect(find.text('Entwicklungsversion öffnen'), findsOneWidget);
    // Der Hinweis auf die Neuanmeldung gehört dazu: Eigener Origin heißt
    // eigener Speicher, und ohne den Satz sieht das wie ein Fehler aus.
    expect(find.textContaining('neu'), findsWidgets);
    expect(find.textContaining('anmelden'), findsOneWidget);
  });

  testWidgets('Die Vorschau sagt, was sie ist — und zeigt den Rückweg',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: [
      webChannelProvider.overrideWithValue(WebChannel.preview),
    ]);

    // Der Streifen liegt über der ganzen App, nicht nur über der Karte.
    expect(find.text('Entwicklungsstand — nicht freigegeben'), findsOneWidget);

    await openAbout(tester);
    expect(find.text('Zur freigegebenen Version'), findsOneWidget);
    expect(find.text('Entwicklungsversion öffnen'), findsNothing,
        reason: 'in der Vorschau wäre das ein Verweis auf sich selbst');
  });
}
