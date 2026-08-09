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
}
