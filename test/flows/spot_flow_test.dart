// Szenarien rund um Spots: anlegen am Fadenkreuz, Arten-Vorschläge,
// Vorbelegung, Wiederbesuch (Fund eintragen), Freigabe-Ausschluss, Löschen.
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

  testWidgets('Eigene Spots erscheinen als Marker auf der Karte',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    await pumpApp(tester, backend);

    expect(find.byTooltip('Buchenhang'), findsOneWidget);
    expect(find.byType(MushroomIcon), findsOneWidget);
  });

  testWidgets(
      'Neuer Spot: Fadenkreuz → Vorschlag antippen → Speichern legt Spot samt Fund an',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget);

    // Tippen zeigt Vorschläge aus der eingebauten Artenliste …
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Steinpil');
    await settle(tester, frames: 4);
    // … Antippen übernimmt den Treffer ins Feld.
    await tester.tap(find.widgetWithText(ListTile, 'Steinpilz').first);
    await settle(tester, frames: 4);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    expect(backend.spots, hasLength(1));
    expect(backend.spots.single.finds.single.species, 'Steinpilz');
    // Gespeichert wird exakt an der Fadenkreuz-Position (Kartenmitte).
    expect(backend.spots.single.lat, closeTo(51.1634, 0.01));
    expect(find.text('Spot gespeichert 🍄'), findsOneWidget);
    expect(find.byType(MushroomIcon), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Zuletzt benutzte Art ist beim nächsten Spot vorbelegt',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id,
        species: 'Pfifferling',
        foundOn: DateTime(2026, 7, 1));
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Pfifferling'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Pfifferling'), findsOneWidget);
  });

  testWidgets('Wiederbesuch: Fund eintragen ist mit dem letzten Fund vorbelegt',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id,
        species: 'Maronenröhrling',
        count: 3,
        foundOn: DateTime(2026, 6, 15));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    expect(find.text('Dein Spot'), findsOneWidget);
    expect(find.text('Maronenröhrling, 3 Stück'), findsOneWidget);

    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);
    expect(find.widgetWithText(TextField, 'Maronenröhrling'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    expect(backend.spots.single.finds, hasLength(2));
    expect(backend.spots.single.finds.last.species, 'Maronenröhrling');
    // Das Detail-Sheet zeigt jetzt beide Funde.
    expect(find.text('Maronenröhrling, 3 Stück'), findsNWidgets(2));
  });

  testWidgets('Freigabe-Ausschluss lässt sich am Spot umschalten',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    await tester.tap(find.text('Von Freigabe ausschließen'));
    await settle(tester);

    expect(backend.spots.single.sharingExcluded, isTrue);
  });

  testWidgets('Spot löschen entfernt den Marker und die Daten',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Alter Spot');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Alter Spot'));
    await settle(tester);
    await tester.tap(find.byTooltip('Spot löschen'));
    await settle(tester);
    expect(find.text('Spot löschen?'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await settle(tester);

    expect(backend.spots, isEmpty);
    expect(find.byTooltip('Alter Spot'), findsNothing);
  });

  testWidgets('Profil zeigt Statistik und schaltet die Detail-Freigabe',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final spotA = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2025, 9, 1));
    backend.addFindRow(spotA,
        species: 'Steinpilz', foundOn: DateTime(2025, 10, 3));
    backend.addSpot(
        ownerId: me.id,
        lat: 51.5,
        species: 'Pfifferling',
        foundOn: DateTime(2025, 8, 2));
    await pumpApp(tester, backend);

    await tester.tap(find.text('Profil'));
    await settle(tester);

    expect(find.text('testpilz'), findsOneWidget);
    expect(find.text('Spots'), findsOneWidget);
    expect(find.text('Funde'), findsOneWidget);
    // 2 Spots, 3 Funde, 1 mehrfach besuchter Spot
    expect(find.text('2'), findsAtLeastNWidgets(1));
    expect(find.text('3'), findsAtLeastNWidgets(1));

    // Detail-Freigabe umschalten, solange der Schalter oben sichtbar ist.
    await tester.tap(find.text('Auch Art, Anzahl und Funddatum teilen'));
    await settle(tester);
    expect(me.shareDetails, isFalse);

    // Top-Arten liegt weiter unten im ListView — hinscrollen.
    await tester.scrollUntilVisible(find.text('Top-Arten'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Top-Arten'), findsOneWidget);

    // Ganz unten: die „Über"-Sektion mit Version und Links.
    await tester.scrollUntilVisible(find.text('Über PilzBuddy'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('GitHub-Projekt & Dokumentation'), findsOneWidget);
    expect(find.text('Web-App'), findsOneWidget);
  });
}
