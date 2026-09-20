// Die Spuren der Buddys auf der Karte (#340, Stufe 2, Anzeige-Hälfte).
//
// **Die wichtigste Zusage steht ganz unten und ist eine Unterlassung:**
// Boden, den jemand ANDERES gegangen ist, ist kein Boden, den ICH
// abgesucht habe. Eine fremde Spur darf meine Leergänge nie
// beeinflussen — das ist die Stichprobe, die #199 als unabhängigen
// Prüfstein der Pilzampel aufhebt, und der Grund, warum Stufe 1
// überhaupt so vorsichtig gebaut wurde.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/map/live_share_providers.dart';
import 'package:pilzbuddy/features/map/map_view/map_view.dart';
import 'package:pilzbuddy/features/tour/tour_providers.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';
import 'package:pilzbuddy/features/tour/widgets/tour_track_marker.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/test_app.dart';

void main() {
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  List<TourPoint> walk(int count) => [
        for (var i = 0; i < count; i++)
          TourPoint(
            lat: 51.16 + i * 0.0005,
            lng: 10.45,
            at: DateTime.utc(2026, 9, 20, 12).add(Duration(seconds: 15 * i)),
            accuracyM: 5,
          ),
      ];

  /// Ein Buddy, der teilt UND eine Spur hochgeladen hat.
  FakeUser sharingBuddy(FakeBackend backend, FakeUser me,
      {String name = 'lilli92', int points = 4}) {
    final buddy = backend.addUser(username: name);
    backend.addFriendship(buddy.id, me.id);
    backend.addLiveShare(buddy.id);
    backend.tourTracks.add(FakeTourTrackRow(
      userId: buddy.id,
      startedAt: DateTime.utc(2026, 9, 20, 12),
      points: walk(points),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    return buddy;
  }

  MapViewMarkers markersOf(WidgetTester tester) =>
      tester.widget<FakeMapView>(find.byType(FakeMapView)).markers;

  testWidgets('Die Spur eines Buddys erscheint auf der Karte',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final buddy = sharingBuddy(backend, me);
    await pumpApp(tester, backend);
    await settle(tester);

    final dots = markersOf(tester).tourTrack;
    expect(dots, isNotEmpty);
    // In seiner Farbe, nicht in meiner.
    final painted = tester
        .widgetList<TourTrackDot>(find.byType(TourTrackDot))
        .map((d) => d.color)
        .toSet();
    expect(painted, contains(buddyTrackColor(buddy.id)));
    expect(painted, isNot(contains(AppColors.forestGreen)),
        reason: 'ich laufe gerade gar keine Tour');
  });

  testWidgets('Zwei Buddys bekommen zwei Farben', (tester) async {
    final (backend, me) = loggedInBackend();
    final a = sharingBuddy(backend, me, name: 'lilli92');
    final b = sharingBuddy(backend, me, name: 'jonas');
    await pumpApp(tester, backend);
    await settle(tester);

    final painted = tester
        .widgetList<TourTrackDot>(find.byType(TourTrackDot))
        .map((d) => d.color)
        .toSet();
    expect(painted, contains(buddyTrackColor(a.id)));
    expect(painted, contains(buddyTrackColor(b.id)));
    expect(painted.length, greaterThanOrEqualTo(2));
  });

  testWidgets('Ohne Freundschaft bleibt die Spur unsichtbar',
      (tester) async {
    // Spiegelt `tt_friend_select`. Der Fake zieht dieselbe Grenze wie
    // die Policy — hier geht es um Bewegungsdaten.
    final (backend, _) = loggedInBackend();
    final fremder = backend.addUser(username: 'fremder');
    backend.addLiveShare(fremder.id);
    backend.tourTracks.add(FakeTourTrackRow(
      userId: fremder.id,
      startedAt: DateTime.utc(2026, 9, 20, 12),
      points: walk(4),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    await pumpApp(tester, backend);
    await settle(tester);

    expect(markersOf(tester).tourTrack, isEmpty);
  });

  testWidgets('Eine abgelaufene Spur erscheint nicht', (tester) async {
    final (backend, me) = loggedInBackend();
    final buddy = backend.addUser(username: 'lilli92');
    backend.addFriendship(buddy.id, me.id);
    backend.addLiveShare(buddy.id);
    backend.tourTracks.add(FakeTourTrackRow(
      userId: buddy.id,
      startedAt: DateTime.utc(2026, 9, 20, 12),
      points: walk(4),
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    ));
    await pumpApp(tester, backend);
    await settle(tester);

    expect(markersOf(tester).tourTrack, isEmpty);
  });

  testWidgets('Teilt niemand, wird gar nicht erst nach Spuren gefragt',
      (tester) async {
    // Der Torwächter: Eine Spur gibt es nur, wo auch ein Live-Standort
    // ist. Ohne den spart der Provider den Poll ganz — dieselbe Linie
    // wie #316 („every query that isn't necessary should be saved").
    final (backend, me) = loggedInBackend();
    final buddy = backend.addUser(username: 'lilli92');
    backend.addFriendship(buddy.id, me.id);
    // Spur da, aber KEINE Standort-Freigabe.
    backend.tourTracks.add(FakeTourTrackRow(
      userId: buddy.id,
      startedAt: DateTime.utc(2026, 9, 20, 12),
      points: walk(4),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    await pumpApp(tester, backend);
    await settle(tester);

    expect(containerOf(tester).read(friendTracksProvider).valueOrNull,
        isEmpty);
    expect(markersOf(tester).tourTrack, isEmpty);
  });

  testWidgets('Eine fremde Spur zählt NICHT als mein Leergang',
      (tester) async {
    // Die Zusage, für die dieser Test existiert. Der Buddy läuft
    // mitten über meinen Spot; mein eigener Tour-Zustand bleibt leer,
    // also darf das Abschluss-Blatt dort nichts anbieten.
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', lat: 51.16, lng: 10.45);
    sharingBuddy(backend, me, points: 20);
    await pumpApp(tester, backend);
    await settle(tester);

    final container = containerOf(tester);
    expect(container.read(tourProvider)?.points ?? const [], isEmpty,
        reason: 'ich habe keine Tour — fremde Punkte dürfen hier nie landen');
    // Aber die fremde Spur IST da — der Test prüft also wirklich die
    // Trennung und nicht nur eine leere Karte.
    expect(markersOf(tester).tourTrack, isNotEmpty);
    // Und die Auswertung selbst: Sie bekommt ausschließlich eigene
    // Punkte übergeben (map_screen.dart:450). Mit einer leeren eigenen
    // Spur gibt es keinen einzigen Besuch, egal wie weit der Buddy lief.
    expect(tourVisits(const [], []), isEmpty);
  });
}
