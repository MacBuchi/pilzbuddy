// Der Ausgangskorb im Browser (#386).
//
// **Diese Datei läuft absichtlich ohne `dart:io` und ohne Assets** und
// deshalb auch auf dart2js:
//
//     flutter test --platform chrome test/outbox_idb_test.dart
//
// Auf der Dart-VM übernimmt `newIdbFactoryMemory()` dieselbe
// idb_shim-Implementierung im Arbeitsspeicher; im Browser ist es das
// echte IndexedDB. Beides prüft denselben Code — siehe den Zwilling
// `spot_cache_idb_test.dart`.
//
// Der Unterschied zu jenem ist der Punkt dieser Datei: Der
// Zwischenspeicher ist eine Kopie und darf still scheitern, der Korb
// trägt das ORIGINAL. Deshalb steht hier ein Test, den es dort nicht
// gibt — „append wirft".
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:pilzbuddy/data/browser_db.dart';
import 'package:pilzbuddy/data/browser_storage.dart';
import 'package:pilzbuddy/data/idb_factory.dart';
import 'package:pilzbuddy/data/outbox.dart';
import 'package:pilzbuddy/data/outbox_idb.dart';
import 'package:pilzbuddy/data/spot_repository.dart';
import 'package:pilzbuddy/models/find_position.dart';

import 'fakes/broken_idb_factory.dart';

NewSpotJob spotJob({String id = 'job-1'}) => NewSpotJob(
      id: id,
      createdAt: DateTime.utc(2026, 9, 3, 9),
      lat: 51.1,
      lng: 10.4,
      name: 'Buchenhang',
      finds: [
        NewFind(
          species: 'Steinpilz',
          count: 3,
          foundOn: DateTime.utc(2026, 9, 3),
          clientId: '$id-f1',
          // Die eigene Fundstelle aus #373 — der Korb legt sie mit ab,
          // sonst wäre sie beim Nachsenden weg.
          position: const FindPosition.gps(
              lat: 51.1002, lng: 10.4003, accuracy: 8),
        ),
        NewFind.blank(foundOn: DateTime.utc(2026, 9, 3), clientId: '$id-f2'),
      ],
    );

NewFindsJob findsJob({String id = 'job-2', bool spotIsPending = false}) =>
    NewFindsJob(
      id: id,
      createdAt: DateTime.utc(2026, 9, 3, 10),
      spotId: spotIsPending ? 'job-1' : 'spot-7',
      spotIsPending: spotIsPending,
      finds: [
        NewFind(
            species: 'Maronenröhrling',
            count: 1,
            foundOn: DateTime.utc(2026, 9, 3),
            clientId: '$id-f1'),
      ],
    );

void main() {
  late IdbFactory factory;
  late Outbox outbox;

  setUp(() async {
    // Im Browser der echte Speicher, sonst der im Arbeitsspeicher.
    factory = browserIdbFactory() ?? newIdbFactoryMemory();
    // Auf dart2js überlebt die Datenbank den vorigen Test.
    await factory.deleteDatabase(kBrowserDbName);
    outbox = IndexedDbOutbox(BrowserDb(factory));
  });

  test('Ein abgelegter Auftrag kommt vollständig zurück', () async {
    await outbox.append(spotJob(), uid: 'u1');

    final jobs = await outbox.read(uid: 'u1');
    expect(jobs.length, 1);
    final job = jobs.single as NewSpotJob;
    expect(job.id, 'job-1');
    expect(job.lat, 51.1);
    expect(job.finds.length, 2);
    expect(job.finds.first.clientId, 'job-1-f1',
        reason: 'Ohne die client_id wäre der Wiederholversuch nicht mehr '
            'derselbe Auftrag — genau davor schützt Patch 016.');
    expect(job.finds.first.position?.accuracyM, 8);
    expect(job.finds.last.blank, isTrue);
  });

  test('Ein Fund an einem noch wartenden Spot behält seinen Anker',
      () async {
    await outbox.append(spotJob(), uid: 'u1');
    await outbox.append(findsJob(spotIsPending: true), uid: 'u1');

    final jobs = await outbox.read(uid: 'u1');
    final finds = jobs.last as NewFindsJob;
    expect(finds.spotIsPending, isTrue);
    expect(finds.spotId, 'job-1',
        reason: 'Solange der Spot selbst wartet, ist seine „id" die '
            'Kennung des Auftrags.');
  });

  test('Leerer Korb ist eine leere Liste, kein Fehler', () async {
    expect(await outbox.read(uid: 'u1'), isEmpty);
  });

  test('Ein fremdes Konto sieht die Aufträge nicht', () async {
    await outbox.append(spotJob(), uid: 'u1');

    expect(await outbox.read(uid: 'u2'), isEmpty,
        reason: 'Sonst trügen die Fundstellen des einen Kontos in das '
            'andere.');
  });

  test('replaceAll ersetzt vollständig', () async {
    await outbox.append(spotJob(), uid: 'u1');
    await outbox.append(findsJob(), uid: 'u1');

    await outbox.replaceAll([findsJob(id: 'job-9')], uid: 'u1');

    final jobs = await outbox.read(uid: 'u1');
    expect(jobs.single.id, 'job-9');
  });

  test('clear() räumt den Korb', () async {
    await outbox.append(spotJob(), uid: 'u1');
    await outbox.clear();

    expect(await outbox.read(uid: 'u1'), isEmpty);
  });

  test('Die Ablage ist derselbe Text wie in der Datei auf Android',
      () async {
    await outbox.append(spotJob(), uid: 'u1');

    final db = await factory.open(kBrowserDbName, version: kBrowserDbVersion);
    final txn = db.transaction(kOutboxStore, idbModeReadOnly);
    final stored = await txn.objectStore(kOutboxStore).getObject('jobs');
    await txn.completed;
    db.close();

    expect(stored, encodeOutbox([spotJob()], uid: 'u1'),
        reason: 'Eine Abbildung, ein Ergebnis — IndexedDB gäbe Objekte als '
            'Map<String, Object?> zurück.');
  });

  test('Unlesbarer Inhalt ist kein Fehler, sondern kein Korb', () async {
    await outbox.append(spotJob(), uid: 'u1');

    final db = await factory.open(kBrowserDbName, version: kBrowserDbVersion);
    final txn = db.transaction(kOutboxStore, idbModeReadWrite);
    await txn.objectStore(kOutboxStore).put(42, 'jobs');
    await txn.completed;
    db.close();

    expect(await outbox.read(uid: 'u1'), isEmpty);
  });

  group('Der Korb trägt das Original — nicht eine Kopie', () {
    late Outbox broken;

    setUp(() => broken = IndexedDbOutbox(BrowserDb(BrokenIdbFactory())));

    test('append WIRFT, wenn der Auftrag nicht unterkommt', () {
      // Der Unterschied zum Zwischenspeicher, in einem Test statt nur im
      // Kommentar: Schluckte append den Fehler, meldete die App
      // „gespeichert" über einen Fund, der nirgends liegt.
      expect(broken.append(spotJob(), uid: 'u1'), throwsA(isA<Object>()));
    });

    test('replaceAll wirft ebenfalls', () {
      // Die Wiedervorlage muss von einem Fehlschlag erfahren — sonst
      // gälte ein Auftrag als erledigt, der noch offen ist.
      expect(broken.replaceAll([spotJob()], uid: 'u1'),
          throwsA(isA<Object>()));
    });

    test('read und clear werfen nie', () async {
      await expectLater(broken.read(uid: 'u1'), completion(isEmpty));
      await expectLater(broken.clear(), completes);
    });
  });

  test('Außerhalb des Browsers verfällt nichts', () async {
    // Der Stub sagt `true`, und das ist eine Entscheidung: Ein Warnhinweis
    // über ein Dateisystem wäre schlicht falsch, und die Fehlerrichtung
    // „warnt, wo nichts ist" verbraucht genau die Aufmerksamkeit, die der
    // echte Fall braucht. Im Browser gilt dagegen die echte Antwort — die
    // hängt vom Hersteller ab und wird hier nicht behauptet.
    if (browserIdbFactory() != null) return;
    expect(await isStorageDurable(), isTrue);
  });

  test('Unter --platform chrome läuft der ECHTE Browser-Speicher', () {
    final browser = browserIdbFactory();
    // Dart-VM: kein Browser, also kein Beleg — siehe
    // spot_cache_idb_test.dart.
    if (browser == null) return;
    expect(browser.persistent, isTrue,
        reason: 'Ein stiller Rückfall auf die Speicher-Fassung sähe genauso '
            'aus wie ein bestandener Lauf.');
  });

  group('Welcher Korb zu welcher Plattform gehört', () {
    test('Android: die Datei', () {
      expect(chooseOutbox(web: false, db: BrowserDb(newIdbFactoryMemory())),
          isA<FileOutbox>());
    });

    test('Browser mit IndexedDB: der neue Weg', () {
      expect(chooseOutbox(web: true, db: BrowserDb(newIdbFactoryMemory())),
          isA<IndexedDbOutbox>());
    });

    test('Browser ohne IndexedDB: gar keiner, und der wirft', () async {
      final none = chooseOutbox(web: true, db: null);
      expect(none, isA<NoOutbox>());
      // Kein Ort für das Original heißt: sichtbar scheitern.
      await expectLater(
          none.append(spotJob(), uid: 'u1'), throwsA(isA<OutboxUnavailable>()));
    });
  });
}
