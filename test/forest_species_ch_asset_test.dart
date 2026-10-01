// Das ausgelieferte Schweizer Artengitter hält, was das Werkzeug
// verspricht — geprüft am Asset selbst (`tool/forest_species_ch.py`).
//
// Der Leser rechnet die Wabe über das GANZE Hex-Raster aus und
// verschiebt dann ins gespeicherte Rechteck. Stimmt das Raster nicht mit
// dem der anderen Gitter überein, landet jede Abfrage eine Wabe daneben,
// ohne dass irgendetwas scheitert — deshalb der erste Test.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_species.dart';

Map<String, dynamic> _manifest(String name) =>
    jsonDecode(File('assets/forest/${name}_manifest.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final ch = _manifest('forest_species_ch');
  final dlr = _manifest('forest_species');
  final grid = SwissSpeciesGrid.decode(
    File('assets/forest/forest_species_ch.bin.gz').readAsBytesSync(),
    gridWidth: ch['grid_width'] as int,
    gridHeight: ch['grid_height'] as int,
    x0: ch['x0'] as int,
    y0: ch['y0'] as int,
    width: ch['width'] as int,
    height: ch['height'] as int,
    west: (ch['west'] as num).toDouble(),
    east: (ch['east'] as num).toDouble(),
    north: (ch['north'] as num).toDouble(),
    south: (ch['south'] as num).toDouble(),
    referenceYear: ch['reference_year'] as int,
    hexLonStep: (ch['hex_lon_step'] as num).toDouble(),
    hexLatStep: (ch['hex_lat_step'] as num).toDouble(),
  );

  test('dasselbe Hex-Raster wie das DLR-Gitter', () {
    for (final key in [
      'west',
      'east',
      'north',
      'south',
      'hex_lon_step',
      'hex_lat_step',
      'cell_factor',
    ]) {
      expect(ch[key], dlr[key], reason: key);
    }
    expect(ch['grid_width'], dlr['width']);
    expect(ch['grid_height'], dlr['height']);
  });

  test('Format und Artenliste passen zum Leser', () {
    expect(ch['cell_bytes'], 3);
    expect(ch['slots'], swissTreeSlots);
    expect((ch['species'] as List).length, SwissTree.values.length);
    expect(ch['species'], contains('Castanea sativa'));
    expect(ch['never_named'], ['Larix']);
    expect(ch['threshold'], 0.1);
  });

  test('jede Liste ist lückenlos und nennt keine Art zweimal', () {
    var named = 0;
    for (var i = 0; i < grid.values.length; i += 3) {
      final v =
          grid.values[i] << 16 | grid.values[i + 1] << 8 | grid.values[i + 2];
      if (v == 0 || v == swissCoveredNone) continue;
      named++;
      final seen = <int>{};
      var ended = false;
      for (var slot = 0; slot < swissTreeSlots; slot++) {
        final nibble = (v >> (4 * (swissTreeSlots - 1 - slot))) & 0xF;
        if (nibble == 0) {
          ended = true;
          continue;
        }
        expect(ended, isFalse, reason: 'Art nach dem Listenende: $v');
        expect(seen.add(nibble), isTrue, reason: 'Art doppelt: $v');
      }
      expect(seen, isNotEmpty);
    }
    expect(named, ch['named_cells']);
  });

  test('spricht in der Schweiz und schweigt in Deutschland', () {
    // Der Wald am Uetliberg über Zürich und der Kastanienwald über
    // Locarno; Freiburg im Breisgau liegt außerhalb der Karte.
    expect(grid.at(47.3496, 8.4920), isNotEmpty);
    expect(grid.at(46.1790, 8.7950), isNotEmpty);
    expect(grid.at(47.9990, 7.8420), isNull);
  });
}
