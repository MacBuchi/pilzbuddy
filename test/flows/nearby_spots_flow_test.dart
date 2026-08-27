// Spots überlagern sich nicht mehr (#215) — die beiden Wege von Hand:
// die Rückfrage beim Anlegen und das Aufräumen im Profil.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Die Kartenmitte im Harness — dort sitzt das Fadenkreuz.
  const crosshairLat = 51.1634;
  const crosshairLng = 10.4477;

  /// [meters] nördlich der Kartenmitte.
  double northOfCrosshair(double meters) => crosshairLat + meters / 111200;

  group('Rückfrage beim Anlegen', () {
    testWidgets('Ein Spot in Reichweite fragt nach — „Dort eintragen" legt '
        'keinen zweiten an', (tester) async {
      final (backend, me) = loggedInBackend();
      backend.addSpot(
          ownerId: me.id,
          name: 'Buchenhang',
          lat: northOfCrosshair(8),
          lng: crosshairLng,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 7, 1));
      await pumpApp(tester, backend);

      await tester.tap(find.text('Neuer Spot'));
      await settle(tester);

      expect(find.text('Hier liegt schon ein Spot'), findsOneWidget);
      expect(find.textContaining('8 m entfernt'), findsOneWidget);
      expect(find.textContaining('Buchenhang'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('Dort eintragen'));
      await settle(tester);

      // Es öffnet das FUND-Blatt, nicht das Anlege-Blatt.
      expect(find.text('Fund eintragen'), findsOneWidget);
      expect(find.text('Neuer Pilz-Spot'), findsNothing);

      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await settle(tester);

      // Der springende Punkt: EIN Spot, zwei Einträge.
      expect(backend.spots, hasLength(1));
      expect(backend.spots.single.finds, hasLength(2));
      expect(find.textContaining('Buchenhang'), findsAtLeastNWidgets(1));
    });

    testWidgets('„Trotzdem neuer Spot" legt den zweiten an', (tester) async {
      final (backend, me) = loggedInBackend();
      backend.addSpot(
          ownerId: me.id,
          name: 'Buchenhang',
          lat: northOfCrosshair(8),
          lng: crosshairLng,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 7, 1));
      await pumpApp(tester, backend);

      await tester.tap(find.text('Neuer Spot'));
      await settle(tester);
      await tester.tap(find.text('Trotzdem neuer Spot'));
      await settle(tester);

      expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await settle(tester);

      expect(backend.spots, hasLength(2));
    });

    testWidgets('Weit genug weg fragt gar nicht', (tester) async {
      final (backend, me) = loggedInBackend();
      backend.addSpot(
          ownerId: me.id,
          lat: northOfCrosshair(60),
          lng: crosshairLng,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 7, 1));
      await pumpApp(tester, backend);

      await tester.tap(find.text('Neuer Spot'));
      await settle(tester);

      expect(find.text('Hier liegt schon ein Spot'), findsNothing);
      expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
    });

    testWidgets('Der Spot eines Buddys löst keine Rückfrage aus',
        (tester) async {
      // Sonst hinge der Fund plötzlich bei jemand anderem.
      //
      // Ein ERGEBNIS-Test, kein Wächter über einen einzelnen Mechanismus:
      // Dahinter stehen zwei, die einander decken — die Karte übergibt
      // ohnehin nur eigene Spots, und `nearestOwnSpot` siebt fremde
      // zusätzlich aus. Erst wenn man beides aufgibt, wird dieser Test rot
      // (nachgemessen). Das ist Absicht: Welcher der beiden bleibt, ist
      // egal, das Ergebnis nicht.
      final (backend, me) = loggedInBackend();
      final lilli = backend.addUser(username: 'lilli92');
      backend.addFriendship(lilli.id, me.id);
      backend.addSpot(
          ownerId: lilli.id,
          lat: northOfCrosshair(5),
          lng: crosshairLng,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 7, 1));
      await pumpApp(tester, backend);

      await tester.tap(find.text('Neuer Spot'));
      await settle(tester);

      expect(find.text('Hier liegt schon ein Spot'), findsNothing);
      expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
    });
  });

  group('Aufräumen im Profil', () {
    testWidgets('Paar wird gelistet und lässt sich zusammenführen',
        (tester) async {
      final (backend, me) = loggedInBackend();
      final a = backend.addSpot(
          ownerId: me.id,
          name: 'Alter Hang',
          lat: crosshairLat,
          lng: crosshairLng,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 7, 1));
      final b = backend.addSpot(
          ownerId: me.id,
          name: 'Neuer Hang',
          lat: northOfCrosshair(6),
          lng: crosshairLng,
          species: 'Marone',
          foundOn: DateTime(2026, 7, 2));
      await pumpApp(tester, backend);

      await tester.tap(find.text('Profil'));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Dicht beieinander'), 200,
          scrollable: find.byType(Scrollable).first);
      // `scrollUntilVisible` hört auf, sobald das Ziel im Viewport ist —
      // das kann haarscharf am Rand sein, und dann geht der Tipp ins
      // Leere. Beim Zuwachs der Profilliste (#338) genau so passiert.
      await tester.ensureVisible(find.text('Dicht beieinander'));
      await settle(tester);
      await tester.tap(find.text('Dicht beieinander'));
      await settle(tester);

      expect(find.textContaining('6 m auseinander'), findsOneWidget);

      await tester.tap(find.text('In „Alter Hang"'));
      await settle(tester);
      expect(find.text('Spots zusammenführen?'), findsOneWidget);
      await tester.tap(find.text('Zusammenführen'));
      await settle(tester);

      // Ein Spot bleibt, mit beiden Funden.
      expect(backend.spots, hasLength(1));
      expect(backend.spots.single.id, a);
      expect(backend.spots.single.finds, hasLength(2));
      expect(backend.spots.where((s) => s.id == b), isEmpty);
    });

    testWidgets('Ein Paar mit Buddy-Fund wird nicht angeboten',
        (tester) async {
      // Die RLS ließe den fremden Fund nicht mitwandern, und die
      // Lösch-Kaskade nähme ihn still mit.
      final (backend, me) = loggedInBackend();
      final lilli = backend.addUser(username: 'lilli92');
      backend.addFriendship(lilli.id, me.id);
      backend.addSpot(
          ownerId: me.id,
          name: 'Alter Hang',
          lat: crosshairLat,
          lng: crosshairLng,
          species: 'Steinpilz',
          foundOn: DateTime(2026, 7, 1));
      final b = backend.addSpot(
          ownerId: me.id,
          name: 'Neuer Hang',
          lat: northOfCrosshair(6),
          lng: crosshairLng,
          species: 'Marone',
          foundOn: DateTime(2026, 7, 2));
      backend.addFindRow(b,
          species: 'Pfifferling',
          foundOn: DateTime(2026, 7, 3),
          authorId: lilli.id);
      await pumpApp(tester, backend);

      await tester.tap(find.text('Profil'));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Dicht beieinander'), 200,
          scrollable: find.byType(Scrollable).first);
      // `scrollUntilVisible` hört auf, sobald das Ziel im Viewport ist —
      // das kann haarscharf am Rand sein, und dann geht der Tipp ins
      // Leere. Beim Zuwachs der Profilliste (#338) genau so passiert.
      await tester.ensureVisible(find.text('Dicht beieinander'));
      await settle(tester);
      await tester.tap(find.text('Dicht beieinander'));
      await settle(tester);

      expect(find.textContaining('6 m auseinander'), findsOneWidget);
      expect(find.text('In „Alter Hang"'), findsNothing);
      expect(find.textContaining('Pilz-Buddy eingetragen'), findsOneWidget);
    });

    testWidgets('Ohne Überlagerung gibt es den Profil-Eintrag nicht',
        (tester) async {
      final (backend, me) = loggedInBackend();
      backend.addSpot(ownerId: me.id, lat: crosshairLat, lng: crosshairLng);
      backend.addSpot(ownerId: me.id, lat: 51.5, lng: crosshairLng);
      await pumpApp(tester, backend);

      await tester.tap(find.text('Profil'));
      await settle(tester);

      expect(find.text('Dicht beieinander'), findsNothing);
    });
  });
}
