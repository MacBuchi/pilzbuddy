// Regressionstest für das Offline-Karten-Style: Der Flutter-Renderer muss
// ALLE Ebenen parsen können. Beim Regenerieren des Styles (npm
// @protomaps/basemaps) immer tool/transform_map_style.py laufen lassen —
// sonst fallen Text- und Flächen-Ebenen still weg (Karte grau, ohne Namen).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
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


  test('Ohne Hintergrund-Ebene bleibt der Rest des Styles unangetastet', () {
    // Die background-Ebene malt #cccccc deckend über die ganze Kachel —
    // auch für Kacheln ohne Daten. Im Detail-Layer würde sie damit genau
    // dort die Basiskarte zudecken, wo diese gebraucht wird (#118).
    final raw =
        File('assets/map_style/protomaps_light_de.json').readAsStringSync();
    final styleJson = jsonDecode(raw) as Map<String, dynamic>;
    final layers = styleJson['layers'] as List;
    expect(layers.any((l) => (l as Map)['type'] == 'background'), isTrue,
        reason: 'Ohne background-Ebene im Style wäre das Filtern sinnlos — '
            'dann stimmt die Annahme in offline_map_providers.dart nicht mehr');

    final stripped = styleWithoutBackground(styleJson);
    final strippedLayers = stripped['layers'] as List;
    expect(strippedLayers.length, layers.length - 1);
    expect(strippedLayers.any((l) => (l as Map)['type'] == 'background'),
        isFalse);
    // Das Original darf die Funktion nicht verändern: Die Basiskarte
    // braucht die Ebene weiterhin.
    expect((styleJson['layers'] as List).length, layers.length);
    // Und der Renderer muss den Rest weiterhin vollständig parsen.
    expect(ThemeReader().read(stripped).layers.length, strippedLayers.length);
  });

  test('Wanderwege haben eine eigene Ebene', () {
    // Protomaps steckt Pfade, Forstwege und Steige als `kind == "path"`
    // in dieselbe Ebene wie Zufahrten und Bahnsteige. Der LIGHT-Flavor
    // malt die mit #ebebeb auf #e2dfda und 0,5 px bei z14 — für eine
    // Pilz-App ist damit ausgerechnet unsichtbar, worauf man läuft.
    // `tool/transform_map_style.py` trennt sie deshalb heraus.
    final styleJson = jsonDecode(
            File('assets/map_style/protomaps_light_de.json').readAsStringSync())
        as Map<String, dynamic>;
    final layers = (styleJson['layers'] as List).cast<Map<String, dynamic>>();
    final ids = [for (final layer in layers) layer['id'] as String];

    expect(ids, containsAll(['roads_path_track', 'roads_path']));

    final other = layers.firstWhere((layer) => layer['id'] == 'roads_other');
    expect(jsonEncode(other['filter']), isNot(contains('"path"')),
        reason: 'roads_other darf kind == path nicht mehr einsammeln — sonst '
            'liegt die blasse Sammelgrube wieder auf denselben Wegen');

    // Direkt hinter roads_other, also UNTER den Straßen: Eine Straße,
    // die einen Forstweg kreuzt, gehört obenauf.
    expect(ids.indexOf('roads_path_track'), ids.indexOf('roads_other') + 1);
    expect(ids.indexOf('roads_path'), ids.indexOf('roads_other') + 2);
    expect(ids.indexOf('roads_path'), lessThan(ids.indexOf('roads_minor')));

    // Forstwege ab z12, der Rest ab z13 in den Kacheln (nachgemessen an
    // `de_saarland`) — die Breiten dürfen deshalb nicht wieder bei z14
    // anfangen, sonst ändert sich sichtbar nichts.
    for (final id in ['roads_path_track', 'roads_path']) {
      final paint = layers.firstWhere((layer) => layer['id'] == id)['paint']
          as Map<String, dynamic>;
      final width = paint['line-width'] as List;
      expect(width[3], 12, reason: '$id soll ab Zoom 12 breiter werden');
      expect(paint['line-dasharray'], isNotNull,
          reason: 'gestrichelt, damit ein Weg nicht wie eine Straße aussieht');
    }
  });

  test('Der Renderer versteht die Wanderwege-Ebenen', () {
    // Eine Ebene, die vector_tile_renderer nicht parst, lässt er
    // stillschweigend weg — genau der Fehler, gegen den es das
    // Transform-Skript überhaupt gibt.
    final styleJson = jsonDecode(
            File('assets/map_style/protomaps_light_de.json').readAsStringSync())
        as Map<String, dynamic>;
    final ids = ThemeReader().read(styleJson).layers.map((l) => l.id).toSet();
    expect(ids, containsAll(['roads_path_track', 'roads_path']));
  });
}
