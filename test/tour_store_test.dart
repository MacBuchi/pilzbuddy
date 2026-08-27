// Die Tour auf der Platte (#338).
//
// Gegen ein Temp-Verzeichnis, kein Netz. Was hier geprüft wird, ist der
// Unterschied zwischen „drei Stunden Gehen sind gesichert" und „drei
// Stunden Gehen sind weg" — und dass ein Prozess-Kill mitten im Schreiben
// höchstens den letzten Fix kostet, nicht die Tour.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/tour/tour_store.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tours_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  final start = DateTime.utc(2026, 8, 27, 9);

  TourPoint point(int i) => TourPoint(
        lat: 51 + i / 100000,
        lng: 11,
        at: start.add(Duration(seconds: i * 15)),
        accuracyM: 8,
      );

  File fileIn(Directory d) =>
      File('${d.path}/${FileTourStore.dirName}/active.jsonl');

  test('Punkte überstehen Schreiben und Lesen unverändert', () async {
    final store = FileTourStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    for (var i = 0; i < 3; i++) {
      await store.appendPoint(point(i));
    }

    // Bewusst eine FRISCHE Instanz: Der Neustart der App ist der Fall,
    // für den es die Datei gibt.
    final tour = await FileTourStore(baseDir: dir).read(uid: 'me');
    expect(tour, isNotNull);
    expect(tour!.startedAt, start);
    expect(tour.points, hasLength(3));
    expect(tour.points[2].lat, closeTo(point(2).lat, 1e-9));
    expect(tour.points[2].at, point(2).at);
    expect(tour.points[2].accuracyM, 8);
  });

  test('eine abgeschnittene letzte Zeile kostet einen Fix, nicht die Tour',
      () async {
    // Der Normalfall nach einem Speicher-Kill (#147): Android beendet den
    // Prozess mitten im Anhängen. Genau dafür ist das Format
    // zeilenweise — beim Ausgangskorb wäre derselbe Abbruch eine halbe
    // Datei, deshalb steht dort `.part` + `rename`.
    final store = FileTourStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    for (var i = 0; i < 3; i++) {
      await store.appendPoint(point(i));
    }
    final file = fileIn(dir);
    await file.writeAsString('${await file.readAsString()}{"lat":51.0,"ln');

    final tour = await FileTourStore(baseDir: dir).read(uid: 'me');
    expect(tour!.points, hasLength(3));
  });

  test('eine Zeile ohne Zeitstempel fällt weg, der Rest bleibt', () async {
    final store = FileTourStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    await store.appendPoint(point(0));
    final file = fileIn(dir);
    await file.writeAsString(
        '${await file.readAsString()}{"lat":51.0,"lng":11.0}\n');
    await store.appendPoint(point(2));

    final tour = await FileTourStore(baseDir: dir).read(uid: 'me');
    expect(tour!.points, hasLength(2));
    expect(tour.points.last.at, point(2).at);
  });

  test('die Tour eines fremden Kontos wird nicht gelesen', () async {
    // Sonst würden aus dem Weg eines anderen Nutzers Leergänge im
    // eigenen Konto — dieselbe Regel wie im Ausgangskorb.
    final store = FileTourStore(baseDir: dir);
    await store.begin(uid: 'jemand-anderes', startedAt: start);
    await store.appendPoint(point(0));

    expect(await FileTourStore(baseDir: dir).read(uid: 'me'), isNull);
  });

  test('begin verwirft, was vorher dalag', () async {
    final store = FileTourStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    await store.appendPoint(point(0));
    await store.begin(
        uid: 'me', startedAt: start.add(const Duration(days: 1)));

    final tour = await store.read(uid: 'me');
    expect(tour!.points, isEmpty);
    expect(tour.startedAt, start.add(const Duration(days: 1)));
  });

  test('ohne Datei gibt es keine Tour', () async {
    expect(await FileTourStore(baseDir: dir).read(uid: 'me'), isNull);
  });

  test('eine unlesbare Datei ist keine Tour und kein Fehler', () async {
    final file = fileIn(dir);
    await file.parent.create(recursive: true);
    await file.writeAsString('kein JSON\nauch nicht\n');
    expect(await FileTourStore(baseDir: dir).read(uid: 'me'), isNull);
  });

  test('clear löscht, und danach ist nichts mehr da', () async {
    final store = FileTourStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    await store.appendPoint(point(0));
    await store.clear();
    expect(await store.read(uid: 'me'), isNull);
    expect(await fileIn(dir).exists(), isFalse);
  });

  test('clear auf nichts wirft nicht', () async {
    await FileTourStore(baseDir: dir).clear();
  });

  test('ein Schreibfehler beendet die Tour nicht', () async {
    // Voller Speicher, entzogene Rechte: Ein verlorener Fix ist ein
    // verlorener Fix. Die Tour bricht deswegen nicht ab — sonst stünde
    // man im Wald und die Aufzeichnung wäre still zu Ende.
    final store = FileTourStore(baseDir: File('/dev/null/geht-nicht')
        .parent // ein Pfad, unter dem sich kein Verzeichnis anlegen lässt
        );
    await store.appendPoint(point(0));
  });

  test('begin dagegen wirft — eine Tour, die nicht aufzeichnen kann, '
      'darf nicht starten', () async {
    final store = FileTourStore(baseDir: File('/dev/null/geht-nicht').parent);
    await expectLater(
        store.begin(uid: 'me', startedAt: start), throwsA(anything));
  });
}
