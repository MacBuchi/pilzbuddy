// postgrest-dart sortiert ohne Angabe ABSTEIGEND (`ascending = false`).
// Das hat zweimal zugeschnappt: bei den Nachrichten (behoben, bevor es
// auffiel) und bei den eigenen Spots (bis 1.210.0 live neuester zuerst,
// im Fake ältester zuerst — die Tests prüften eine andere Reihenfolge als
// die ausgelieferte). Deshalb steht die Richtung an jeder Abfrage.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _order = RegExp(r'\.order\(([^)]*)\)');

void main() {
  test('jedes .order( nennt seine Richtung', () {
    final missing = <String>[];
    var calls = 0;
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final match in _order.allMatches(file.readAsStringSync())) {
        calls++;
        if (!match.group(1)!.contains('ascending:')) {
          missing.add('${file.path}: ${match.group(0)}');
        }
      }
    }
    expect(calls, greaterThanOrEqualTo(3), reason: 'überhaupt gefunden');
    expect(missing, isEmpty,
        reason: 'ohne `ascending:` sortiert postgrest-dart absteigend');
  });
}
