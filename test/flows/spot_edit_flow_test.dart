// Name und Stelle eines Spots nachträglich korrigieren (#466).
//
// Der Wunsch: „Erlaube es den Spot nachträglich von der Position zu
// korrigieren." Unter Blätterdach liegt ein Fix 10–20 m daneben, und bis
// 1.144.0 war die Stelle beim Anlegen endgültig — der Name übrigens
// auch, der war nach dem Anlegen nirgends mehr erreichbar.
//
// Geprüft wird durch die echte Oberfläche, weil der teure Fehler nicht
// „lässt sich nicht verschieben" wäre, sondern „lässt sich verschieben
// und wird woanders gespeichert" — dieselbe Falle wie beim Anlegen
// (#407, `spot_position_flow_test.dart`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/widgets/mini_map.dart';
import 'package:pilzbuddy/features/map/widgets/spot_position_field.dart';
import 'package:pilzbuddy/core/errors.dart';
import 'package:pilzbuddy/models/find_position.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> openSpot(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await settle(tester);
  }

  Future<void> openEditSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Spot bearbeiten'));
    await settle(tester);
    expect(find.text('Spot bearbeiten'), findsWidgets);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
  }

  testWidgets('Das Blatt ist mit dem vorbelegt, was dasteht', (tester) async {
    // Vorbelegen ist keine Bequemlichkeit: Ohne sie wäre jede Korrektur
    // ein Neuschreiben, und wer nur die Stelle rücken will, verlöre den
    // Namen.
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
    await pumpApp(tester, backend);

    await openSpot(tester, 'Buchenhang');
    await openEditSheet(tester);

    expect(find.widgetWithText(TextField, 'Buchenhang'), findsOneWidget);
    // DASSELBE Widget wie im Anlege-Blatt, keine Kopie: Die Stelle wird
    // überall gleich gewählt, mit demselben Ring und derselben
    // Entfernungszeile. Zwei Fassungen wären zwei Antworten auf „wo
    // liegt der Spot".
    expect(find.byType(SpotPositionField), findsOneWidget);
    final map = tester.widget<MiniMap>(find.byType(MiniMap));
    expect(map.mode, MiniMapMode.pick);
    expect(map.reference.latitude, closeTo(50.5, 1e-9),
        reason: 'der Ring liegt auf der BISHERIGEN Stelle');
    expect(map.reference.longitude, closeTo(7.5, 1e-9));
  });

  testWidgets('Eine verschobene Stelle wird auch dort gespeichert',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
    await pumpApp(tester, backend);

    await openSpot(tester, 'Buchenhang');
    await openEditSheet(tester);

    tester.widget<MiniMap>(find.byType(MiniMap)).onCenterChanged!(
        const LatLng(50.50018, 7.50022));
    await settle(tester);
    await save(tester);

    final spot = backend.spots.single;
    expect(spot.lat, closeTo(50.50018, 1e-9));
    expect(spot.lng, closeTo(7.50022, 1e-9));
    expect(spot.name, 'Buchenhang', reason: 'was niemand anfasst, bleibt');
    await drainSnackbars(tester);
  });

  testWidgets('Der Name lässt sich ändern — zum ersten Mal überhaupt',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
    await pumpApp(tester, backend);

    await openSpot(tester, 'Buchenhang');
    await openEditSheet(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Buchenhang'), 'Buchenhang am Bach');
    await settle(tester, frames: 4);
    await save(tester);

    final spot = backend.spots.single;
    expect(spot.name, 'Buchenhang am Bach');
    expect(spot.lat, closeTo(50.5, 1e-9),
        reason: 'ein Namenswechsel rückt die Stelle nicht');
    await drainSnackbars(tester);
  });

  testWidgets('Ein leerer Name wird null, kein leerer String',
      (tester) async {
    // Zwei Wege, dasselbe zu sagen, wären einer zu viel: Die Anzeige
    // fragt `name != null && name.isNotEmpty` und zeigt sonst
    // „Pilz-Spot". Ein leerer String käme dort an wie `null` — aber nur
    // hier, und beim nächsten Leser vielleicht nicht.
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang');
    await pumpApp(tester, backend);

    await openSpot(tester, 'Buchenhang');
    await openEditSheet(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Buchenhang'), '   ');
    await settle(tester, frames: 4);
    await save(tester);

    expect(backend.spots.single.name, isNull);
    await drainSnackbars(tester);
  });

  testWidgets('Ohne Zutun ändert sich nichts', (tester) async {
    // Die Gegenrichtung. Ein Blatt, das beim bloßen Öffnen und
    // Speichern etwas verschiebt, wäre schlimmer als gar keins.
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
    await pumpApp(tester, backend);

    await openSpot(tester, 'Buchenhang');
    await openEditSheet(tester);
    await save(tester);

    final spot = backend.spots.single;
    expect(spot.name, 'Buchenhang');
    expect(spot.lat, closeTo(50.5, 1e-9));
    expect(spot.lng, closeTo(7.5, 1e-9));
    await drainSnackbars(tester);
  });

  testWidgets('Funde mit eigener Stelle bleiben, wo sie gemessen wurden',
      (tester) async {
    // Die Entscheidung, die man im Diff nicht sieht: `findOffset`
    // rechnet den Versatz beim LESEN aus absoluten Koordinaten. Ein Fund
    // ohne eigene Stelle erbt die des Spots und wandert von selbst mit;
    // ein Fund MIT eigener Stelle (#373) trägt eine eigene Messung, die
    // von dieser Korrektur nichts weiß. Sie mitzuschieben hieße, fremde
    // Messungen umzuschreiben.
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1),
        position: const FindPosition.picked(lat: 50.5004, lng: 7.5004));
    await pumpApp(tester, backend);

    await openSpot(tester, 'Buchenhang');
    await openEditSheet(tester);
    tester
        .widget<MiniMap>(find.byType(MiniMap))
        .onCenterChanged!(const LatLng(50.502, 7.502));
    await settle(tester);
    await save(tester);

    final position = backend.spots.single.finds.single.position!;
    expect(position.lat, closeTo(50.5004, 1e-9));
    expect(position.lng, closeTo(7.5004, 1e-9));
    await drainSnackbars(tester);
  });

  testWidgets('Ein wartender Spot lässt sich nicht bearbeiten',
      (tester) async {
    // Ihm fehlt die Server-id, auf die das Update zeigen müsste (#267) —
    // dieselbe Grenze wie beim Ändern einzelner Einträge. Ausgerechnet
    // der Spot, den man gerade im Funkloch mit schlechtem GPS gesetzt
    // hat, ist damit nicht korrigierbar; das ist bekannt und bewusst,
    // denn Aufträge im Korb umzuschreiben ist ein eigenes Thema.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, outbox: FakeOutbox());
    backend.offline = true;

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    await drainSnackbars(tester);

    await openSpot(tester, 'Pilz-Spot — wartet auf Verbindung');
    // Der Löschen-Knopf ist da und heißt anders: Er nimmt den Auftrag
    // zurück, dafür braucht es keine Server-id. Das belegt zugleich,
    // dass wirklich das Blatt des WARTENDEN Spots offen ist.
    expect(find.byTooltip('Eintrag verwerfen'), findsOneWidget);
    expect(find.byTooltip('Spot bearbeiten'), findsNothing);
  });

  test('Ein fremder Spot wird abgelehnt, nicht stillschweigend übergangen',
      () async {
    // Live zieht `spots_owner_all` die Grenze, und PostgREST meldet ein
    // Update auf null Zeilen NICHT als Fehler — ohne das `.select('id')`
    // meldete die App Erfolg für einen Vorgang, der nie stattfand
    // (dieselbe Falle wie bei `updateFind`). Der Fake spiegelt das.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final buddy = backend.addUser(username: 'buddy');
    backend.signInAs(me.id);
    final foreign =
        backend.addSpot(ownerId: buddy.id, name: 'Buddyhang', lat: 50.5, lng: 7.5);

    await expectLater(
      FakeSpotRepository(backend).editSpot(
          spotId: foreign, name: 'geklaut', lat: 1, lng: 1),
      throwsA(isA<WriteRejectedException>()),
    );
    final row = backend.spots.single;
    expect(row.name, 'Buddyhang');
    expect(row.lat, closeTo(50.5, 1e-9));
  });

  testWidgets('An einem Freundes-Spot gibt es den Knopf nicht',
      (tester) async {
    // `spots_owner_all` lässt nur den Besitzer schreiben. Was die
    // Datenbank ablehnt, darf die Oberfläche nicht anbieten.
    final (backend, me) = loggedInBackend();
    final buddy = backend.addUser(username: 'buddy');
    backend.addFriendship(me.id, buddy.id);
    backend.addSpot(ownerId: buddy.id, name: 'Buddyhang');
    await pumpApp(tester, backend);

    // Der Tooltip eines fremden Markers nennt den Besitzer mit.
    await openSpot(tester, 'Buddyhang (buddy)');
    expect(find.text('Gefunden von buddy'), findsOneWidget,
        reason: 'das Blatt des Buddy-Spots ist wirklich offen');
    expect(find.byTooltip('Spot bearbeiten'), findsNothing);
  });
}
