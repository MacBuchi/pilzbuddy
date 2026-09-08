// Darstellung der Tourspur: Punkte oder Linie, und in welcher Farbe
// (#340, Schritt 1 des Buddy-Track-Plans).
//
// Zwei Zusagen stecken hier, und beide waren vorher falsch bzw. gar
// nicht möglich: Die EIGENE Spur trug `friendBlue` — die Farbe, die
// diese App für ANDERE benutzt —, und eine Linie konnte die Fassade gar
// nicht darstellen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/map_view/map_view.dart';
import 'package:pilzbuddy/features/tour/tour_providers.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';
import 'package:pilzbuddy/features/tour/widgets/tour_track_marker.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_tour.dart';
import '../fakes/map_ui.dart';
import '../fakes/test_app.dart';

TourPoint _at({double lat = 51.0, double lng = 11.0}) => TourPoint(
      at: DateTime.utc(2026, 9, 8),
      lat: lat,
      lng: lng,
      accuracyM: 8,
    );

void main() {
  List<TourPoint> track(int count) => [
        for (var i = 0; i < count; i++)
          TourPoint(
            at: DateTime.utc(2026, 9, 8).add(Duration(seconds: 15 * i)),
            lat: 51.0 + i * 0.0001,
            lng: 11.0,
            accuracyM: 8,
          ),
      ];

  group('tourTrackPolyline', () {
    test('unter zwei Punkten gibt es keine Linie', () {
      // Ein Strich der Länge null ist keine Aussage, sondern ein Fleck.
      expect(tourTrackPolyline(track(0)), isEmpty);
      expect(tourTrackPolyline(track(1)), isEmpty);
      expect(tourTrackPolyline(track(2)), hasLength(1));
    });

    test('sie wird genauso gedünnt wie die Punkte', () {
      // Sonst hätte die Linie 2000 Stützstellen, wo das Auge 400 nicht
      // unterscheidet — und `tourVisits` rechnet ohnehin mit allen.
      final line = tourTrackPolyline(track(2000)).single;
      expect(line.points.length, lessThanOrEqualTo(kTourTrackMaxDots + 1));
      expect(line.points.length, greaterThan(300));
    });

    test('die eigene Spur ist grün, nicht Buddy-blau', () {
      // Der Fehler, der bis 1.125.1 drinstand.
      expect(tourTrackPolyline(track(5)).single.color.toARGB32(),
          kOwnTrackColor.withValues(alpha: 0.7).toARGB32());
      expect(kOwnTrackColor, isNot(const Color(0xFF1565C0)),
          reason: 'friendBlue gehört den anderen');
    });
  });

  group('der Schalter im Profil', () {
    FakeBackend loggedInBackend() {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'testpilz');
      backend.signInAs(me.id);
      return backend;
    }

    MapViewMarkers drawn(WidgetTester tester) =>
        tester.widget<FakeMapView>(find.byType(FakeMapView)).markers;

    testWidgets('ab Werk Punkte, keine Linie', (tester) async {
      final fix = FakeTourFix()..next = _at();
      await pumpApp(tester, loggedInBackend(),
          tourStore: FakeTourStore(), tourFix: fix,
          tourBridge: FakeTourServiceBridge(), keepAlive: FakeKeepAlive());
      await startTour(tester);
      await settle(tester);

      expect(drawn(tester).tourTrack, isNotEmpty);
      expect(drawn(tester).polylines, isEmpty,
          reason: 'die Punktabstände tragen die Verweildauer');
      await drainSnackbars(tester);
    });

    testWidgets('mit Schalter eine Linie und KEINE Punkte', (tester) async {
      // Nie beides: Der Strich läge auf seinen eigenen Stützstellen.
      final fix = FakeTourFix()..next = _at();
      await pumpApp(tester, loggedInBackend(),
          settings: FakeSettings(tourTrackAsLine: true),
          tourStore: FakeTourStore(), tourFix: fix,
          tourBridge: FakeTourServiceBridge(), keepAlive: FakeKeepAlive());
      await startTour(tester);
      await settle(tester);

      // Ein zweiter Punkt, denn unter zweien gibt es bewusst keine Linie.
      // Denselben Weg nimmt der Service: eine Zeichenkette hin, ein
      // Punkt zurück.
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
          .read(tourProvider.notifier)
          .acceptTick(_at(lat: 51.0005));
      await settle(tester);

      expect(drawn(tester).polylines, hasLength(1));
      expect(drawn(tester).tourTrack, isEmpty);
      // Und sie kommt auch bei der Karte AN. Ohne diese Zeile prüfte der
      // Test nur, was die Fassade übergibt — der Fake könnte Linien
      // stillschweigend fallen lassen, so wie es die echten Engines vor
      // dieser Änderung taten.
      expect(find.byKey(const ValueKey('fake-polyline')), findsOneWidget);
      await drainSnackbars(tester);
    });
  });
}
