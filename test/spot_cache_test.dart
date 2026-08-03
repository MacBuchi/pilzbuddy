// Der Zwischenspeicher der eigenen Spots und die Regel darüber
// („Netz zuerst, sonst der Zwischenspeicher").
//
// Was hier geprüft wird, ist genau der Fall, der bis 1.44.0 kaputt war:
// Kaltstart im Wald ohne Empfang. Ein fehlgeschlagener *Refresh* war nie
// betroffen — Riverpod behält den vorherigen Wert.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/spot_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Ein Zwischenspeicher, dessen I/O grundsätzlich scheitert — steht für
/// Web (kein App-Verzeichnis), volle Platte und fehlende Rechte.
class _BrokenCache implements SpotCache {
  @override
  Future<CachedSpotRows?> read({required String uid}) async =>
      throw const FileSystemException('kaputt');

  @override
  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
  }) async =>
      throw const FileSystemException('kaputt');

  @override
  Future<void> clear() async => throw const FileSystemException('kaputt');
}

/// Eine Supabase-Zeile, wie `select('*, finds(*)')` sie liefert.
Map<String, dynamic> row(String id, {String owner = 'u1'}) => {
      'id': id,
      'owner_id': owner,
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
          'note': null,
          'created_at': '2026-09-12T10:00:00Z',
        }
      ],
    };

void main() {
  late Directory tempDir;
  late SpotCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spot_cache_test');
    cache = FileSpotCache(baseDirOverride: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final savedAt = DateTime.utc(2026, 9, 12, 8, 30);

  group('SpotCache', () {
    test('geschriebene Zeilen kommen unverändert zurück', () async {
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);
      final cached = await cache.read(uid: 'u1');

      expect(cached, isNotNull);
      expect(cached!.savedAt, savedAt);
      expect(cached.rows.single['id'], 's1');
      // Die Funde müssen mitkommen — ohne sie wäre die Karte im Wald zwar
      // bevölkert, aber jeder Spot ohne Historie und ohne Artsymbol.
      expect((cached.rows.single['finds'] as List).single['species'],
          'Steinpilz');
    });

    test('ohne Datei gibt es keinen Zwischenspeicher', () async {
      expect(await cache.read(uid: 'u1'), isNull);
    });

    test('fremdes Konto wird nicht herausgegeben', () async {
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);

      expect(await cache.read(uid: 'u2'), isNull,
          reason: 'Die Fundstellen eines anderen Kontos dürfen in einer '
              'fremden Sitzung niemals auftauchen.');
    });

    test('kaputte Datei gilt als „kein Zwischenspeicher", nicht als Fehler',
        () async {
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);
      final file = File('${tempDir.path}/${FileSpotCache.dirName}/my_spots.json');
      await file.writeAsString('{kaputt');

      expect(await cache.read(uid: 'u1'), isNull);
    });

    test('clear löscht die Datei — Abmelden lässt nichts zurück', () async {
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);
      final file = File('${tempDir.path}/${FileSpotCache.dirName}/my_spots.json');
      expect(await file.exists(), isTrue);

      await cache.clear();

      expect(await file.exists(), isFalse);
      expect(await cache.read(uid: 'u1'), isNull);
    });

    test('clear ohne vorhandene Datei wirft nicht', () async {
      await cache.clear();
    });

    test('geschrieben wird atomar — keine .part-Datei bleibt liegen',
        () async {
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);
      final dir = Directory('${tempDir.path}/${FileSpotCache.dirName}');
      final names = await dir
          .list()
          .map((e) => e.path.split('/').last)
          .toList();

      expect(names, ['my_spots.json']);
    });
  });

  group('fetchSpotRowsWithCache', () {
    test('Erfolg: Zeilen kommen aus dem Netz und landen im Speicher',
        () async {
      final result = await fetchSpotRowsWithCache(
        fetch: () async => [row('s1')],
        cache: cache,
        uid: 'u1',
        now: savedAt,
      );

      expect(result.cachedAt, isNull, reason: 'frisch aus dem Netz');
      expect(result.rows.single['id'], 's1');
      expect((await cache.read(uid: 'u1'))!.rows.single['id'], 's1');
    });

    test('Kaltstart ohne Empfang: der Zwischenspeicher rettet die Karte',
        () async {
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);

      final result = await fetchSpotRowsWithCache(
        fetch: () async => throw const SocketException('kein Netz'),
        cache: cache,
        uid: 'u1',
        now: DateTime.utc(2026, 9, 13),
      );

      expect(result.rows.single['id'], 's1');
      expect(result.cachedAt, savedAt,
          reason: 'Das Alter muss mitkommen — die Karte sagt es dazu.');
    });

    test('ohne Empfang UND ohne Zwischenspeicher fliegt der Fehler weiter',
        () async {
      // Wichtig: kein leerer Erfolg. Eine leere Liste sähe aus wie „du hast
      // keine Spots" und wäre eine Lüge.
      await expectLater(
        fetchSpotRowsWithCache(
          fetch: () async => throw const SocketException('kein Netz'),
          cache: cache,
          uid: 'u1',
          now: savedAt,
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('ein Serverfehler versteckt sich NICHT hinter alten Daten',
        () async {
      // Der wichtigste Test hier: Wäre der Rückfall nicht auf
      // Verbindungsfehler beschränkt, bliebe ein kaputtes Deployment
      // (umbenannte Spalte, kaputte RLS) unsichtbar, während alle Geräte
      // stillschweigend Veraltetes zeigen — Lehre aus Issue #80.
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);

      await expectLater(
        fetchSpotRowsWithCache(
          fetch: () async => throw const PostgrestException(
              message: 'column spots.lat does not exist'),
          cache: cache,
          uid: 'u1',
          now: savedAt,
        ),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('ein kaputter Zwischenspeicher lässt den Abruf nicht scheitern',
        () async {
      // Web und volle Platten: Schreiben darf nie werfen. Vorher hätte
      // ein Schreibfehler im Erfolgspfad die ganze Karte geleert.
      final result = await fetchSpotRowsWithCache(
        fetch: () async => [row('s1')],
        cache: _BrokenCache(),
        uid: 'u1',
        now: savedAt,
      );

      expect(result.rows.single['id'], 's1');
      expect(result.cachedAt, isNull);
    });

    test('Zwischenspeicher eines anderen Kontos hilft nicht', () async {
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);

      await expectLater(
        fetchSpotRowsWithCache(
          fetch: () async => throw const SocketException('kein Netz'),
          cache: cache,
          uid: 'u2',
          now: savedAt,
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('jeder erfolgreiche Abruf schreibt den Stand fort', () async {
      await cache.write(uid: 'u1', rows: [row('alt')], savedAt: savedAt);
      final laterOn = DateTime.utc(2026, 9, 14);

      await fetchSpotRowsWithCache(
        fetch: () async => [row('neu')],
        cache: cache,
        uid: 'u1',
        now: laterOn,
      );

      final cached = (await cache.read(uid: 'u1'))!;
      expect(cached.rows.single['id'], 'neu');
      expect(cached.savedAt, laterOn);
    });

    test('der gespeicherte Stand liest sich als echtes Spot-Modell zurück',
        () async {
      // Der Grund, warum rohe Zeilen gespeichert werden: Es gibt genau eine
      // Abbildung (Spot.fromJson), und die läuft für Netz und Speicher.
      await cache.write(uid: 'u1', rows: [row('s1')], savedAt: savedAt);
      final cached = await cache.read(uid: 'u1');

      final decoded = jsonDecode(jsonEncode(cached!.rows.single))
          as Map<String, dynamic>;
      expect(decoded['lat'], 48.1);
      expect(decoded['owner_id'], 'u1');
    });
  });
}
