// Der Zwischenspeicher der eigenen Spots im Browser (#385).
//
// **Diese Datei läuft absichtlich ohne `dart:io` und ohne Assets.** Damit
// ist sie die erste im Projekt, die sich auch auf dart2js ausführen
// lässt:
//
//     flutter test --platform chrome test/spot_cache_idb_test.dart
//
// Auf der Dart-VM (dem Normalfall, `flutter test`) gibt es keinen
// Browser; dann übernimmt `newIdbFactoryMemory()` dieselbe
// idb_shim-Implementierung im Arbeitsspeicher. Der Test prüft also auf
// beiden Wegen denselben Code — auf dem einen die Logik, auf dem anderen
// zusätzlich die echte Verdrahtung mit dem IndexedDB des Browsers.
//
// Was er NICHT beweist, solange er auf der VM läuft: dass der
// Browser-Zugang selbst funktioniert. `kIsWeb` ist dort immer falsch
// (siehe CLAUDE.md, „Kein Test läuft auf dart2js").
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:pilzbuddy/data/browser_db.dart';
import 'package:pilzbuddy/data/idb_factory.dart';
import 'package:pilzbuddy/data/spot_cache.dart';
import 'package:pilzbuddy/data/spot_cache_idb.dart';

import 'fakes/broken_idb_factory.dart';

/// Eine Supabase-Zeile, wie `select('*, finds(*)')` sie liefert.
Map<String, dynamic> row(String id) => {
      'id': id,
      'owner_id': 'u1',
      'name': 'Buchenhang',
      'lat': 48.1,
      'lng': 11.5,
      'sharing_excluded': false,
      'finds': [
        {
          'id': 'f-$id',
          'spot_id': id,
          'species': 'Steinpilz',
          'count': 3,
          'found_on': '2026-09-12',
          // Die Spalten aus #373 — der Zwischenspeicher legt ROHE Zeilen
          // ab und weiß von ihnen nichts. Genau das soll so bleiben.
          'lat': 48.1001,
          'lng': 11.5002,
          'accuracy_m': 8.0,
        }
      ],
    };

void main() {
  late IdbFactory factory;
  late SpotCache cache;
  final rows = [row('s1'), row('s2')];
  final savedAt = DateTime.utc(2026, 9, 12, 8, 30);

  setUp(() async {
    // Im Browser der echte Speicher, sonst der im Arbeitsspeicher.
    factory = browserIdbFactory() ?? newIdbFactoryMemory();
    // Auf dart2js überlebt die Datenbank den vorigen Test — sonst prüfte
    // „leerer Speicher liefert null" dort nie, was es soll.
    await factory.deleteDatabase(kBrowserDbName);
    cache = IndexedDbSpotCache(BrowserDb(factory));
  });

  test('Geschriebenes kommt unverändert zurück', () async {
    await cache.write(uid: 'u1', rows: rows, savedAt: savedAt);

    final cached = await cache.read(uid: 'u1');
    expect(cached, isNotNull);
    expect(cached!.savedAt, savedAt);
    expect(cached.rows.length, 2);
    expect(cached.rows.first['name'], 'Buchenhang');
    // Der Weg durch JSON darf die verschachtelten Zeilen nicht in einen
    // Typ verwandeln, den `Spot.fromJson` nicht mehr annimmt.
    final finds = cached.rows.first['finds'] as List<dynamic>;
    expect((finds.first as Map<String, dynamic>)['accuracy_m'], 8.0);
  });

  test('Leerer Speicher liefert null, nicht eine leere Liste', () async {
    expect(await cache.read(uid: 'u1'), isNull);
  });

  test('Ein fremdes Konto sieht die Spots nicht', () async {
    await cache.write(uid: 'u1', rows: rows, savedAt: savedAt);

    expect(await cache.read(uid: 'u2'), isNull,
        reason: 'Die Spots eines anderen Nutzers dürfen in einer fremden '
            'Sitzung niemals auftauchen.');
  });

  test('Der nächste Abruf überschreibt den vorigen Stand', () async {
    await cache.write(uid: 'u1', rows: rows, savedAt: savedAt);
    await cache.write(
        uid: 'u2', rows: [row('s9')], savedAt: savedAt.add(const Duration(days: 1)));

    expect(await cache.read(uid: 'u1'), isNull,
        reason: 'Ein fester Schlüssel statt einer je Konto — sonst blieben '
            'die Spots jedes früher angemeldeten Kontos im Browser liegen.');
    expect((await cache.read(uid: 'u2'))!.rows.single['id'], 's9');
  });

  test('clear() räumt den Speicher', () async {
    await cache.write(uid: 'u1', rows: rows, savedAt: savedAt);
    await cache.clear();

    expect(await cache.read(uid: 'u1'), isNull);
  });

  test('Die Ablage ist derselbe Text wie in der Datei auf Android',
      () async {
    await cache.write(uid: 'u1', rows: rows, savedAt: savedAt);

    final db =
        await factory.open(kBrowserDbName, version: kBrowserDbVersion);
    final txn = db.transaction(kSpotCacheStore, idbModeReadOnly);
    final stored = await txn.objectStore(kSpotCacheStore).getObject('my_spots');
    await txn.completed;
    db.close();

    expect(stored, encodeSpotCache(uid: 'u1', rows: rows, savedAt: savedAt),
        reason: 'Eine Abbildung, ein Ergebnis: IndexedDB nähme auch Objekte, '
            'gäbe sie aber als Map<String, Object?> zurück — und darauf ist '
            'Map<String, dynamic> nicht zuweisbar.');
  });

  test('Unlesbarer Inhalt ist kein Fehler, sondern kein Zwischenspeicher',
      () async {
    await cache.write(uid: 'u1', rows: rows, savedAt: savedAt);

    final db =
        await factory.open(kBrowserDbName, version: kBrowserDbVersion);
    final txn = db.transaction(kSpotCacheStore, idbModeReadWrite);
    await txn.objectStore(kSpotCacheStore).put(42, 'my_spots');
    await txn.completed;
    db.close();

    expect(await cache.read(uid: 'u1'), isNull);
  });

  test('Ein kaputter Zugang wirft nie', () async {
    final broken = IndexedDbSpotCache(BrowserDb(BrokenIdbFactory()));

    // Alle drei Methoden sind total (siehe SpotCache): Ein erfolgreicher
    // Abruf darf nicht daran scheitern, dass sich die Kopie nicht ablegen
    // lässt — und das Abmelden nicht daran, dass sie sich nicht löschen
    // lässt.
    await expectLater(
        broken.write(uid: 'u1', rows: rows, savedAt: savedAt), completes);
    await expectLater(broken.read(uid: 'u1'), completion(isNull));
    await expectLater(broken.clear(), completes);
  });

  test('Unter --platform chrome läuft der ECHTE Browser-Speicher', () {
    final browser = browserIdbFactory();
    if (browser == null) {
      // Dart-VM: Hier gibt es keinen Browser. Das ist kein Fehler — aber
      // eben auch kein Beleg, und deshalb steht die Zusage hier und
      // nicht im Dateikopf.
      return;
    }
    // Ohne diese Prüfung bewiese ein grüner Chrome-Lauf nichts: Ein
    // stiller Rückfall auf die Speicher-Fassung sähe genauso aus. Genau
    // dieser Fehler ist in #383 schon einmal passiert (ein Test, der den
    // Web-Weg zu gehen behauptete und ihn nie ging).
    expect(browser.persistent, isTrue,
        reason: 'Die Speicher-Fassung ist nicht persistent — käme sie hier '
            'heraus, prüfte der ganze Lauf nur sich selbst.');
  });

  group('Welcher Zwischenspeicher zu welcher Plattform gehört', () {
    test('Android: die Datei', () {
      expect(chooseSpotCache(web: false, db: BrowserDb(newIdbFactoryMemory())),
          isA<FileSpotCache>(),
          reason: 'Auf dem Telefon liest FileAt faul und der Backup-'
              'Ausschluss zeigt auf das Verzeichnis.');
    });

    test('Browser mit IndexedDB: der neue Weg', () {
      expect(chooseSpotCache(web: true, db: BrowserDb(newIdbFactoryMemory())),
          isA<IndexedDbSpotCache>());
    });

    test('Browser ohne IndexedDB: gar keiner', () {
      expect(chooseSpotCache(web: true, db: null), isA<NoSpotCache>(),
          reason: 'Ehrlicher als eine Ablage, die jeden Neustart vergisst.');
    });
  });
}
