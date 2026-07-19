// Regressionstests für #41: Downloads großer Karten müssen
// Verbindungsabrisse überleben (HTTP-Range-Fortsetzung) und eine
// liegengebliebene .part-Datei beim nächsten Versuch weiterverwenden.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_repository.dart';

const _map = AvailableMap(
  key: 'de_bremen',
  dateStamp: '20260320',
  sizeBytes: 1000,
  downloadUrl: 'https://example.invalid/de_bremen_20260320.pmtiles',
);

final _mapBytes = List<int>.generate(1000, (i) => i % 251);

Future<Directory> _tempDir() async {
  final dir = await Directory.systemTemp.createTemp('pilzbuddy_dl_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  test('Verbindungsabriss mitten im Download wird per Range fortgesetzt',
      () async {
    final rangeHeaders = <String?>[];
    var call = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      call++;
      rangeHeaders.add(request.headers['range']);
      if (call == 1) {
        // Erste 400 Bytes liefern, dann bricht die Verbindung.
        final controller = StreamController<List<int>>()
          ..add(_mapBytes.sublist(0, 400))
          ..addError(const SocketException('Verbindung abgerissen'))
          ..close();
        return http.StreamedResponse(controller.stream, 200,
            contentLength: _mapBytes.length);
      }
      return http.StreamedResponse(
          Stream.value(_mapBytes.sublist(400)), 206);
    });

    final repo = OfflineMapRepository(
        client: client, baseDirOverride: await _tempDir());

    final progress = <double>[];
    await for (final p in repo.download(_map)) {
      progress.add(p);
    }

    // Zweiter Request muss dort weitermachen, wo der erste abriss.
    expect(rangeHeaders, [null, 'bytes=400-']);
    final installed = await repo.listInstalled();
    expect(installed.single.key, 'de_bremen');
    expect(await File(installed.single.filePath).readAsBytes(), _mapBytes);
    expect(progress.last, 1.0);
  });

  test('Liegengebliebene .part-Datei wird beim nächsten Versuch fortgesetzt',
      () async {
    final dir = await _tempDir();
    // Halbfertiger Download aus einem früheren (abgebrochenen) Versuch.
    final mapsDir = Directory('${dir.path}/offline_maps')
      ..createSync(recursive: true);
    File('${mapsDir.path}/de_bremen_20260320.pmtiles.part')
        .writeAsBytesSync(_mapBytes.sublist(0, 700));

    String? rangeHeader;
    final client = MockClient.streaming((request, bodyStream) async {
      rangeHeader = request.headers['range'];
      return http.StreamedResponse(
          Stream.value(_mapBytes.sublist(700)), 206);
    });

    final repo = OfflineMapRepository(client: client, baseDirOverride: dir);
    await repo.download(_map).drain<void>();

    expect(rangeHeader, 'bytes=700-');
    final installed = await repo.listInstalled();
    expect(await File(installed.single.filePath).readAsBytes(), _mapBytes);
  });

  test('Korrupte Datei fällt durch die Prüfsumme und wird neu geladen',
      () async {
    final mapWithChecksum = AvailableMap(
      key: _map.key,
      dateStamp: _map.dateStamp,
      sizeBytes: _map.sizeBytes,
      downloadUrl: _map.downloadUrl,
      sha256: 'sha256:${sha256.convert(_mapBytes)}',
    );

    var call = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      call++;
      if (call == 1) {
        // Richtige Länge, aber ein gekipptes Byte — z. B. weil die Quelle
        // das Asset ersetzt hat, während eine .part-Datei fortgesetzt wurde.
        final corrupt = List<int>.of(_mapBytes);
        corrupt[500] = (corrupt[500] + 1) % 256;
        return http.StreamedResponse(Stream.value(corrupt), 200,
            contentLength: corrupt.length);
      }
      return http.StreamedResponse(Stream.value(_mapBytes), 200,
          contentLength: _mapBytes.length);
    });

    final repo = OfflineMapRepository(
        client: client, baseDirOverride: await _tempDir());
    await repo.download(mapWithChecksum).drain<void>();

    expect(call, 2); // Erster Download verworfen, zweiter sauber.
    final installed = await repo.listInstalled();
    expect(await File(installed.single.filePath).readAsBytes(), _mapBytes);
    expect(installed.single.sha256, mapWithChecksum.sha256);
  });

  test('Dauerhaft falsche Prüfsumme bricht mit Fehler ab statt zu installieren',
      () async {
    final mapWithChecksum = AvailableMap(
      key: _map.key,
      dateStamp: _map.dateStamp,
      sizeBytes: _map.sizeBytes,
      downloadUrl: _map.downloadUrl,
      sha256: 'sha256:${'0' * 64}',
    );
    final client = MockClient.streaming((request, bodyStream) async =>
        http.StreamedResponse(Stream.value(_mapBytes), 200,
            contentLength: _mapBytes.length));

    final repo = OfflineMapRepository(
        client: client, baseDirOverride: await _tempDir());

    await expectLater(repo.download(mapWithChecksum).drain<void>(),
        throwsA(isA<FileSystemException>()));
    expect(await repo.listInstalled(), isEmpty);
  });
}
