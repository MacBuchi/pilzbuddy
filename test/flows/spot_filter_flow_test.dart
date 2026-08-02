// Filtern auf der Karte (#154): Knopf → Blatt → Auswahl → weniger Marker.
// Die Regeln selbst stehen in `spot_filter_test.dart`; hier geht es darum,
// dass ein aktiver Filter sichtbar ist und sich wieder aufheben lässt —
// ein unbemerkt versteckter Spot ist der eigentliche Schaden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  /// Ich mit zwei Spots (Marone, Pfifferling), eine Freundin mit einem.
  (FakeBackend, FakeUser) backendWithSpots() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final lilli = backend.addUser(username: 'lilli');
    backend.signInAs(me.id);
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(
        ownerId: me.id, species: 'Marone', foundOn: DateTime(2026, 7, 1));
    backend.addSpot(
        ownerId: me.id, species: 'Pfifferling', foundOn: DateTime(2026, 7, 2));
    backend.addSpot(
        ownerId: lilli.id,
        lat: 51.1644,
        species: 'Marone',
        foundOn: DateTime(2026, 7, 3));
    return (backend, me);
  }

  testWidgets('Nach Art filtern lässt nur die passenden Marker stehen',
      (tester) async {
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);

    expect(find.byType(MushroomIcon), findsNWidgets(3));

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);

    // Das Blatt zählt Fundstellen je Art — zwei Maronen (meine und Lillis).
    expect(find.text('2 Fundstellen'), findsOneWidget);
    expect(find.text('1 Fundstelle'), findsOneWidget);

    await tester.tap(find.text('Marone'));
    await settle(tester);
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    // Meine Marone und Lillis — der Pfifferling ist weg.
    expect(find.byType(MushroomIcon), findsNWidgets(2));
  });

  testWidgets('Ein aktiver Filter ist auf der Karte zu sehen und aufhebbar',
      (tester) async {
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);
    await tester.tap(find.text('Pfifferling'));
    await settle(tester);
    // Das Blatt schließen (Auswahl wirkt sofort, ohne „Übernehmen").
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    // Nur noch der Pfifferling-Spot.
    expect(find.byType(MushroomIcon), findsOneWidget);
    // …und die Karte sagt, warum.
    expect(find.textContaining('Gefiltert: nur Pfifferling'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter aufheben'));
    await settle(tester);
    expect(find.byType(MushroomIcon), findsNWidgets(3));
    expect(find.textContaining('Gefiltert'), findsNothing);
  });

  testWidgets('„Nur meine Spots" blendet die der Freundin aus',
      (tester) async {
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);
    await tester.tap(find.text('Nur meine Spots'));
    await settle(tester);
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    expect(find.byType(MushroomIcon), findsNWidgets(2));
    expect(find.textContaining('Gefiltert: nur meine'), findsOneWidget);
  });

  testWidgets('Ohne Filter gibt es keine Hinweiszeile', (tester) async {
    // Die Zeile kostet Platz über der Karte — sie erscheint nur, wenn sie
    // etwas zu sagen hat.
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);

    expect(find.textContaining('Gefiltert'), findsNothing);
    expect(find.byTooltip('Filter aufheben'), findsNothing);
  });
}
