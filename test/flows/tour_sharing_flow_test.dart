// Die eigene Tourspur zu den Buddys — durch die echte Oberfläche
// (#340, Stufe 2).
//
// **Was hier geprüft wird, ist eine Zusage, keine Funktion.** Seit
// Stufe 1 gilt: Die Spur verlässt das Gerät nie. Patch 023 bricht das
// absichtlich, aber nur unter EINER Bedingung — es muss eine Tour
// laufen UND eine Standort-Freigabe. Jeder Test hier ist eine Grenze
// dieser Bedingung, und die teuren Fälle sind die, in denen NICHTS
// hochgehen darf.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/tour/tour_providers.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';

import '../fakes/fake_backend.dart';
import '../fakes/map_ui.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  /// Punkte einspeisen, wie es das Service-Isolate täte — und danach den
  /// Takt anstoßen, den sonst `_onTourTick` auslöst.
  ///
  /// Die Uhr läuft im Test nicht: `planTrackShare` würde nach dem ersten
  /// Upload eine Minute verlangen. Jeder Punkt bekommt deshalb einen
  /// eigenen Zeitstempel, und der erste Upload passiert ohnehin sofort.
  var tick = 0;
  Future<void> feedTourPoints(WidgetTester tester, int count) async {
    final container = containerOf(tester);
    for (var i = 0; i < count; i++) {
      container.read(tourProvider.notifier).acceptTick(TourPoint(
            lat: 51.16 + tick * 0.0001,
            lng: 10.45,
            at: DateTime.utc(2026, 9, 20, 12).add(Duration(seconds: 15 * tick)),
            accuracyM: 5,
          ));
      tick++;
    }
    await container.read(tourSharingProvider.notifier).sync();
    await settle(tester);
  }

  testWidgets('Tour ohne Freigabe lädt NICHTS hoch', (tester) async {
    // Stufe 1 unverändert. Das ist der wichtigste Test der Datei: Wer
    // aufzeichnet, ohne zu teilen, behält seine Bewegungsdaten.
    final (backend, me) = loggedInBackend();
    await pumpApp(tester, backend, position: fakePosition(51.16, 10.45));

    await startTour(tester);
    expect(tourStopButton(), findsOneWidget, reason: 'die Tour läuft');

    expect(backend.tourTracks.where((r) => r.userId == me.id), isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Freigabe ohne Tour lädt NICHTS hoch', (tester) async {
    // Die Gegenrichtung: Standort-Teilen allein gibt keine Spur frei.
    final (backend, me) = loggedInBackend();
    backend.addLiveShare(me.id);
    await pumpApp(tester, backend, position: fakePosition(51.16, 10.45));

    expect(backend.tourTracks, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Tour UND Freigabe: die Spur geht hoch', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addLiveShare(me.id);
    await pumpApp(tester, backend, position: fakePosition(51.16, 10.45));

    await startTour(tester);
    // Zwei Punkte, sonst gibt es keine Spur (`kMinSharedTrackPoints`).
    await feedTourPoints(tester, 2);

    final row = backend.tourTracks.singleWhere((r) => r.userId == me.id);
    expect(row.points, hasLength(2));
    expect(row.expiresAt,
        backend.liveLocations.singleWhere((r) => r.userId == me.id).expiresAt,
        reason: 'die Frist wird GEERBT, nicht neu erfunden');
    await drainSnackbars(tester);
  });

  testWidgets('Ein einzelner Punkt ist noch keine Spur', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addLiveShare(me.id);
    await pumpApp(tester, backend, position: fakePosition(51.16, 10.45));

    await startTour(tester);
    await feedTourPoints(tester, 1);

    expect(backend.tourTracks.where((r) => r.userId == me.id), isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Tour beenden nimmt die Spur wieder vom Server',
      (tester) async {
    // Nicht erst beim Ablauf der Freigabe: Bis dahin läge dort eine
    // Freigabe, die niemand mehr gibt.
    final (backend, me) = loggedInBackend();
    backend.addLiveShare(me.id);
    await pumpApp(tester, backend, position: fakePosition(51.16, 10.45));

    await startTour(tester);
    await feedTourPoints(tester, 2);
    expect(backend.tourTracks.where((r) => r.userId == me.id), isNotEmpty);

    await tester.tap(tourStopButton());
    await settle(tester);

    expect(backend.tourTracks.where((r) => r.userId == me.id), isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Es bleibt bei EINER Zeile, egal wie lange gelaufen wird',
      (tester) async {
    // Die Eigenschaft, für die die Tabelle so geschnitten ist: Die
    // Zeilenzahl darf nicht mit der verbrachten Zeit wachsen.
    final (backend, me) = loggedInBackend();
    backend.addLiveShare(me.id);
    await pumpApp(tester, backend, position: fakePosition(51.16, 10.45));

    await startTour(tester);
    await feedTourPoints(tester, 2);
    final container = containerOf(tester);
    for (var i = 0; i < 5; i++) {
      await feedTourPoints(tester, 1);
      await container.read(tourSharingProvider.notifier).sync();
      await settle(tester);
    }

    expect(backend.tourTracks.where((r) => r.userId == me.id), hasLength(1));
    await drainSnackbars(tester);
  });

  testWidgets('Die Spur eines Nicht-Freundes bleibt unsichtbar',
      (tester) async {
    // Spiegelt `tt_friend_select` über den Fake. Der Lesepfad wird erst
    // im zweiten PR gezeichnet — geprüft gehört er jetzt, weil genau er
    // falsch sein könnte.
    final (backend, me) = loggedInBackend();
    final fremder = backend.addUser(username: 'fremder');
    backend.addLiveShare(fremder.id);
    backend.tourTracks.add(FakeTourTrackRow(
      userId: fremder.id,
      startedAt: DateTime.now().toUtc(),
      points: const [],
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    await pumpApp(tester, backend);

    final tracks = await FakeTourTrackRepository(backend).fetchFriendTracks();
    expect(tracks, isEmpty, reason: 'keine Freundschaft, keine Spur');

    backend.addFriendship(fremder.id, me.id);
    expect(await FakeTourTrackRepository(backend).fetchFriendTracks(),
        hasLength(1));
    await drainSnackbars(tester);
  });
}
