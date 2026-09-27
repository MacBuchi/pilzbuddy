// Das ausgelieferte Rückfall-Gitter (#624) hält, was das Werkzeug
// verspricht — geprüft am Asset selbst, nicht am Werkzeug.
//
// Der Leser beschränkt ohnehin auf Fichte, Kiefer und Buche
// (`forestSpeciesReadingAt`). Dieser Test fängt den anderen Fall: ein
// Asset, das mit einer geänderten Regel gebaut wurde und dessen Zahlen
// dann nicht mehr zur Messung in #624 passen — oder eines, das über
// Deutschland spricht, wo das DLR-Gitter gilt.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_species.dart';

List<int> _grid(String name) {
  final manifest = jsonDecode(
          File('assets/forest/${name}_manifest.json').readAsStringSync())
      as Map<String, dynamic>;
  final flat =
      gzip.decode(File('assets/forest/$name.bin.gz').readAsBytesSync());
  if (flat.length != (manifest['width'] as int) * (manifest['height'] as int)) {
    throw StateError('$name: Länge passt nicht zum Manifest');
  }
  return flat;
}

void main() {
  final eu = _grid('forest_species_eu');
  final dlr = _grid('forest_species');

  test('dasselbe Raster wie das DLR-Gitter', () {
    expect(eu.length, dlr.length);
  });

  test('nur Fichte, Kiefer und Buche — oder nichts', () {
    final allowed = <int>{speciesNoData};
    for (final hi in [0, ...estimatedBroadleaves.map((b) => b.index + 1)]) {
      for (final lo in [0, ...estimatedConifers.map((c) => c.index + 1)]) {
        allowed.add(hi << 4 | lo);
      }
    }
    final found = eu.toSet();
    expect(found.difference(allowed), isEmpty,
        reason: 'Bytes außerhalb der drei Gattungen im Asset');
    // Und es steht wirklich etwas darin.
    expect(found, containsAll([0x01, 0x02, 0x10, 0x11]));
  });

  test('schweigt überall, wo das DLR-Gitter etwas sagt', () {
    var overlap = 0;
    for (var i = 0; i < eu.length; i++) {
      if (dlr[i] != speciesNoData && eu[i] != speciesNoData) overlap++;
    }
    expect(overlap, 0);
  });
}
