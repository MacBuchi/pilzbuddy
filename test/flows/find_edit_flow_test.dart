// Einen einzelnen Eintrag korrigieren oder löschen (#240) — bis dahin
// ging beides nur, indem man den ganzen Spot samt Historie löschte.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/errors.dart';
import 'package:pilzbuddy/core/widgets/mushroom_avatar.dart';
import 'package:pilzbuddy/data/spot_repository.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Spot-Blatt öffnen und den ersten Eintrag antippen.
  Future<void> openEntry(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, label));
    await settle(tester);
  }

  testWidgets('Art korrigieren: der Bestand ist vorbelegt und wird ersetzt',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id,
        species: 'Maronenröhrling',
        count: 3,
        foundOn: DateTime(2026, 6, 15));
    await pumpApp(tester, backend);

    await openEntry(tester, 'Maronenröhrling, 3 Stück');
    expect(find.text('Fund bearbeiten'), findsOneWidget);
    // Vorbelegt mit dem, was dasteht — sonst wäre jede Korrektur ein
    // Neuschreiben aller Felder.
    expect(find.widgetWithText(TextField, 'Maronenröhrling'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    // Auf dem Datumsknopf des Blatts — das Datum steht auch in der
    // Fundliste dahinter, die weiter eingehängt ist.
    expect(find.widgetWithText(OutlinedButton, '15.6.2026'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Maronenröhrling'), 'Steinpilz');
    await settle(tester, frames: 4);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final entry = backend.spots.single.finds.single;
    expect(entry.species, 'Steinpilz');
    expect(entry.count, 3, reason: 'was nicht angefasst wurde, bleibt');
    expect(entry.foundOn, DateTime(2026, 6, 15));
    expect(backend.spots.single.finds, hasLength(1),
        reason: 'korrigieren legt keinen zweiten Eintrag an');
    expect(find.text('Steinpilz, 3 Stück'), findsOneWidget);
  });

  testWidgets('Ein Zweitname wird auch beim Korrigieren zur Hauptbezeichnung',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 6, 15));
    await pumpApp(tester, backend);

    await openEntry(tester, 'Steinpilz');
    await tester.enterText(
        find.widgetWithText(TextField, 'Steinpilz'), 'Totentrompete');
    await settle(tester, frames: 4);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    expect(backend.spots.single.finds.single.species, 'Herbsttrompete',
        reason: 'sonst lägen über den Korrekturweg zwei Namen für eine Art '
            'nebeneinander');
  });

  testWidgets('Löschen fragt nach — und nimmt nur den einen Eintrag',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 6, 15));
    backend.addFindRow(spotId,
        species: 'Pfifferling', foundOn: DateTime(2026, 7, 1));
    await pumpApp(tester, backend);

    await openEntry(tester, 'Pfifferling');
    await tester.ensureVisible(find.text('Fund löschen'));
    await tester.tap(find.text('Fund löschen'));
    await settle(tester);

    // Erst abbrechen: Ein Fund ist unwiederbringlich weg.
    expect(find.text('Fund löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(backend.spots.single.finds, hasLength(2));

    await tester.tap(find.text('Fund löschen'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await settle(tester);

    expect(backend.spots.single.finds.map((f) => f.species), ['Steinpilz']);
    expect(backend.spots, hasLength(1), reason: 'der Spot selbst bleibt');
    expect(find.text('Pfifferling'), findsNothing);
  });

  testWidgets('Ein Leergang hat kein Artfeld und bleibt einer',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 6, 15));
    backend.addFindRow(spotId, foundOn: DateTime(2026, 7, 1), blank: true);
    await pumpApp(tester, backend);

    await openEntry(tester, 'Nichts gefunden');
    expect(find.text('Leergang bearbeiten'), findsOneWidget);
    // `finds_blank_leer` verbietet Art und Anzahl — was die Datenbank
    // ablehnt, darf das Blatt gar nicht erst anbieten.
    expect(find.widgetWithText(TextField, 'Pilzart'), findsNothing);
    expect(find.text('Anzahl'), findsNothing);

    await tester.enterText(
        find.widgetWithText(TextField, 'Notiz (optional)'), 'alles abgesucht');
    await settle(tester, frames: 4);
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final entry = backend.spots.single.finds.last;
    expect(entry.blank, isTrue);
    expect(entry.species, isNull);
    expect(entry.count, isNull);
    expect(entry.note, 'alles abgesucht');
  });

  testWidgets('Ein fremder Fund lässt sich nicht anfassen', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final lilli = backend.addUser(username: 'lilli');
    backend.signInAs(me.id);
    backend.addFriendship(me.id, lilli.id);
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 6, 15));
    backend.addFindRow(spotId,
        species: 'Parasol',
        foundOn: DateTime(2026, 7, 1),
        authorId: lilli.id);
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    // Der Fund des Buddys zeigt seinen Eintrager, keinen Stift …
    final buddyTile = find.widgetWithText(ListTile, 'Parasol');
    expect(
        find.descendant(of: buddyTile, matching: find.byType(MushroomAvatar)),
        findsOneWidget);
    expect(
        find.descendant(
            of: buddyTile, matching: find.byIcon(Icons.edit_outlined)),
        findsNothing);

    // … und tippen tut nichts: `finds_author_all` erlaubt dort nichts.
    await tester.tap(buddyTile);
    await settle(tester);
    expect(find.text('Fund bearbeiten'), findsNothing);
  });

  test('Endet die Freigabe, bleibt Löschen — Ändern nicht', () async {
    // Die Asymmetrie steckt in `finds_author_all`: Das `using` fragt nur
    // nach dem Autor, der `with check` zusätzlich nach einem sichtbaren
    // Spot. Wer seine Daten zurückziehen will, kann das also immer;
    // ändern kann er sie nur, solange er den Spot noch sieht.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final lilli = backend.addUser(username: 'lilli');
    backend.signInAs(me.id);
    backend.addFriendship(me.id, lilli.id);
    final spotId = backend.addSpot(
        ownerId: lilli.id, species: 'Steinpilz', foundOn: DateTime(2026, 6, 1));
    backend.addFindRow(spotId,
        species: 'Pfifferling',
        foundOn: DateTime(2026, 7, 1),
        authorId: me.id);
    final repo = FakeSpotRepository(backend);
    final myFind = backend.spots.single.finds.last;

    backend.friendships.clear();
    expect(
        () => repo.updateFind(
            findId: myFind.id,
            find: NewFind(species: 'Marone', foundOn: DateTime(2026, 7, 1))),
        throwsA(isA<WriteRejectedException>()));
    await repo.deleteFind(myFind.id);
    expect(backend.spots.single.finds.map((f) => f.species), ['Steinpilz']);
  });

  test('Ein fremder Eintrag ist auch am eigenen Spot tabu', () async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final lilli = backend.addUser(username: 'lilli');
    backend.signInAs(me.id);
    backend.addFriendship(me.id, lilli.id);
    final spotId = backend.addSpot(ownerId: me.id);
    backend.addFindRow(spotId,
        species: 'Parasol',
        foundOn: DateTime(2026, 7, 1),
        authorId: lilli.id);
    final repo = FakeSpotRepository(backend);
    final buddyFind = backend.spots.single.finds.single;

    expect(
        () => repo.updateFind(
            findId: buddyFind.id,
            find: NewFind(species: 'Marone', foundOn: DateTime(2026, 7, 1))),
        throwsA(isA<WriteRejectedException>()));
    expect(() => repo.deleteFind(buddyFind.id),
        throwsA(isA<WriteRejectedException>()));
    expect(backend.spots.single.finds, hasLength(1));
  });
}
