// Der Takt im Service-Isolate (#342).
//
// Hier liegt seit 1.103.0 die eigentliche Aufzeichnung — und zwar, weil
// dieses Isolate das Wegwischen der App überlebt und der Main-Isolate
// nicht. Der Feldbefund vom 2026-08-27: „Solange die App aktiv ist, wird
// sie geschlossen, wird nichts aufgezeichnet, obwohl der
// Hintergrundservice aktiv ist."
//
// Geprüft wird über die eingebauten Nähte (`fix`, `storeFor`), nicht
// gegen echtes GPS: Was zählt, sind die Regeln drumherum — schreibt er
// nur, wenn eine Tour läuft, und übersteht er einen Fehlschlag.
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pilzbuddy/features/tour/tour_task_handler.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_tour.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime.utc(2026, 8, 27, 19, 30);

  Position positionAt({double accuracy = 8}) => Position(
        latitude: 51.0,
        longitude: 11.0,
        timestamp: at,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  /// Die Brücke liegt in SharedPreferences — `saveData`/`getData` lesen
  /// sie in BEIDEN Isolaten, deshalb ist sie hier mockbar.
  Future<void> bridge({required bool active, String dir = '/tmp/tour'}) async {
    SharedPreferences.setMockInitialValues({});
    if (dir.isNotEmpty) {
      await FlutterForegroundTask.saveData(key: kTourDataDir, value: dir);
    }
    await FlutterForegroundTask.saveData(
        key: kTourDataActive, value: active);
  }

  test('läuft eine Tour, wird gemessen und angehängt', () async {
    await bridge(active: true);
    final store = FakeTourStore();
    await store.begin(uid: 'me', startedAt: at);

    final point = await recordTourTick(
      fix: () async => positionAt(),
      storeFor: (_) => store,
    );

    expect(point, isNotNull);
    expect(point!.accuracyM, 8);
    expect(store.points, hasLength(1));
    expect(store.points.single.at, at);
  });

  test('ohne laufende Tour passiert nichts', () async {
    // Der Service bleibt nach dem Beenden der Tour noch kurz stehen (er
    // trägt womöglich einen Download). Ein Takt darf dann nicht in die
    // alte Datei schreiben — sonst bekäme die nächste Tour die Punkte
    // der vorigen.
    await bridge(active: false);
    final store = FakeTourStore();
    var asked = 0;

    final point = await recordTourTick(
      fix: () async {
        asked++;
        return positionAt();
      },
      storeFor: (_) => store,
    );

    expect(point, isNull);
    expect(store.points, isEmpty);
    expect(asked, 0, reason: 'ohne Tour wird GPS gar nicht erst gefragt');
  });

  test('ohne Pfad in der Brücke passiert nichts', () async {
    await bridge(active: true, dir: '');
    final store = FakeTourStore();
    expect(
      await recordTourTick(
          fix: () async => positionAt(), storeFor: (_) => store),
      isNull,
    );
    expect(store.points, isEmpty);
  });

  test('kein Fix ist kein Fehler', () async {
    // Kein Empfang zum Himmel ist im Wald der Normalfall.
    await bridge(active: true);
    final store = FakeTourStore();
    expect(
      await recordTourTick(fix: () async => null, storeFor: (_) => store),
      isNull,
    );
    expect(store.points, isEmpty);
  });

  test('ein werfender Fix beendet die Aufzeichnung nicht', () async {
    // In diesem Isolate fängt niemand eine Ausnahme. Käme sie durch,
    // wäre die Tour für den Rest des Wegs still zu Ende — und genau das
    // merkt man erst zu Hause.
    await bridge(active: true);
    final store = FakeTourStore();
    expect(
      await recordTourTick(
          fix: () async => throw Exception('GPS weg'),
          storeFor: (_) => store),
      isNull,
    );
  });

  group('Isolat-Brücke', () {
    test('ein Punkt übersteht Hin- und Rückweg', () {
      // `sendDataToMain` trägt nur einfache Werte, deshalb die
      // Zeichenkette. Die Genauigkeit MUSS mit — sie entscheidet später
      // über die Verweildauer.
      final point = TourPoint(
          lat: 51.123456,
          lng: 11.654321,
          at: DateTime.utc(2026, 8, 27, 19, 30, 15),
          accuracyM: 7.5);
      final back = decodeTourTick(encodeTourTick(point))!;
      expect(back.lat, point.lat);
      expect(back.lng, point.lng);
      expect(back.at, point.at);
      expect(back.accuracyM, point.accuracyM);
    });

    test('Unsinn wird zu null statt zu einem falschen Punkt', () {
      expect(decodeTourTick(42), isNull);
      expect(decodeTourTick('51.0;11.0'), isNull);
      expect(decodeTourTick('a;b;c;d'), isNull);
    });
  });
}
