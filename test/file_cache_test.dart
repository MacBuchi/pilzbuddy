// Der Speicher mit Größengrenze (`BoundedFileCache`): Seit #659 zählt er
// das Verzeichnis nicht mehr bei jedem Ablegen, sondern schreibt die
// Belegung fort. Die Grenze muss trotzdem halten — sonst wüchse der
// Kachelspeicher unbemerkt über seine 64 MB.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/file_cache.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('file_cache_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<int> bytesOnDisk() async {
    var total = 0;
    await for (final e in Directory('${tmp.path}/c').list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  test('die Grenze hält auch, wenn nur noch fortgeschrieben wird', () async {
    final cache =
        BoundedFileCache(dirName: 'c', maxBytes: 1000, baseDirectory: tmp);
    for (var i = 0; i < 40; i++) {
      await cache.write('k$i', Uint8List(100));
      expect(await bytesOnDisk(), lessThanOrEqualTo(1000),
          reason: 'nach Ablage $i');
    }
    expect(await cache.read('k39'), hasLength(100),
        reason: 'das zuletzt Abgelegte bleibt');
  });

  test('keine halben Dateien: nach dem Ablegen liegt nichts mit .part',
      () async {
    final cache =
        BoundedFileCache(dirName: 'c', maxBytes: 1000, baseDirectory: tmp);
    await cache.write('a/b', Uint8List.fromList([1, 2, 3]));
    final names = [
      await for (final e in Directory('${tmp.path}/c').list())
        e.uri.pathSegments.last
    ];
    expect(names, ['a_b']);
    expect(await cache.read('a/b'), [1, 2, 3]);
  });
}
