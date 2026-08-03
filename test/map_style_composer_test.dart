// Der Style-Composer ist pure Logik ohne I/O — genau deshalb ist er hier
// vollständig prüfbar: Was er zusammensetzt, entscheidet, ob MapLibre
// überhaupt etwas rendert (der Spike scheiterte an einem Style, der vor
// den Regionsquellen gebaut wurde).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/map_view/map_style_composer.dart';

/// Kleines Basis-Style-Dokument im Protomaps-Schema: eine background-Ebene,
/// eine Flächen-Ebene, eine Text-Ebene mit Schriften auch in einem
/// case-Ausdruck (so steckt es im echten Asset).
Map<String, dynamic> _baseStyle() => {
      'version': 8,
      'sources': {
        'protomaps': {'type': 'vector', 'url': 'https://example.invalid/x'},
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#cccccc'},
        },
        {
          'id': 'earth',
          'type': 'fill',
          'source': 'protomaps',
          'source-layer': 'earth',
        },
        {
          'id': 'places',
          'type': 'symbol',
          'source': 'protomaps',
          'layout': {
            'text-font': [
              'case',
              [
                '==',
                ['get', 'kind'],
                'city'
              ],
              ['literal', 'Noto Sans Medium'],
              ['literal', 'Noto Sans Italic'],
            ],
          },
        },
      ],
    };

const _overview = MapStyleSource(
  id: 'overview',
  filePath: '/data/app/offline_maps/overview_dach.pmtiles',
  minZoom: 0,
  maxZoom: 7,
);

const _bayern = MapStyleSource(
  id: 'region_de_bayern',
  filePath: '/data/app/offline_maps/de_bayern_20260320.pmtiles',
  minZoom: 0,
  maxZoom: 15,
);

const _osm = MapRasterSource(
  id: 'osm',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  maxZoom: 19,
);

Map<String, dynamic> _compose({List<MapStyleSource>? sources}) =>
    jsonDecode(composeMapLibreStyle(
      baseStyle: _baseStyle(),
      glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
      backgroundColor: '#e2dfda',
      sources: sources ?? const [_overview, _bayern],
    )) as Map<String, dynamic>;

void main() {
  test('genau eine background-Ebene, zuerst und im Landton', () {
    final style = _compose();
    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    final backgrounds =
        layers.where((l) => l['type'] == 'background').toList();
    expect(backgrounds, hasLength(1),
        reason: 'Die background-Ebene des Basis-Styles darf nicht je '
            'Quelle dupliziert werden — sie würde alles darunter zudecken.');
    expect(layers.first['type'], 'background');
    expect(layers.first['paint'], {'background-color': '#e2dfda'});
  });

  test('jede Quelle: pmtiles-URL und Zoombereich aus dem Header', () {
    final style = _compose();
    final sources = style['sources'] as Map<String, dynamic>;
    expect(sources.keys, ['overview', 'region_de_bayern']);
    final overview = sources['overview'] as Map<String, dynamic>;
    expect(overview['url'],
        'pmtiles://file:///data/app/offline_maps/overview_dach.pmtiles');
    expect(overview['minzoom'], 0);
    expect(overview['maxzoom'], 7);
    final bayern = sources['region_de_bayern'] as Map<String, dynamic>;
    expect(bayern['maxzoom'], 15);
    // Attribution trägt nur die ERSTE Quelle (Dedup, eigener Test unten).
    expect(overview['attribution'], contains('OpenStreetMap'));
    // Die Quelle des Basis-Styles ist ersetzt, nicht ergänzt.
    expect(sources.containsKey('protomaps'), isFalse);
  });

  test('Ebenen je Quelle dupliziert: Präfix-Id, Quelle umgehängt, '
      'Reihenfolge = Quellenreihenfolge', () {
    final style = _compose();
    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    final ids = layers.map((l) => l['id']).toList();
    expect(
        ids,
        containsAllInOrder([
          'overview/earth',
          'overview/places',
          'region_de_bayern/earth',
          'region_de_bayern/places',
        ]),
        reason: 'Übersicht unten, Regionen darüber — die Zeichenreihenfolge '
            'ist die Reihenfolge der übergebenen Quellen.');
    final regionEarth =
        layers.singleWhere((l) => l['id'] == 'region_de_bayern/earth');
    expect(regionEarth['source'], 'region_de_bayern');
    expect(regionEarth['source-layer'], 'earth');
  });

  test('Schriftnamen werden auf die eigenen Stacks umgeschrieben — auch in '
      'case-Ausdrücken', () {
    final style = _compose();
    final encoded = jsonEncode(style);
    expect(encoded, isNot(contains('Noto Sans Medium')));
    expect(encoded, isNot(contains('Noto Sans Italic')));
    expect(encoded, contains('noto-sans-medium'));
    expect(encoded, contains('noto-sans-regular'));
    expect(style['glyphs'], 'file:///glyphs/{fontstack}/{range}.pbf');
  });

  test('ohne Regionen bleibt die Übersicht allein übrig', () {
    final style = _compose(sources: const [_overview]);
    final sources = style['sources'] as Map<String, dynamic>;
    expect(sources.keys, ['overview']);
    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    // background + 2 Übersichts-Ebenen, sonst nichts.
    expect(layers, hasLength(3));
  });

  test('Raster-Quelle: Kachel-URL, 256er-Kacheln, Attribution — und die '
      'Raster-Ebene liegt ÜBER allen Vektor-Ebenen', () {
    final style = jsonDecode(composeMapLibreStyle(
      baseStyle: _baseStyle(),
      glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
      backgroundColor: '#e2dfda',
      sources: const [_overview],
      rasterSources: const [_osm],
    )) as Map<String, dynamic>;
    final sources = style['sources'] as Map<String, dynamic>;
    final osm = sources['osm'] as Map<String, dynamic>;
    expect(osm['type'], 'raster');
    expect(osm['tiles'], ['https://tile.openstreetmap.org/{z}/{x}/{y}.png']);
    expect(osm['tileSize'], 256,
        reason: 'OSM liefert 256er-Kacheln; MapLibres Standard sind 512 — '
            'ohne die Angabe wäre die Karte eine Zoomstufe daneben.');
    expect(osm['maxzoom'], 19);
    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    expect(layers.last['type'], 'raster',
        reason: 'Online-Kacheln über der Übersicht: Wo eine OSM-Kachel '
            'lädt, deckt sie den fremden Kartenstil darunter ab (#137).');
    expect(layers.last['source'], 'osm');
  });

  test('gleiche Attribution steht nur an EINER Quelle — sonst stapelt das '
      'Attributions-Widget je Quelle eine identische Zeile', () {
    final style = jsonDecode(composeMapLibreStyle(
      baseStyle: _baseStyle(),
      glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
      backgroundColor: '#e2dfda',
      sources: const [_overview, _bayern],
      rasterSources: const [_osm],
    )) as Map<String, dynamic>;
    final sources = style['sources'] as Map<String, dynamic>;
    final attributions = sources.values
        .map((s) => (s as Map)['attribution'])
        .whereType<String>()
        .toList();
    expect(attributions, hasLength(1),
        reason: 'Am Gerät standen vier identische „© OpenStreetMap"-Zeilen '
            'übereinander — eine je Quelle. Rechtlich genügt eine.');
  });

  test('nur Raster (Online-Normalfall): keine Vektor-Ebenen, kein Glyphs-Zwang',
      () {
    final style = jsonDecode(composeMapLibreStyle(
      baseStyle: _baseStyle(),
      glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
      backgroundColor: '#e2dfda',
      sources: const [],
      rasterSources: const [_osm],
    )) as Map<String, dynamic>;
    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    // background + genau eine Raster-Ebene.
    expect(layers, hasLength(2));
    expect(layers.first['type'], 'background');
    expect(layers.last['type'], 'raster');
  });
}
