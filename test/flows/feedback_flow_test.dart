// Das gelbe Melde-Banner auf der Karte: Feedback absenden und ausblenden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

const _bannerText = '💡 Wunsch, Fehler oder Pilzart melden!';

void main() {
  FakeBackend loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  testWidgets('Melde-Banner sendet eine Bug-Meldung ans Backend',
      (tester) async {
    final backend = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text(_bannerText));
    await settle(tester);
    expect(find.text('Wünsch dir was!'), findsOneWidget);
    // Transparenz-Hinweis: Feedback landet öffentlich auf GitHub.
    expect(find.textContaining('öffentlich im GitHub-Projekt'), findsOneWidget);

    await tester.tap(find.text('🐛 Bug'));
    await settle(tester, frames: 4);
    await tester.enterText(
        find.widgetWithText(TextField, 'Was ist passiert?'),
        'Beim Löschen eines Spots bleibt der Marker stehen');
    await tester.tap(find.text('Senden'));
    await settle(tester);

    expect(backend.feedback.single['type'], 'bug');
    expect(backend.feedback.single['message'],
        'Beim Löschen eines Spots bleibt der Marker stehen');
    // **Und aus welchem Stand sie kommt** (#358). `error_reports` trug
    // die Version seit Patch 009, die von Hand geschriebenen Meldungen
    // nicht — ausgerechnet dort, wo die Triage sie am dringendsten
    // braucht. Bei #358 war deshalb nicht entscheidbar, ob die Meldung
    // ein Duplikat einer schon behobenen war oder ein neuer Fehler im
    // frischen Stand; die Frage musste beim Melder zurückgestellt
    // werden. `pumpApp` setzt die Version auf 1.0.0.
    expect(backend.feedback.single['app_version'], '1.0.0');
    await drainSnackbars(tester);
  });

  testWidgets('Das Melde-Banner bleibt nach dem Absenden stehen',
      (tester) async {
    // Früher blendete jedes abgeschickte Feedback das Banner aus — das wirkte,
    // als wäre die Meldemöglichkeit verschwunden (Issue #72).
    final backend = loggedInBackend();
    await pumpApp(tester, backend);
    expect(find.text(_bannerText), findsOneWidget);

    await tester.tap(find.text(_bannerText));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Dein Wunsch'), 'Fotos zu Funden');
    await tester.tap(find.widgetWithText(FilledButton, 'Senden'));
    await settle(tester);

    expect(backend.feedback, hasLength(1));
    expect(find.text(_bannerText), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Der Pilzart-Wunsch sagt sofort, wenn es die Art schon gibt',
      (tester) async {
    // #395: Genau so ist es passiert — „Flaschen-Stäubling" getippt,
    // gesendet, und der Melder hat auf ein Update gewartet für eine Art,
    // die seit jeher in der Liste steht. Der Dialog fragte „Welche Pilzart
    // fehlt in der Auswahlliste?", ohne die Liste zu kennen.
    final backend = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text(_bannerText));
    await settle(tester);
    await tester.tap(find.text('🍄 Pilzart'));
    await settle(tester, frames: 4);

    expect(find.textContaining('gibt es schon'), findsNothing,
        reason: 'ohne Eingabe gibt es nichts zu sagen');

    await tester.enterText(
        find.widgetWithText(TextField, 'Name der Pilzart'),
        'Flaschen-Stäubling');
    await settle(tester, frames: 4);

    expect(find.textContaining('Die gibt es schon: „Flaschenstäubling"'),
        findsOneWidget);
  });

  testWidgets('Eine wirklich fehlende Art bekommt keinen Hinweis',
      (tester) async {
    // Die Gegenrichtung, und sie trägt die erste: Ein Hinweis, der immer
    // steht, sagt nichts mehr — und würde echte Wünsche entmutigen.
    final backend = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text(_bannerText));
    await settle(tester);
    await tester.tap(find.text('🍄 Pilzart'));
    await settle(tester, frames: 4);
    await tester.enterText(
        find.widgetWithText(TextField, 'Name der Pilzart'),
        'Blauer Wurzelrübling');
    await settle(tester, frames: 4);

    expect(find.textContaining('gibt es schon'), findsNothing);
    expect(find.textContaining('Schon in der Liste'), findsNothing);

    // Und sie lässt sich weiterhin senden.
    await tester.tap(find.text('Senden'));
    await settle(tester);
    expect(backend.feedback.single['type'], 'species');
    expect(backend.feedback.single['species_name'], 'Blauer Wurzelrübling');
  });

  testWidgets('Das X blendet das Melde-Banner aus', (tester) async {
    await pumpApp(tester, loggedInBackend());

    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.text(_bannerText),
        matching: find.byType(Row),
      ),
      matching: find.byIcon(Icons.close),
    ));
    await settle(tester);

    expect(find.text(_bannerText), findsNothing);
  });
}
