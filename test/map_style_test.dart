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

    // Forstwege ab z12, der Rest ab z13 — so liegen sie in den Kacheln
    // (nachgemessen an `de_saarland`). Die erste Stützstelle der Breite
    // muss dort sitzen, sonst zeichnet der Renderer die Ebene mit der
    // Breite der ersten Stufe auch darunter: in der Übersicht ein
    // Gespinst aus Feldwegen, wo man Landschaft sehen will.
    const startZoom = {'roads_path_track': 12, 'roads_path': 13};
    for (final entry in startZoom.entries) {
      final layer = layers.firstWhere((l) => l['id'] == entry.key);
      final paint = layer['paint'] as Map<String, dynamic>;
      expect((paint['line-width'] as List)[3], entry.value,
          reason: '${entry.key} soll ab Zoom ${entry.value} breiter werden');
      expect(layer['minzoom'], entry.value,
          reason: '${entry.key}: minzoom und erste Stützstelle gehören '
              'zusammen — sonst hängt die Sichtbarkeit an der Breite');
      expect(paint['line-dasharray'], isNotNull,
          reason: 'gestrichelt — aber nur MapLibre sieht das, siehe unten');
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

  test('Der Strich ist Zugabe, die Aussage tragen Farbe und Breite', () {
    // vector_tile_renderer 6.1.0 prüft in paint_factory.dart
    // `dashJson is List<num>` — jsonDecode liefert aber List<dynamic>,
    // und das ist in Dart KEIN List<num>. Auf dem klassischen Renderer
    // (Web und classicMapEnabled) sind die Wege deshalb durchgezogen,
    // in MapLibre gestrichelt. Dieselbe Lage wie bei roads_rail und
    // allen roads_tunnels_* seit jeher — also keine Verschlechterung,
    // aber der Grund, warum die Breiten weit auseinanderliegen müssen.
    expect(jsonDecode('[4, 2]') is List<num>, isFalse,
        reason: 'Ändert sich das je, darf dieser Test bleiben — dann ist '
            'der Strich plötzlich überall da, und das wäre gut');

    final styleJson = jsonDecode(
            File('assets/map_style/protomaps_light_de.json').readAsStringSync())
        as Map<String, dynamic>;
    final layers = (styleJson['layers'] as List).cast<Map<String, dynamic>>();
    double widthAt(String id, int zoom) {
      final stops = ((layers.firstWhere((layer) => layer['id'] == id)['paint']
          as Map<String, dynamic>)['line-width'] as List).skip(3).toList();
      for (var i = 0; i < stops.length; i += 2) {
        if (stops[i] == zoom) return (stops[i + 1] as num).toDouble();
      }
      fail('keine Stützstelle bei Zoom $zoom für $id');
    }

    // Ohne Strich bleibt nur die Breite. Der Forstweg — das für Sammler
    // Wichtigste — muss deutlich dicker sein als der Pfad, nicht nur
    // eine Spur.
    expect(widthAt('roads_path_track', 15),
        greaterThanOrEqualTo(widthAt('roads_path', 15) * 1.5));
    expect(widthAt('roads_path_track', 20),
        greaterThanOrEqualTo(widthAt('roads_path', 20) * 1.5));
  });

  test('In paint und layout steht nirgends die alte Filter-Kurzform', () {
    // DER BEFUND VOM 2026-08-21. `["in", "kind", "a", "b"]` ist ein
    // FILTER, kein Ausdruck. In `paint` lehnt MapLibre die Ebene ab —
    // ohne Fehlermeldung, ohne Ersatzfarbe, sie ist einfach weg. Seit
    // 1.43.0 (MapLibre als Vorgabe) waren dadurch `landuse_park` und
    // `pois` still ausgefallen: kein grüner Wald, keine Wiese, kein
    // Park, keine POI-Namen. Auf der Offline-Karte blieben Straßen und
    // Wege übrig — genau der Eindruck, den der Betreiber gemeldet hat.
    //
    // Erzeugt hat es unser eigenes Werkzeug: `fix_in` schrieb die
    // Kurzform auch nach `paint`, weil `vector_tile_renderer` `in` NUR
    // so versteht. Beide Renderer können `match`, also steht dort
    // jetzt `match` (tool/transform_map_style.py, [rewrite_in]).
    final styleJson = jsonDecode(
            File('assets/map_style/protomaps_light_de.json').readAsStringSync())
        as Map<String, dynamic>;

    bool legacyIn(Object? node) {
      if (node is! List) return false;
      if (node.isNotEmpty &&
          (node.first == 'in' || node.first == '!in') &&
          node.length > 1 &&
          node[1] is String) {
        return true;
      }
      return node.any(legacyIn);
    }

    final offenders = <String>[];
    for (final layer in (styleJson['layers'] as List).cast<Map<String, dynamic>>()) {
      for (final section in ['paint', 'layout']) {
        final block = layer[section] as Map<String, dynamic>?;
        if (block == null) continue;
        for (final entry in block.entries) {
          if (legacyIn(entry.value)) {
            offenders.add('${layer['id']}.$section.${entry.key}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'MapLibre wirft diese Ebenen weg — tool/transform_map_style.py '
            'muss in paint/layout `match` schreiben, nicht die Kurzform');

    // Und derselbe Riegel für den Filter, sobald dort schon ein
    // Ausdruck steht: gemischt lehnt MapLibre ihn genauso ab.
    for (final layer in (styleJson['layers'] as List).cast<Map<String, dynamic>>()) {
      final filter = layer['filter'];
      if (filter == null) continue;
      final text = jsonEncode(filter);
      if (!text.contains('["zoom"]') && !text.contains('["get"')) continue;
      expect(legacyIn(filter), isFalse,
          reason: '${layer['id']}: alte Kurzform neben einem Ausdruck');
    }
  });

  test('Wald, Wiese und Park bekommen wieder ihre Farbe', () {
    final styleJson = jsonDecode(
            File('assets/map_style/protomaps_light_de.json').readAsStringSync())
        as Map<String, dynamic>;
    final park = (styleJson['layers'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((layer) => layer['id'] == 'landuse_park');

    // Die Fläche muss `forest` treffen — die Kacheln liefern sie unter
    // diesem Namen (nachgesehen in einer echten z13-Kachel aus
    // de_saarland: 16 forest-Polygone).
    expect(jsonEncode(park['filter']), contains('"forest"'));
    final fillColor = jsonEncode(park['paint']['fill-color']);
    expect(fillColor, contains('"forest"'));
    expect(fillColor, contains('#9cd3b4'),
        reason: 'ohne Treffer bliebe nur der Erdton als Rückfall');
  });

  test('Der klassische Renderer bekommt keinen neuen blinden Fleck', () {
    // Der Riegel für die Gegenrichtung: `match` statt `in` darf den
    // Canvas-Renderer (Web, classicMapEnabled) nicht kalt erwischen.
    // Einen Ausdruck, den er nicht versteht, verwirft er still — die
    // Ebenen-Zahl oben bliebe davon unberührt, die Warnung ist der
    // einzige Hinweis.
    //
    // EINE Lücke gibt es, und sie ist älter als dieser Umbau: Der
    // `pois`-Filter fragt `["zoom"]` ab, und das kennt
    // `vector_tile_renderer` 6.1.0 gar nicht. Vor und nach dem Umbau
    // sind es dieselben vier Meldungen (2026-08-21 gegen den Stand von
    // 1.98.0 gemessen) — deshalb steht hier die Zahl und nicht `isEmpty`.
    // Wächst sie, hat jemand dem Renderer etwas Neues vorgesetzt.
    final warnings = <String>[];
    final styleJson = jsonDecode(
            File('assets/map_style/protomaps_light_de.json').readAsStringSync())
        as Map<String, dynamic>;
    ThemeReader(logger: _RecordingLogger(warnings)).read(styleJson);
    expect(warnings.where((w) => !w.contains('[zoom]')), isEmpty,
        reason: 'neuer Ausdruck, den der klassische Renderer nicht versteht');
    expect(warnings, hasLength(4),
        reason: 'die bekannte pois-Lücke — mehr darf es nicht werden');
  });
}

/// Sammelt die Warnungen von `vector_tile_renderer` ein, statt sie auf
/// die Konsole zu schreiben, wo sie niemand liest.
class _RecordingLogger implements Logger {
  _RecordingLogger(this.warnings);

  final List<String> warnings;

  @override
  void log(MessageFunction message) {}

  @override
  void warn(MessageFunction message) => warnings.add(message());
}
