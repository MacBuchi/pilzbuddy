// Keine Hintergrundrechnung an der Grenze vorbei (#641).
//
// Der ANR aus #641 hing an zu vielen gleichzeitigen Isolates in der
// Gruppe der Oberfläche. Grenze (`boundedCompute`) und Zeichen-Isolate
// (`map_worker.dart`) helfen nur, wenn ALLE Rechnungen über sie laufen —
// ein neues nacktes `compute` irgendwo gälte wieder ohne Grenze, und
// niemand sähe es im Diff.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowed = {
  'lib/core/bounded_compute.dart',
  'lib/core/map_worker.dart',
};

final _bare = RegExp(r'(?<![\w.])compute\(|Isolate\.(run|spawn|spawnUri)\(');

void main() {
  test('kein nacktes compute oder Isolate.run in lib/', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (_allowed.contains(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (_bare.hasMatch(line)) hits.add('$path:${i + 1}: $line');
      }
    }
    expect(hits, isEmpty,
        reason: 'Über boundedCompute oder runOnMapWorker rechnen (#641)');
  });
}
