// Szenario: Punkte importieren — je Punkt einen Spot anlegen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/import_export/import_screen.dart';
import 'package:pilzbuddy/features/import_export/waypoint_parser.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('Importierte Punkte werden einzeln als Spots angelegt',
      (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    addTearDown(backend.dispose);

    final waypoints = [
      ImportedWaypoint(
          name: 'Edelreizker Spechbach',
          lat: 51.2,
          lng: 10.4,
          time: DateTime(2024, 10, 27, 16, 25)),
      const ImportedWaypoint(lat: 51.3, lng: 10.5),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: overridesFor(backend),
      child: MaterialApp(
        home: ImportScreen(initialWaypoints: waypoints),
      ),
    ));
    await settle(tester);

    expect(find.textContaining('2 Punkte gefunden'), findsOneWidget);
    expect(find.text('Edelreizker Spechbach'), findsOneWidget);
    expect(find.text('Punkt 2'), findsOneWidget);

    // Ersten Punkt anlegen — Name, erkannte Art und Funddatum aus dem
    // GPX sind schon vorbefüllt.
    await tester.tap(find.text('Anlegen').first);
    await settle(tester);
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Edelreizker Spechbach'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Edelreizker'), findsOneWidget);
    expect(find.text('27.10.2024'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'), warnIfMissed: false);
    await settle(tester);

    expect(backend.spots, hasLength(1));
    expect(backend.spots.single.lat, closeTo(51.2, 1e-9));
    expect(backend.spots.single.name, 'Edelreizker Spechbach');
    expect(backend.spots.single.finds.single.species, 'Edelreizker');
    expect(backend.spots.single.finds.single.foundOn,
        DateTime(2024, 10, 27, 16, 25));
    expect(find.text('Angelegt'), findsOneWidget);
    // Der zweite Punkt wartet noch.
    expect(find.text('Anlegen'), findsOneWidget);
  });
}
