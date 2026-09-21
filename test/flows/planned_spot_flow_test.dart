// Vormerkung (#499): ein Spot ohne Fund, mit erwarteten Arten — anlegen,
// sehen, bearbeiten, und der erste Fund beendet sie.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
  }

  /// „Neuer Spot" → Schalter an → Art → Speichern.
  Future<void> createPlanned(WidgetTester tester, {String? species}) async {
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await tester.ensureVisible(find.text('Nur vormerken, noch kein Fund'));
    await tester.tap(find.text('Nur vormerken, noch kein Fund'));
    await settle(tester);
    if (species != null) {
      await tester.enterText(
          find.widgetWithText(TextField, 'Pilzart (optional)'), species);
      await settle(tester, frames: 4);
    }
    await save(tester);
    await drainSnackbars(tester);
  }

  bool markerPlanned(WidgetTester tester, String tooltip) => tester
      .widget<MushroomIcon>(find.descendant(
          of: find.byTooltip(tooltip), matching: find.byType(MushroomIcon)))
      .planned;

  testWidgets('„Nur vormerken" legt keinen Fund an — die Art wird Erwartung',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await createPlanned(tester, species: 'Steinpilz');

    final row = backend.spots.single;
    expect(row.finds, isEmpty, reason: 'kein Fund, auch kein artloser');
    expect(row.expectedSpecies, ['Steinpilz']);

    // Auf der Karte verblasst — und ohne Uhr. Der Tooltip bleibt der
    // Name: Das Blatt erklärt die Vormerkung, ein Tooltip erklärt nichts.
    expect(markerPlanned(tester, 'Pilz-Spot'), isTrue);
    expect(find.byIcon(Icons.schedule), findsNothing);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    expect(find.text('Vorgemerkt für Steinpilz — noch kein Fund.'),
        findsOneWidget);
    expect(find.text('Noch keine Funde eingetragen.'), findsOneWidget);
  });

  testWidgets('ohne den Schalter bleibt alles beim Alten: ein Fund entsteht',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await save(tester);
    await drainSnackbars(tester);

    final row = backend.spots.single;
    expect(row.finds, hasLength(1));
    expect(row.expectedSpecies, isEmpty);
    expect(markerPlanned(tester, 'Pilz-Spot'), isFalse);
  });

  testWidgets('der erste Fund beendet die Vormerkung — die Art ist vorbelegt',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await createPlanned(tester, species: 'Steinpilz');

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);
    // Die erwartete Art steht schon im Feld.
    expect(find.widgetWithText(TextField, 'Pilzart (optional)'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'Pilzart (optional)'))
            .controller
            ?.text,
        'Steinpilz');
    await save(tester);
    await drainSnackbars(tester);

    final row = backend.spots.single;
    expect(row.finds, hasLength(1));
    expect(row.finds.single.species, 'Steinpilz');
    expect(find.textContaining('Vorgemerkt für'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(markerPlanned(tester, 'Pilz-Spot'), isFalse);
  });

  testWidgets('die Erwartung lässt sich im Bearbeiten-Blatt ändern',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final id = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
    backend.spots.single.expectedSpecies = ['Steinpilz'];
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byTooltip('Spot bearbeiten'));
    await settle(tester);
    expect(find.text('Vorgemerkt für'), findsOneWidget);
    expect(find.byType(InputChip), findsOneWidget);

    // Chip weg, Pfifferling dazu.
    tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Pfifferling');
    await settle(tester, frames: 4);
    await save(tester);
    await drainSnackbars(tester);

    expect(backend.spots.single.expectedSpecies, ['Pfifferling']);
    expect(backend.spots.single.id, id);
  });

  testWidgets('ein Spot mit Funden bietet keine Erwartung an', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5,
        species: 'Steinpilz');
    await pumpApp(tester, backend);
    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byTooltip('Spot bearbeiten'));
    await settle(tester);
    expect(find.text('Vorgemerkt für'), findsNothing);
  });
}
