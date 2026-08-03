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

const _radar = MapImageOverlay(
  id: 'regenradar',
  url: 'https://maps.dwd.de/geoserver/dwd/wms?REQUEST=GetMap'
      '&BBOX=612257,5700583,1948091,7459517&WIDTH=1024&HEIGHT=1348',
  west: 5.5,
  south: 45.5,
  east: 17.5,
  north: 55.5,
  opacity: 0.6,
  attribution: '© Deutscher Wetterdienst',
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

  // Der Flexibilitätsbeweis der Migration: ein halbtransparentes
  // Raster-Overlay (DWD-Regenradar) als OBERSTE Kartenschicht — der Weg,
  // über den später Niederschlag (#156/#158) und Waldarten hereinkommen.
  group('Overlay', () {
    Map<String, dynamic> compose() => jsonDecode(composeMapLibreStyle(
          baseStyle: _baseStyle(),
          glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
          backgroundColor: '#e2dfda',
          sources: const [_overview],
          rasterSources: const [_osm],
          overlays: const [_radar],
        )) as Map<String, dynamic>;

    test('liegt als oberste Ebene über Basis-Raster und Vektor', () {
      final layers =
          (compose()['layers'] as List).cast<Map<String, dynamic>>();
      expect(layers.last['id'], 'regenradar');
      expect(layers.last['type'], 'raster');
      // Direkt darunter das Basis-Raster — Overlay schlägt alles.
      expect(layers[layers.length - 2]['source'], 'osm');
    });

    test('halbtransparent: raster-opacity aus dem Overlay-Objekt', () {
      final layers =
          (compose()['layers'] as List).cast<Map<String, dynamic>>();
      expect((layers.last['paint'] as Map)['raster-opacity'], 0.6,
          reason: 'Deckend würde das Radar die Karte darunter auslöschen — '
              'der Regen soll ÜBER der Landschaft liegen, nicht statt ihr.');
    });

    test('nächster Nachbar statt Interpolation', () {
      final layers =
          (compose()['layers'] as List).cast<Map<String, dynamic>>();
      expect((layers.last['paint'] as Map)['raster-resampling'], 'nearest',
          reason: 'Die DWD-Produkte sind ein 1-km-Raster. Weichgezeichnet '
              'sähe die Ebene genauer aus, als sie ist.');
    });

    test('IMAGE-Source mit vier Ecken im Uhrzeigersinn ab oben links — '
        'maplibre-native kennt keine WMS-Kachel-Vorlagen', () {
      final sources = compose()['sources'] as Map<String, dynamic>;
      final radar = sources['regenradar'] as Map<String, dynamic>;
      expect(radar['type'], 'image');
      expect(radar['url'], contains('maps.dwd.de'));
      expect(radar['coordinates'], [
        [5.5, 55.5],
        [17.5, 55.5],
        [17.5, 45.5],
        [5.5, 45.5],
      ]);
    });

    test('Overlay-Attribution fährt bei der ersten Quelle mit — eine '
        'image-Source kennt kein attribution-Feld', () {
      final sources = compose()['sources'] as Map<String, dynamic>;
      final overview = sources['overview'] as Map<String, dynamic>;
      expect(overview['attribution'], contains('OpenStreetMap'));
      expect(overview['attribution'], contains('Wetterdienst'));
      expect(sources['regenradar'], isNot(contains('attribution')));
    });

    test('ohne Overlay-Liste ändert sich nichts am Style', () {
      final without = composeMapLibreStyle(
        baseStyle: _baseStyle(),
        glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
        backgroundColor: '#e2dfda',
        sources: const [_overview],
        rasterSources: const [_osm],
      );
      final withEmpty = composeMapLibreStyle(
        baseStyle: _baseStyle(),
        glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
        backgroundColor: '#e2dfda',
        sources: const [_overview],
        rasterSources: const [_osm],
        overlays: const [],
      );
      expect(withEmpty, without);
    });
  });
}
