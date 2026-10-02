// Der Kachel-Server der Neuen Karte (#659): Jede Zusage hier ist eine
// gemessene Wiederholung aus #630, die es nicht mehr geben darf — und
// jede Anfrage, die er nicht stellt, ist eine R2-Operation weniger.
//
// Echte Sockets auf Loopback und echte Dateien: Genau das, was MapLibre
// auf dem Gerät tut, nur mit einem zählenden Archiv statt des Hosts.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/file_cache.dart';
import 'package:pilzbuddy/features/map/online_tile_server.dart';

class _CountingArchive {
  final calls = <String>[];

  /// Hält Abrufe an, bis der Test sie freigibt — so liegen zwei Anfragen
  /// wirklich gleichzeitig in der Luft.
  Completer<void>? gate;
  bool closed = false;

  Future<Uint8List?> fetch(int z, int x, int y) async {
    calls.add('$z/$x/$y');
    await gate?.future;
    if (closed) throw StateError('withResource() on a closed Pool');
    if (z == 13 && x == 0) return null; // Lücke im Archiv
    return Uint8List.fromList([z, x, y, 0x1f]);
  }
}

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tile_server_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<OnlineTileServer> serverOver(_CountingArchive archive) async {
    final server = OnlineTileServer(
      cache: BoundedFileCache(
          dirName: 'map_tile_cache',
          maxBytes: 1 << 20,
          baseDirectory: tmp),
    );
    await server.start();
    addTearDown(server.close);
    server.attach(build: 'dach-20261001', fetch: archive.fetch, gzip: true);
    return server;
  }

  Future<({int status, List<int> body, String? encoding})> get(
      OnlineTileServer server, String path) async {
    final template = server.urlTemplate('dach-20261001');
    final base = template.substring(0, template.indexOf('/dach-'));
    final client = HttpClient()..autoUncompress = false;
    addTearDown(client.close);
    final request = await client.getUrl(Uri.parse('$base/$path'));
    final response = await request.close();
    final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (
      status: response.statusCode,
      body: body,
      encoding: response.headers.value(HttpHeaders.contentEncodingHeader),
    );
  }

  test('die Vorlage zeigt auf Loopback und nennt den Stand', () async {
    final server = await serverOver(_CountingArchive());
    expect(server.urlTemplate('dach-20261001'),
        matches(RegExp(r'^http://127\.0\.0\.1:\d+/dach-20261001/\{z\}/\{x\}/\{y\}\.pbf$')));
  });

  test('liefert die Bytes unverändert, mit gzip-Kennung', () async {
    final server = await serverOver(_CountingArchive());
    final r = await get(server, 'dach-20261001/7/68/44.pbf');
    expect(r.status, 200);
    expect(r.body, [7, 68, 44, 0x1f]);
    expect(r.encoding, 'gzip');
  });

  test('zwei gleichzeitige Anfragen auf eine Kachel ⇒ EIN Abruf', () async {
    final archive = _CountingArchive()..gate = Completer<void>();
    final server = await serverOver(archive);
    final a = get(server, 'dach-20261001/7/68/44.pbf');
    final b = get(server, 'dach-20261001/7/68/44.pbf');
    // Beide Anfragen müssen den Server erreicht haben, bevor der Abruf
    // zurückkommt — sonst prüft der Test nur das Ablegen.
    while (archive.calls.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    archive.gate!.complete();
    final results = await Future.wait([a, b]);
    expect([for (final r in results) r.status], [200, 200]);
    expect(archive.calls, ['7/68/44']);
  });

  test('abgelegt ⇒ die zweite Anfrage geht nicht hinaus', () async {
    final archive = _CountingArchive();
    final server = await serverOver(archive);
    await get(server, 'dach-20261001/7/68/44.pbf');
    final again = await get(server, 'dach-20261001/7/68/44.pbf');
    expect(again.body, [7, 68, 44, 0x1f]);
    expect(archive.calls, hasLength(1));
  });

  test('nach dem Neustart (neuer Server, derselbe Ordner) ⇒ kein Abruf',
      () async {
    final first = _CountingArchive();
    final before = await serverOver(first);
    await get(before, 'dach-20261001/7/68/44.pbf');
    await before.close();

    final second = _CountingArchive();
    final after = await serverOver(second);
    final r = await get(after, 'dach-20261001/7/68/44.pbf');
    expect(r.status, 200);
    expect(r.body, [7, 68, 44, 0x1f]);
    expect(second.calls, isEmpty);
  });

  test('Lücke im Archiv ⇒ 204, und nur einmal gefragt', () async {
    final archive = _CountingArchive();
    final server = await serverOver(archive);
    expect((await get(server, 'dach-20261001/13/0/5.pbf')).status, 204);
    expect((await get(server, 'dach-20261001/13/0/5.pbf')).status, 204);
    expect(archive.calls, ['13/0/5']);
  });

  test('geschlossenes Archiv ⇒ 503, nichts abgelegt', () async {
    final archive = _CountingArchive()..closed = true;
    final server = await serverOver(archive);
    expect((await get(server, 'dach-20261001/7/68/44.pbf')).status, 503);
    archive.closed = false;
    final retry = await get(server, 'dach-20261001/7/68/44.pbf');
    expect(retry.status, 200, reason: 'ein Fehler darf nicht hängenbleiben');
    expect(archive.calls, hasLength(2));
  });

  test('ein fremder Stand oder Unsinn im Pfad ⇒ 404, kein Abruf', () async {
    final archive = _CountingArchive();
    final server = await serverOver(archive);
    expect((await get(server, 'dach-20250101/7/68/44.pbf')).status, 404);
    expect((await get(server, 'dach-20261001/7/68.pbf')).status, 404);
    expect((await get(server, 'dach-20261001/a/b/c.pbf')).status, 404);
    expect(archive.calls, isEmpty);
  });
}
