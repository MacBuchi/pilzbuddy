// Der Schutzgebiets-Hinweis beim Eintragen (#580) — durch die echte
// Oberfläche.
//
// Die teuren Fälle: ein Hinweis, der an der Stelle fehlt, an der er
// gilt (dann liest man „hier ist keins"); einer, der dem Spot folgt,
// aber nicht der Fundstelle; und einer, der das Speichern verhindert —
// der Betreiber wollte ausdrücklich keine Bevormundung.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/protected_area_providers.dart';
import 'package:pilzbuddy/features/map/protected_areas.dart';
import 'package:pilzbuddy/features/map/widgets/protected_area_note.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';
import '../protected_areas_test.dart' show protectedOf;

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Ein Schutzgebiet über der Kartenmitte der App (51,1634 / 10,4477)
  /// und dem Standardort der Test-Spots — 10 × 10 Waben zu ~1 km.
  final ProtectedAreas reserve = protectedOf(
    [
      for (var y = 0; y < 10; y++) [(0, 10, 1)],
    ],
    west: 10.40,
    north: 51.20,
    lonStep: 0.01,
    latStep: 0.01,
  );

  final withReserve = [
    protectedAreasLoaderProvider.overrideWithValue(() async => reserve),
  ];

  testWidgets('„Neuer Spot" im Schutzgebiet: ein Satz mit Namen — und '
      'speichern geht trotzdem', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withReserve);
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester, frames: 12);

    expect(find.byKey(kProtectedAreaNoteKey), findsOneWidget);
    expect(find.textContaining('Naturschutzgebiet „Wutachschlucht“'),
        findsOneWidget);
    expect(find.textContaining('meist verboten'), findsOneWidget);
    expect(find.textContaining('Beschilderung vor Ort'), findsOneWidget);

    // Keine Sperre: Art rein, Speichern, der Spot steht da.
    await tester.enterText(find.byType(TextField).at(1), 'Steinpilz');
    await settle(tester);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 12);
    expect(backend.spots, hasLength(1),
        reason: 'der Hinweis verhindert nichts (keine Bevormundung)');
  });

  testWidgets('außerhalb steht nichts — auch kein „kein Schutzgebiet"',
      (tester) async {
    // Schweigen heißt nicht „erlaubt": Die Daten decken nur DACH ab.
    // Deshalb gibt es keinen Satz für die Gegenrichtung.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: [
      protectedAreasLoaderProvider.overrideWithValue(() async => protectedOf(
            [
              for (var y = 0; y < 10; y++) [(0, 10, 1)],
            ],
            west: 12.0, // weit östlich der Kartenmitte
            north: 51.20,
            lonStep: 0.01,
            latStep: 0.01,
          )),
    ]);
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester, frames: 12);
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
    expect(find.byKey(kProtectedAreaNoteKey), findsNothing);
    expect(find.textContaining('Schutzgebiet'), findsNothing);
  });

  testWidgets('„Fund eintragen" an einem Spot im Schutzgebiet zeigt ihn auch',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id,
        name: 'Buchenhang',
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1));
    await pumpApp(tester, backend, extraOverrides: withReserve);
    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester, frames: 12);
    expect(find.byKey(kProtectedAreaNoteKey), findsOneWidget);
  });
}
