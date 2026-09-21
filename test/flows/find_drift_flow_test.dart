// Fundstellen weit vom Spot (#475): Warndreieck auf der Karte, Zeile im
// Blatt, „So gewollt" — und die beiden Fragen beim Verlegen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';
import 'package:pilzbuddy/features/map/widgets/mini_map.dart';
import 'package:pilzbuddy/models/find_position.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Spot bei 50.5/7.5, ein Steinpilz ~245 m nördlich.
  const farPosition = FindPosition.picked(lat: 50.5022, lng: 7.5);

  bool markerDrift(WidgetTester tester, String tooltip) => tester
      .widget<MushroomIcon>(find.descendant(
          of: find.byTooltip(tooltip), matching: find.byType(MushroomIcon)))
      .drift;

  Future<void> openSpot(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await settle(tester);
  }

  testWidgets('eine Fundstelle über 100 m: Dreieck am Marker, Zeile im '
      'Blatt, „So gewollt" nimmt beides', (tester) async {
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        position: farPosition);
    await pumpApp(tester, backend);

    expect(markerDrift(tester, 'Buchenhang'), isTrue);
    await openSpot(tester, 'Buchenhang');
    expect(find.textContaining('1 Fundstelle liegt über 100 m vom Spot'),
        findsOneWidget);
    expect(find.textContaining('Steinpilz'), findsWidgets);
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    expect(find.text('So gewollt'), findsOneWidget);

    await tester.tap(find.text('So gewollt'));
    await settle(tester);
    expect(backend.spots.single.offsetConfirmedAt, isNotNull);
    expect(find.text('So gewollt'), findsNothing);
    expect(find.textContaining('— bestätigt'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    await tester.tapAt(const Offset(20, 20)); // Blatt schließen
    await settle(tester);
    expect(markerDrift(tester, 'Buchenhang'), isFalse);
  });

  testWidgets('ein jüngerer Fund weit weg bringt die Warnung zurück',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        position: farPosition);
    backend.spots.single.offsetConfirmedAt = DateTime(2026, 9, 5);
    backend.addFindRow(spotId,
        species: 'Pfifferling',
        foundOn: DateTime(2026, 9, 12),
        createdAt: DateTime(2026, 9, 12),
        position: const FindPosition.picked(lat: 50.5, lng: 7.506));
    await pumpApp(tester, backend);

    expect(markerDrift(tester, 'Buchenhang'), isTrue);
    await openSpot(tester, 'Buchenhang');
    expect(find.textContaining('2 Fundstellen liegen über 100 m'),
        findsOneWidget);
    expect(find.text('So gewollt'), findsOneWidget);
  });

  testWidgets('am Buddy-Spot nur die Auskunft: kein Knopf, kein Dreieck',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final buddy = backend.addUser(username: 'buddy');
    backend.addFriendship(me.id, buddy.id);
    final spotId = backend.addSpot(
        ownerId: buddy.id, name: 'Buddyhang', lat: 50.5, lng: 7.5);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        authorId: buddy.id,
        position: farPosition);
    await pumpApp(tester, backend);

    expect(markerDrift(tester, 'Buddyhang (buddy)'), isFalse);
    await openSpot(tester, 'Buddyhang (buddy)');
    expect(find.textContaining('1 Fundstelle liegt über 100 m'),
        findsOneWidget);
    expect(find.text('So gewollt'), findsNothing);
  });

  group('Spot verlegen mit Fundstellen', () {
    Future<void> moveSpot(WidgetTester tester, LatLng to) async {
      await tester.tap(find.byTooltip('Spot bearbeiten'));
      await settle(tester);
      tester.widget<MiniMap>(find.byType(MiniMap)).onCenterChanged!(to);
      await settle(tester);
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await settle(tester);
    }

    testWidgets('„Nur den Spot": Stellen bleiben, die Bestätigung fällt',
        (tester) async {
      final (backend, me) = loggedInBackend();
      final spotId = backend.addSpot(
          ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
      backend.addFindRow(spotId,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 9, 1),
          createdAt: DateTime(2026, 9, 1),
          position: farPosition);
      backend.spots.single.offsetConfirmedAt = DateTime(2026, 9, 5);
      await pumpApp(tester, backend);

      await openSpot(tester, 'Buchenhang');
      await moveSpot(tester, const LatLng(50.51, 7.5));
      expect(find.text('Fundstellen mitnehmen?'), findsOneWidget);
      await tester.tap(find.text('Nur den Spot'));
      await settle(tester);

      final row = backend.spots.single;
      expect(row.lat, closeTo(50.51, 1e-9));
      expect(row.finds.single.position, farPosition);
      expect(row.offsetConfirmedAt, isNull,
          reason: 'die Stellen stehen neu zum Spot');
      await drainSnackbars(tester);
    });

    testWidgets('„Spot und alle Fundstellen": eigene Stellen gelten am Spot, '
        'fremde bleiben', (tester) async {
      final (backend, me) = loggedInBackend();
      final buddy = backend.addUser(username: 'buddy');
      backend.addFriendship(me.id, buddy.id);
      final spotId = backend.addSpot(
          ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
      backend.addFindRow(spotId,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 9, 1),
          createdAt: DateTime(2026, 9, 1),
          position: const FindPosition.gps(
              lat: 50.5001, lng: 7.5, accuracy: 8));
      backend.addFindRow(spotId,
          species: 'Pfifferling',
          foundOn: DateTime(2026, 9, 2),
          createdAt: DateTime(2026, 9, 2),
          authorId: buddy.id,
          position: farPosition);
      await pumpApp(tester, backend);

      await openSpot(tester, 'Buchenhang');
      await moveSpot(tester, const LatLng(50.51, 7.5));
      expect(find.text('Fundstellen mitnehmen?'), findsOneWidget);
      expect(find.textContaining('gemessene Positionen'), findsOneWidget);
      expect(find.textContaining('von Buddys'), findsOneWidget);
      await tester.tap(find.text('Spot und alle Fundstellen'));
      await settle(tester);

      final row = backend.spots.single;
      expect(row.lat, closeTo(50.51, 1e-9));
      final mine = row.finds.firstWhere((f) => f.authorId == me.id);
      final theirs = row.finds.firstWhere((f) => f.authorId == buddy.id);
      expect(mine.position, isNull, reason: 'gilt jetzt am Spot');
      expect(theirs.position, farPosition, reason: 'fremde Messung bleibt');
      await drainSnackbars(tester);
    });

    testWidgets('Abbrechen schreibt nichts', (tester) async {
      final (backend, me) = loggedInBackend();
      final spotId = backend.addSpot(
          ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
      backend.addFindRow(spotId,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 9, 1),
          position: farPosition);
      await pumpApp(tester, backend);

      await openSpot(tester, 'Buchenhang');
      await moveSpot(tester, const LatLng(50.51, 7.5));
      await tester.tap(find.text('Abbrechen'));
      await settle(tester);
      expect(backend.spots.single.lat, closeTo(50.5, 1e-9));
    });

    testWidgets('ohne Fundstellen mit Position wird nicht gefragt',
        (tester) async {
      final (backend, me) = loggedInBackend();
      backend.addSpot(
          ownerId: me.id,
          name: 'Buchenhang',
          lat: 50.5,
          lng: 7.5,
          species: 'Steinpilz');
      await pumpApp(tester, backend);

      await openSpot(tester, 'Buchenhang');
      await moveSpot(tester, const LatLng(50.51, 7.5));
      expect(find.text('Fundstellen mitnehmen?'), findsNothing);
      expect(backend.spots.single.lat, closeTo(50.51, 1e-9));
      await drainSnackbars(tester);
    });
  });

  group('Fundstelle verlegen', () {
    Future<void> moveFind(WidgetTester tester, LatLng to) async {
      // Bei mehreren Einträgen der oberste — die Liste ist nach Datum
      // sortiert, jüngster zuerst.
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await settle(tester);
      tester.widget<MiniMap>(find.byType(MiniMap)).onCenterChanged!(to);
      await settle(tester);
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await settle(tester);
    }

    testWidgets('„Nur diese Fundstelle" rückt nur sie', (tester) async {
      final (backend, me) = loggedInBackend();
      final spotId = backend.addSpot(
          ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
      backend.addFindRow(spotId,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 9, 1),
          position: const FindPosition.picked(lat: 50.5001, lng: 7.5));
      await pumpApp(tester, backend);

      await openSpot(tester, 'Buchenhang');
      await moveFind(tester, const LatLng(50.5022, 7.5));
      expect(find.text('Spot mitverschieben?'), findsOneWidget);
      await tester.tap(find.text('Nur diese Fundstelle'));
      await settle(tester);

      final row = backend.spots.single;
      expect(row.lat, closeTo(50.5, 1e-9), reason: 'der Spot bleibt');
      expect(row.finds.single.position!.lat, closeTo(50.5022, 1e-9));
    });

    testWidgets('„Spot und alle Fundstellen": der Spot rückt hin, alle '
        'eigenen Stellen gelten dort', (tester) async {
      final (backend, me) = loggedInBackend();
      final spotId = backend.addSpot(
          ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
      backend.addFindRow(spotId,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 9, 1),
          position: const FindPosition.picked(lat: 50.5001, lng: 7.5));
      backend.addFindRow(spotId,
          species: 'Pfifferling',
          foundOn: DateTime(2026, 8, 20),
          position: const FindPosition.gps(
              lat: 50.5002, lng: 7.5, accuracy: 6));
      await pumpApp(tester, backend);

      await openSpot(tester, 'Buchenhang');
      // Der jüngste Eintrag steht oben — das ist der gewählte Steinpilz.
      await moveFind(tester, const LatLng(50.5022, 7.5));
      await tester.tap(find.text('Spot und alle Fundstellen'));
      await settle(tester);

      final row = backend.spots.single;
      expect(row.lat, closeTo(50.5022, 1e-9));
      expect(row.finds.every((f) => f.position == null), isTrue,
          reason: 'alle eigenen Stellen gelten am neuen Spot');
      expect(row.finds.length, 2, reason: 'kein Eintrag geht verloren');
      expect(row.offsetConfirmedAt, isNull);
    });

    testWidgets('ohne Rücken wird nicht gefragt', (tester) async {
      final (backend, me) = loggedInBackend();
      final spotId = backend.addSpot(
          ownerId: me.id, name: 'Buchenhang', lat: 50.5, lng: 7.5);
      backend.addFindRow(spotId,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 9, 1),
          position: const FindPosition.picked(lat: 50.5001, lng: 7.5));
      await pumpApp(tester, backend);

      await openSpot(tester, 'Buchenhang');
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(find.text('Spot mitverschieben?'), findsNothing);
    });
  });
}
