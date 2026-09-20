// Die Rückrichtung vom Service-Isolate zur Karte (#465).
//
// Der Weg hat zwei Hälften, und beide sind einzeln unauffällig: Der
// Service schreibt jeden Takt in die Datei UND meldet ihn per
// `sendDataToMain`; die Karte hört mit `addTaskDataCallback`. Dazwischen
// liegt ein benannter Port, den ausschließlich `initCommunicationPort`
// anlegt — das Paket ruft ihn nie von selbst, es steht als Zeile für
// `main()` in dessen README.
//
// Fehlte sie, schlug `sendDataToMain` `null` nach und verwarf die
// Meldung: kein Fehler, kein Eintrag, keine Spur. Die Karte kannte
// deshalb nur den einen Punkt aus `_firstFix` — als Punkt ein Pünktchen
// unter dem Fadenkreuz, als Linie gar nichts, weil `tourTrackPolyline`
// zwei Stützstellen braucht. Genau so gemeldet.
//
// Geprüft wird beides, und das ist Absicht:
//   1. dass der Weg trägt, wenn der Port steht — echter Rundlauf über
//      `IsolateNameServer`, der auf der Dart-VM vollständig läuft;
//   2. dass er NICHT trägt, wenn er fehlt (die Gegenprobe, die den Fehler
//      von 1.103.0 nachstellt);
//   3. dass `main()` ihn anlegt. Ohne den dritten Punkt bliebe die App
//      kaputt, während die ersten beiden grün leuchten — die Zeile in
//      `main.dart` IST der Fix, alles andere war schon da.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/tour/tour_task_handler.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';

/// Derselbe Name, den das Paket intern benutzt — hier nur, um ihn für die
/// Gegenprobe wieder abmelden zu können.
const _portName = 'flutter_foreground_task/isolateComPort';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final point = TourPoint(
    lat: 50.7374,
    lng: 7.0982,
    at: DateTime.utc(2026, 9, 20, 6, 18, 25),
    accuracyM: 5,
  );

  tearDown(() {
    for (final callback in [...FlutterForegroundTask.dataCallbacks]) {
      FlutterForegroundTask.removeTaskDataCallback(callback);
    }
    IsolateNameServer.removePortNameMapping(_portName);
  });

  test('ein gemeldeter Punkt erreicht die Karte, wenn der Port steht',
      () async {
    FlutterForegroundTask.initCommunicationPort();

    final seen = <TourPoint>[];
    FlutterForegroundTask.addTaskDataCallback((data) {
      final decoded = decodeTourTick(data);
      if (decoded != null) seen.add(decoded);
    });

    FlutterForegroundTask.sendDataToMain(encodeTourTick(point));
    // Ein Port stellt asynchron zu; ein Durchlauf der Ereignisschleife
    // reicht, ein `pumpAndSettle` gibt es hier nicht.
    await Future<void>.delayed(Duration.zero);

    expect(seen, hasLength(1));
    expect(seen.single.lat, point.lat);
    expect(seen.single.lng, point.lng);
    expect(seen.single.at, point.at);
    expect(seen.single.accuracyM, point.accuracyM);
  });

  test('ohne angelegten Port geht die Meldung still verloren', () async {
    // Die Gegenprobe zum Fehler aus 1.103.0: NICHT `initCommunicationPort`
    // rufen. `sendDataToMain` wirft dann nicht — es tut schlicht nichts,
    // und genau diese Stille hat den Fehler vier Wochen getragen.
    final seen = <Object>[];
    FlutterForegroundTask.addTaskDataCallback(seen.add);

    FlutterForegroundTask.sendDataToMain(encodeTourTick(point));
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
  });

  test('main() meldet den Port an, bevor die App läuft', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('initKeepAliveCommunication()'),
        reason: 'ohne diese Zeile meldet die Pilztour ins Leere (#465)');

    // Die Reihenfolge trägt mit: Ein Karten-Screen, der noch vor der
    // Anmeldung `addTaskDataCallback` ruft, hinge sonst an einem Port,
    // den es erst später gibt.
    expect(source.indexOf('initKeepAliveCommunication()'),
        lessThan(source.indexOf('runApp(')),
        reason: 'die Anmeldung gehört vor runApp');
  });
}
