// Szenarien rund ums Teilen: Sichtbarkeit von Freundes-Spots je nach
// Freigabe-Einstellungen und Freundschaftsanfragen.
// (Das Melde-Banner liegt in feedback_flow_test.dart.)
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

  testWidgets('Geteilter Freundes-Spot zeigt Finder und Fund-Details',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(
        ownerId: lilli.id,
        species: 'Steinpilz',
        count: 2,
        foundOn: DateTime(2026, 7, 10));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot (lilli92)'));
    await settle(tester);

    expect(find.text('Gefunden von lilli92'), findsOneWidget);
    expect(find.text('Steinpilz, 2 Stück'), findsOneWidget);
    // Eintragen darf man am geteilten Spot seit #190 — löschen und die
    // Freigabe schalten weiterhin nur der Besitzer.
    expect(find.text('Fund eintragen'), findsOneWidget);
    expect(find.byTooltip('Spot löschen'), findsNothing);
  });

  testWidgets('Freund trägt am geteilten Spot einen eigenen Fund ein',
      (tester) async {
    // Der Kern von #190: Sichtbarkeit des Spots impliziert das
    // Schreibrecht — der Fund gehört aber dem Eintrager, nicht dem
    // Spot-Besitzer.
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(
        ownerId: lilli.id,
        species: 'Steinpilz',
        count: 2,
        foundOn: DateTime(2026, 7, 10));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot (lilli92)'));
    await settle(tester);

    // Besitzer-Rechte bleiben beim Besitzer.
    expect(find.text('Von Freigabe ausschließen'), findsNothing);
    expect(find.byTooltip('Spot löschen'), findsNothing);

    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Pfifferling');
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final saved = backend.spots.single.finds.last;
    expect(saved.authorId, me.id,
        reason: 'der Fund gehört dem Eintrager, nicht dem Spot-Besitzer');
    // Das Blatt zeigt beide Funde — lillis mit Zuschreibung in der
    // Fundzeile (exakter Text, denn „Gefunden von lilli92" steht auch im
    // Kopf), meiner ohne. Die Aktualisierung beweist nebenbei die
    // friendSpots-Invalidierung.
    expect(find.text('Pfifferling'), findsOneWidget);
    expect(find.text('Steinpilz, 2 Stück'), findsOneWidget);
    expect(find.text('10.7.2026 – von lilli92'), findsOneWidget);
  });

  testWidgets(
      'Vorbelegung am Freundes-Spot nimmt den letzten EIGENEN Fund',
      (tester) async {
    // Lillis Fund ist neuer — trotzdem darf nicht IHR Steinpilz im
    // Formular stehen, sondern mein älterer Pfifferling.
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    final spotId = backend.addSpot(
        ownerId: lilli.id,
        species: 'Steinpilz',
        count: 2,
        foundOn: DateTime(2026, 7, 20));
    backend.addFindRow(spotId,
        species: 'Pfifferling',
        count: 4,
        foundOn: DateTime(2026, 6, 1),
        authorId: me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot (lilli92)'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Pfifferling'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Steinpilz'), findsNothing);
  });

  testWidgets(
      'Buddy-Fund am eigenen Spot: Zuschreibung im Blatt, Statistik '
      'zählt nur eigene Funde', (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    final spotId = backend.addSpot(
        ownerId: me.id,
        species: 'Steinpilz',
        count: 1,
        foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        species: 'Parasol',
        count: 2,
        foundOn: DateTime(2026, 7, 5),
        authorId: lilli.id);
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    expect(find.textContaining('von lilli92'), findsOneWidget,
        reason: 'fremde Funde tragen ihren Eintrager');

    // Blatt schließen, dann die Statistik: Lillis Parasol ist ihr Fund,
    // nicht meiner — er gehört nicht in meine Top-Arten.
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Top-Arten'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Parasol'), findsNothing,
        reason: 'fremde Funde zählen nicht zu meinen Top-Arten');
  });

  testWidgets('Ohne Detail-Freigabe sehen Freunde nur den Standort',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92', shareDetails: false);
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(
        ownerId: lilli.id,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 7, 10));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot (lilli92)'));
    await settle(tester);

    expect(find.text('Nur der Standort wurde geteilt.'), findsOneWidget);
    expect(find.text('Steinpilz'), findsNothing);
  });

  testWidgets(
      'Ausgeschlossene, global ungeteilte und fremde Spots bleiben unsichtbar',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    final geizhals = backend.addUser(username: 'geizhals',
        shareSpotsDefault: false);
    final fremder = backend.addUser(username: 'fremder');
    backend.addFriendship(lilli.id, me.id);
    backend.addFriendship(geizhals.id, me.id);
    // Einzeln ausgeschlossener Spot einer Freundin …
    backend.addSpot(ownerId: lilli.id, sharingExcluded: true);
    // … Spot eines Freundes mit global abgeschaltetem Teilen …
    backend.addSpot(ownerId: geizhals.id, lat: 51.5);
    // … und Spot eines Nicht-Freundes.
    backend.addSpot(ownerId: fremder.id, lat: 50.8);
    await pumpApp(tester, backend);

    expect(find.byType(MushroomIcon), findsNothing);
  });

  testWidgets(
      'Anfrage-Banner → annehmen → Spots des neuen Freundes erscheinen',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final bob = backend.addUser(username: 'bobby');
    backend.addFriendship(bob.id, me.id, status: 'pending');
    backend.addSpot(
        ownerId: bob.id, species: 'Parasol', foundOn: DateTime(2026, 7, 1));
    await pumpApp(tester, backend);

    // Solange die Anfrage offen ist, bleibt Bobs Spot unsichtbar.
    expect(find.byType(MushroomIcon), findsNothing);
    await tester.tap(
        find.text('🔔 1 offene Freundschaftsanfrage — antippen'));
    await settle(tester);

    expect(find.text('Anfragen an dich'), findsOneWidget);
    await tester.tap(find.byTooltip('Annehmen'));
    await settle(tester);
    expect(find.text('bobby'), findsOneWidget);
    expect(find.text('Anfragen an dich'), findsNothing);

    // Zurück zur Karte: die Annahme lädt die Freundes-Spots neu.
    await tester.tap(find.text('Karte'));
    await settle(tester);
    expect(find.byTooltip('Pilz-Spot (bobby)'), findsOneWidget);
  });

  testWidgets('Freundesuche findet Nutzer und sendet eine Anfrage',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addUser(username: 'lilli92');
    await pumpApp(tester, backend);

    await tester.tap(find.text('Freunde'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Freund finden'), 'lilli');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    await tester.tap(find.text('Anfragen'));
    await settle(tester);

    expect(backend.friendships.single.requesterId, me.id);
    expect(backend.friendships.single.status, 'pending');
    expect(find.text('Gesendete Anfragen'), findsOneWidget);
    await drainSnackbars(tester);
  });
}
