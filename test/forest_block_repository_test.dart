// Der Download-Kanal der feinen Waldstufe (#253): Katalog-Cache,
// Prüfsummen-Kontrolle auf JEDEM Weg (Netz wie Platte), Aufräumen.
//
// Gegen einen MockClient und ein Temp-Verzeichnis — kein Netz, keine
// echten Pfade; dieselbe Bauart wie die Fakes des Harness.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pilzbuddy/data/forest_block_repository.dart';

import 'forest_grid_test.dart' show encodeForest;

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('forest_repo_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  final payload = encodeForest([
    [11, 96],
    [51, 0],
  ]);

  Map<String, dynamic> catalogJson() => {
        'reference_year': 2024,
        'lattice': 'hex-odd-r',
        'hex_lon_step': 0.004,
        'hex_lat_step': 0.003,
        'blocks': [
          {
            'file': 'forest_block_x0_y0.bin.gz',
            'width': 2,
            'height': 2,
            'west': 10.0,
            'north': 50.0,
            'east': 10.0 + 0.004 * 2.5,
            'south': 50.0 - 0.003 * 3,
            'bytes': payload.length,
            'sha256': sha256.convert(payload).toString(),
          },
        ],
      };

  /// Ein Client, der Katalog und Block ausliefert und mitzählt.
  MockClient serving({List<int>? blockBytes, List<String>? log}) =>
      MockClient((request) async {
        log?.add(request.url.path.split('/').last);
        if (request.url.path.endsWith('forest_blocks.json')) {
          return http.Response(jsonEncode(catalogJson()), 200);
        }
        if (request.url.path.endsWith('forest_block_x0_y0.bin.gz')) {
          return http.Response.bytes(blockBytes ?? payload, 200);
        }
        return http.Response('not found', 404);
      });

  MockClient dead() => MockClient((_) async => throw const SocketException(
      'kein Netz — der Waldparkplatz eben'));

  test('Katalog: frisch vom Netz, danach auch ohne Empfang von Platte',
      () async {
    final online =
        ForestBlockRepository(client: serving(), baseDirOverride: dir);
    final catalog = await online.loadCatalog();
    expect(catalog, isNotNull);
    expect(catalog!.blocks, hasLength(1));

    final offline =
        ForestBlockRepository(client: dead(), baseDirOverride: dir);
    final cached = await offline.loadCatalog();
    expect(cached, isNotNull,
        reason: 'der letzte Stand liegt als blocks.json daneben');
    expect(cached!.blocks.single.sha256, catalog.blocks.single.sha256);
  });

  test('ohne je gesehenen Katalog gibt es nichts — still', () async {
    final offline =
        ForestBlockRepository(client: dead(), baseDirOverride: dir);
    expect(await offline.loadCatalog(), isNull);
  });

  test('ein manipulierter Download wird verworfen und vergiftet nichts',
      () async {
    // Gleiche Länge, ein gekipptes Byte: Die Längenprüfung allein
    // ließe das durch — erst die Prüfsumme fängt es.
    final tampered = [...payload];
    tampered[tampered.length - 1] ^= 0xFF;

    final bad = ForestBlockRepository(
        client: serving(blockBytes: tampered), baseDirOverride: dir);
    final catalog = (await bad.loadCatalog())!;
    expect(await bad.loadBlock(catalog, catalog.blocks.single), isNull);
    expect(
        File('${dir.path}/forest/forest_block_x0_y0.bin.gz').existsSync(),
        isFalse,
        reason: 'die kaputte Datei darf nicht liegen bleiben');

    // Nächster Versuch mit heiler Quelle: lädt, prüft, liefert.
    final good =
        ForestBlockRepository(client: serving(), baseDirOverride: dir);
    final grid = await good.loadBlock(catalog, catalog.blocks.single);
    expect(grid, isNotNull);
    expect(grid!.byteAt(0, 0), 11);
    expect(grid.byteAt(1, 1), 0);
    expect(grid.isHex, isTrue);
  });

  test('einmal geladen heißt: ohne Netz von Platte', () async {
    final online =
        ForestBlockRepository(client: serving(), baseDirOverride: dir);
    final catalog = (await online.loadCatalog())!;
    expect(await online.loadBlock(catalog, catalog.blocks.single), isNotNull);

    // Frische Instanz (kein Speicher-Cache), totes Netz: Die Datei auf
    // Platte trägt — genau der Wald-ohne-Empfang-Fall.
    final offline =
        ForestBlockRepository(client: dead(), baseDirOverride: dir);
    final grid = await offline.loadBlock(catalog, catalog.blocks.single);
    expect(grid, isNotNull);
    expect(grid!.byteAt(1, 0), 96, reason: 'byteAt(x, y): Spalte 1, Zeile 0');
  });

  test('ein alter Platten-Stand unter neuem Katalog wird ersetzt', () async {
    // Der Tag wird überschrieben: gleicher Dateiname, anderer Inhalt.
    // Die Prüfsumme aus dem Katalog ist die Invalidierung.
    final file = File('${dir.path}/forest/forest_block_x0_y0.bin.gz');
    file.createSync(recursive: true);
    file.writeAsBytesSync(encodeForest([
      [1, 1],
      [1, 1],
    ]));

    final repo =
        ForestBlockRepository(client: serving(), baseDirOverride: dir);
    final catalog = (await repo.loadCatalog())!;
    final grid = await repo.loadBlock(catalog, catalog.blocks.single);
    expect(grid!.byteAt(0, 0), 11, reason: 'der frische Stand, nicht der alte');
    expect(sha256.convert(file.readAsBytesSync()).toString(),
        catalog.blocks.single.sha256);
  });

  test('ein frischer Katalog räumt Blöcke weg, die er nicht mehr führt',
      () async {
    final stale = File('${dir.path}/forest/forest_block_x9_y9.bin.gz');
    stale.createSync(recursive: true);
    stale.writeAsBytesSync([1, 2, 3]);

    final repo =
        ForestBlockRepository(client: serving(), baseDirOverride: dir);
    await repo.loadCatalog();
    expect(stale.existsSync(), isFalse);
    expect(File('${dir.path}/forest/blocks.json').existsSync(), isTrue,
        reason: 'der Katalog-Cache trägt keinen Block-Namen und bleibt');
  });

  test('ein Katalog in unbekanntem Gitterformat zählt nicht', () async {
    final client = MockClient((request) async => http.Response(
        jsonEncode({...catalogJson(), 'lattice': 'square'}), 200));
    final repo = ForestBlockRepository(client: client, baseDirOverride: dir);
    expect(await repo.loadCatalog(), isNull);
  });

  // Der Vorlauf (#264): alles am Stück holen, statt auf Bedarf. Zwei
  // Blöcke UNTERSCHIEDLICHER Größe, weil der Fortschritt in Bytes zählt
  // — mit gleich großen Blöcken sähe eine Blockzählung genauso aus.
  group('Vorlauf', () {
    final small = encodeForest([
      [11, 96],
      [51, 0],
    ]);
    final large = encodeForest([
      [11, 96, 51, 0, 11, 96, 51, 0],
      [51, 0, 11, 96, 51, 0, 11, 96],
    ]);

    Map<String, dynamic> twoBlocks() => {
          'reference_year': 2024,
          'lattice': 'hex-odd-r',
          'hex_lon_step': 0.004,
          'hex_lat_step': 0.003,
          'blocks': [
            {
              'file': 'forest_block_x0_y0.bin.gz',
              'width': 2,
              'height': 2,
              'west': 10.0,
              'north': 50.0,
              'east': 10.0 + 0.004 * 2.5,
              'south': 50.0 - 0.003 * 3,
              'bytes': small.length,
              'sha256': sha256.convert(small).toString(),
            },
            {
              'file': 'forest_block_x2_y0.bin.gz',
              'width': 8,
              'height': 2,
              'west': 10.0 + 0.004 * 2,
              'north': 50.0,
              'east': 10.0 + 0.004 * 10.5,
              'south': 50.0 - 0.003 * 3,
              'bytes': large.length,
              'sha256': sha256.convert(large).toString(),
            },
          ],
        };

    MockClient servingBoth({List<String>? log, Set<String> missing = const {}}) =>
        MockClient((request) async {
          final name = request.url.path.split('/').last;
          log?.add(name);
          if (name == 'forest_blocks.json') {
            return http.Response(jsonEncode(twoBlocks()), 200);
          }
          if (missing.contains(name)) return http.Response('weg', 404);
          if (name == 'forest_block_x0_y0.bin.gz') {
            return http.Response.bytes(small, 200);
          }
          if (name == 'forest_block_x2_y0.bin.gz') {
            return http.Response.bytes(large, 200);
          }
          return http.Response('not found', 404);
        });

    test('holt alles und zählt dabei bis eins', () async {
      final log = <String>[];
      final repo = ForestBlockRepository(
          client: servingBoth(log: log), baseDirOverride: dir);
      final catalog = (await repo.loadCatalog())!;

      final steps = await repo.downloadAll(catalog).toList();
      expect(steps.first, 0.0, reason: 'nichts da: der Balken fängt bei null an');
      expect(steps.last, 1.0);
      expect(steps, orderedEquals([...steps]..sort()),
          reason: 'ein Fortschritt läuft vorwärts');
      expect(log.where((n) => n.startsWith('forest_block_')), hasLength(2));

      final onDisk = await repo.installedOf(catalog);
      expect(onDisk.blocks, 2);
      expect(onDisk.bytes, small.length + large.length);
    });

    test('was schon daliegt, wird nicht erneut geholt', () async {
      // Erst den kleinen Block auf dem normalen Weg holen …
      final first =
          ForestBlockRepository(client: servingBoth(), baseDirOverride: dir);
      final catalog = (await first.loadCatalog())!;
      await first.loadBlock(catalog, catalog.blocks.first);

      // … dann den Vorlauf: er darf nur noch den großen anfassen.
      final log = <String>[];
      final repo = ForestBlockRepository(
          client: servingBoth(log: log), baseDirOverride: dir);
      final steps = await repo.downloadAll(catalog).toList();

      expect(log, isNot(contains('forest_block_x0_y0.bin.gz')));
      expect(log, contains('forest_block_x2_y0.bin.gz'));
      expect(steps.first, greaterThan(0),
          reason: 'der Balken setzt dort auf, wo er stand');
      expect(steps.last, 1.0);
    });

    test('ein fehlender Block wirft — und behält, was schon da ist',
        () async {
      final repo = ForestBlockRepository(
          client: servingBoth(missing: {'forest_block_x2_y0.bin.gz'}),
          baseDirOverride: dir);
      final catalog = (await repo.loadCatalog())!;

      await expectLater(repo.downloadAll(catalog).toList(),
          throwsA(isA<ForestBlockDownloadFailed>()));
      expect(
          File('${dir.path}/forest/forest_block_x0_y0.bin.gz').existsSync(),
          isTrue,
          reason: 'der Wiederanlauf soll den kleinen überspringen dürfen');
      expect((await repo.installedOf(catalog)).blocks, 1);
    });

    test('Abbruch hält an, ohne zu werfen', () async {
      final repo =
          ForestBlockRepository(client: servingBoth(), baseDirOverride: dir);
      final catalog = (await repo.loadCatalog())!;

      var seen = 0;
      final steps = await repo
          .downloadAll(catalog, isCancelled: () => seen > 0)
          .map((p) {
        seen++;
        return p;
      }).toList();

      expect(steps.last, lessThan(1.0));
      expect((await repo.installedOf(catalog)).blocks, lessThan(2));
    });

    test('Löschen räumt die Blöcke weg, der Katalog-Cache bleibt', () async {
      final repo =
          ForestBlockRepository(client: servingBoth(), baseDirOverride: dir);
      final catalog = (await repo.loadCatalog())!;
      await repo.downloadAll(catalog).drain<void>();

      final freed = await repo.deleteBlocks();
      expect(freed, small.length + large.length);
      expect((await repo.installedOf(catalog)).blocks, 0);
      expect(File('${dir.path}/forest/blocks.json').existsSync(), isTrue,
          reason: 'ohne ihn wäre die Kachel ohne Empfang stumm');
    });

    test('Löschen leert auch den Speicher — sonst lebt der Block weiter',
        () async {
      // Der Block muss DERSELBEN Instanz einmal durch die Hände gegangen
      // sein (dann liegt er dekodiert im Speicher), und die Quelle muss
      // danach schweigen — sonst holte ein zweiter Aufruf ihn schlicht
      // neu und der Test bewiese nichts.
      var alive = true;
      final client = MockClient((request) async {
        final name = request.url.path.split('/').last;
        if (name == 'forest_blocks.json') {
          return http.Response(jsonEncode(twoBlocks()), 200);
        }
        if (!alive) throw const SocketException('Quelle weg');
        return http.Response.bytes(
            name == 'forest_block_x0_y0.bin.gz' ? small : large, 200);
      });

      final repo = ForestBlockRepository(client: client, baseDirOverride: dir);
      final catalog = (await repo.loadCatalog())!;
      expect(await repo.loadBlock(catalog, catalog.blocks.first), isNotNull);

      await repo.deleteBlocks();
      alive = false;
      expect(await repo.loadBlock(catalog, catalog.blocks.first), isNull,
          reason: 'ohne geleerten Speicher käme der gelöschte Block weiter');
    });

    test('eine Datei falscher Größe zählt nicht als vorhanden', () async {
      // Der Fall nach einem abgebrochenen Schreibvorgang. Sie muss neu
      // geholt werden, sonst bliebe eine halbe Datei für immer liegen.
      final repo =
          ForestBlockRepository(client: servingBoth(), baseDirOverride: dir);
      final catalog = (await repo.loadCatalog())!;
      final stump = File('${dir.path}/forest/forest_block_x0_y0.bin.gz');
      stump.createSync(recursive: true);
      stump.writeAsBytesSync(small.take(3).toList());

      expect((await repo.installedOf(catalog)).blocks, 0);
      await repo.downloadAll(catalog).drain<void>();
      expect((await repo.installedOf(catalog)).blocks, 2);
    });
  });
}
