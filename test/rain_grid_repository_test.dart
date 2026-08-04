// Was das Regen-Repository auf Platte anstellt.
//
// Der Netzweg braucht kein eigenes Netz — beide Provider sind im Harness
// überschrieben, und die Fehlerpfade degradieren still. Geprüft wird
// hier, was NICHT still degradiert, sondern still FALSCH wäre: eine
// Fläche, die als Datei liegen bleibt, obwohl die App sie inzwischen
// anders zeichnet.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('rain_repo_test');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  RainGridRepository repo() => RainGridRepository(baseDirOverride: base);

  final measured = DateTime.utc(2026, 8, 4, 5, 50);

  test('legt die Fläche als Datei ab und nennt ihre URL', () async {
    final url = await repo().writeFill('w4', measured, [1, 2, 3]);

    expect(url, isNotNull);
    expect(url, startsWith('file://'));
    final file = File(url!.substring('file://'.length));
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(file.path, contains('2026-08-04'),
        reason: 'ohne Messzeitpunkt im Namen läge ein neuer Stand unter '
            'derselben URL, und die Engine behielte das alte Bild');
  });

  test('schreibt auch dann, wenn die Datei schon liegt', () async {
    // Der Name kennt den Messzeitpunkt, nicht die Darstellung. Ohne
    // dieses Überschreiben bliebe nach einer App-Version mit anderen
    // Farben, anderer Deckkraft oder anderer Glättung das ALTE Bild
    // liegen — bis zur nächsten Messung. Genau das ist am 2026-08-04 am
    // Emulator passiert: pixelgleiches Ergebnis trotz geändertem Code.
    await repo().writeFill('w4', measured, [1, 2, 3]);
    final url = await repo().writeFill('w4', measured, [9, 9]);

    expect(await File(url!.substring('file://'.length)).readAsBytes(), [9, 9]);
  });

  test('räumt ältere Flächen weg, lässt Gitter und Manifest stehen',
      () async {
    // Gitter (`w4_…`) und Flächen (`fill_w4_…`) liegen im selben Ordner.
    // Ein Aufräumen, das seinen Namensanfang aus der Datei rät, die es
    // behalten will, reißt die jeweils andere Sorte mit.
    final dir = Directory('${base.path}/rain')..createSync(recursive: true);
    File('${dir.path}/w4_2026-08-03T05-50-00-000Z.bin.gz')
        .writeAsBytesSync([0]);
    File('${dir.path}/w4.json').writeAsStringSync('{}');
    await repo().writeFill('w4', DateTime.utc(2026, 8, 3), [1]);

    await repo().writeFill('w4', measured, [2]);

    final left = dir.listSync().map((e) => e.path.split('/').last).toSet();
    expect(left, {
      'w4_2026-08-03T05-50-00-000Z.bin.gz',
      'w4.json',
      'fill_w4_2026-08-04T05-50-00-000Z.png',
    });
  });

  test('trennt die Ebenen — eine neue 30-Tage-Fläche rührt die '
      '24-Stunden-Fläche nicht an', () async {
    await repo().writeFill('sf', measured, [1]);
    await repo().writeFill('w4', measured, [2]);

    final dir = Directory('${base.path}/rain');
    expect(dir.listSync().length, 2);
  });
}
