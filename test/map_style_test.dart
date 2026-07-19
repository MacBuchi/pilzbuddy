// Regressionstest für das Offline-Karten-Style: Der Flutter-Renderer muss
// ALLE Ebenen parsen können. Beim Regenerieren des Styles (npm
// @protomaps/basemaps) immer tool/transform_map_style.py laufen lassen —
// sonst fallen Text- und Flächen-Ebenen still weg (Karte grau, ohne Namen).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

void main() {
  test('Offline-Style wird vollständig geparst (keine verworfenen Ebenen)',
      () {
    final raw = File('assets/map_style/protomaps_light_de.json')
        .readAsStringSync();
    // `format`-Ausdrücke kann der Renderer nicht — sie dürfen nach dem
    // Transform-Skript nicht mehr im Style stehen.
    expect(raw.contains('"format"'), isFalse,
        reason: 'tool/transform_map_style.py nach dem Regenerieren ausführen');

    final styleJson = jsonDecode(raw) as Map<String, dynamic>;
    final theme = ThemeReader().read(styleJson);
    final declared = (styleJson['layers'] as List).length;
    expect(theme.layers.length, declared,
        reason: 'Renderer hat Style-Ebenen verworfen');

    // Die Namens-Ebenen (Städte, Straßen, Gewässer) müssen dabei sein.
    final ids = theme.layers.map((l) => l.id).toSet();
    expect(ids, containsAll(['places_locality', 'roads_labels_major']));
  });
}
