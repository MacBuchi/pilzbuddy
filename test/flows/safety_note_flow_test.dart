// Der Haftungshinweis (#110).
//
// Bei einer Pilz-App ist das nicht Kleingedrucktes: Die App merkt sich
// Orte, sie bestimmt nichts — und wer das verwechselt, isst am Ende
// etwas Falsches. Der Satz stand bisher nur im Play-Store-Text, also
// genau dort, wo ihn niemand liest, der die App schon hat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/safety_note.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  FakeBackend loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  testWidgets('Beim ersten Start steht er da — und lässt sich nicht '
      'wegwischen', (tester) async {
    final settings = FakeSettings(safetyNoteSeen: false);
    await pumpApp(tester, loggedInBackend(), settings: settings);

    expect(find.text('Kurz vorweg'), findsOneWidget);
    expect(find.textContaining('bestimmt keine Pilze'), findsOneWidget);

    // Danebentippen darf ihn nicht schließen: Ein Hinweis, den ein
    // Fehlgriff wegräumt, ist nicht gezeigt worden.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('Kurz vorweg'), findsOneWidget);

    await tester.tap(find.text('Verstanden'));
    await settle(tester);
    expect(find.text('Kurz vorweg'), findsNothing);
    expect(settings.safetyNoteSeen, isTrue, reason: 'einmal je Installation');
  });

  testWidgets('Beim zweiten Start nicht mehr', (tester) async {
    // Ein Hinweis, den man täglich wegklickt, wird zur Tapete.
    await pumpApp(tester, loggedInBackend(),
        settings: FakeSettings(safetyNoteSeen: true));
    expect(find.text('Kurz vorweg'), findsNothing);
  });

  testWidgets('Er verdrängt die geführte Tour, statt sich mit ihr zu '
      'überlagern', (tester) async {
    // Zwei Overlays gleichzeitig wären keins. Die Tour kommt beim
    // nächsten Start — sie ist eine Funktionserklärung, der Hinweis
    // die Voraussetzung.
    final settings = FakeSettings(safetyNoteSeen: false, mapTourSeen: false);
    await pumpApp(tester, loggedInBackend(), settings: settings);

    expect(find.text('Kurz vorweg'), findsOneWidget);
    expect(settings.mapTourSeen, isFalse,
        reason: 'die Tour ist nicht gelaufen und gilt nicht als gesehen');
  });

  testWidgets('Dauerhaft nachlesbar in der Kurzanleitung', (tester) async {
    await pumpApp(tester, loggedInBackend(),
        settings: FakeSettings(safetyNoteSeen: true));

    await tester.tap(find.text('Profil'));
    await settle(tester);
    // Das Profil ist lang; der Eintrag liegt unter der Kante.
    await tester.scrollUntilVisible(find.text('Kurzanleitung'), 200,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(find.text('Kurzanleitung'));
    await settle(tester);

    expect(find.byType(SafetyNoteTile), findsOneWidget);
    expect(find.textContaining('bestimmt keine Pilze'), findsOneWidget);
  });
}
