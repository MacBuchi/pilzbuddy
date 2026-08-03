// Baut das Style-Dokument der MapLibre-Engine — PUR, ohne I/O, damit
// vollständig testbar (map_style_composer_test.dart). Die produktisierte
// Fassung des Spike-Composers aus der MapLibre-Autopsie: Wer hier etwas
// falsch zusammensetzt, bekommt keine Fehlermeldung, sondern eine leere
// Karte. Alle Pfade, Zoombereiche und Farben liefert der Aufrufer
// (maplibre_style_provider.dart übernimmt das Lesen von Platte).
import 'dart:convert';

/// Eine PMTiles-Quelle für den Style: Pfad auf Platte plus Zoombereich.
///
/// Der Zoombereich kommt IMMER aus dem Archiv-Header (Byte 100/101), nie
/// aus den eingebetteten JSON-Metadaten — die lügen (0–15 bei einem
/// 0–7-Extract). Ohne korrektes `maxzoom` hält MapLibre Kacheln bis z22
/// für vorhanden, fragt sie an, bekommt nichts — und die Karte ist ab
/// der ersten fehlenden Stufe LEER statt hochskaliert.
class MapStyleSource {
  const MapStyleSource({
    required this.id,
    required this.filePath,
    required this.minZoom,
    required this.maxZoom,
  });

  final String id;
  final String filePath;
  final int minZoom;
  final int maxZoom;
}

/// Eine Online-Raster-Quelle (Kachel-URL-Vorlage, z. B. OSM).
class MapRasterSource {
  const MapRasterSource({
    required this.id,
    required this.urlTemplate,
    required this.maxZoom,
  });

  final String id;
  final String urlTemplate;
  final int maxZoom;
}

/// Setzt aus dem generierten Protomaps-Basis-Style und den Quellen EIN
/// Style-Dokument zusammen: eine background-Ebene im Landton, dann für
/// jede Quelle alle Nicht-background-Ebenen des Basis-Styles — in der
/// Reihenfolge der Quellenliste (Übersicht zuerst = unterste Schicht,
/// Regionen darüber; dieselbe Schichtung wie heute bei flutter_map).
/// [rasterSources] liegen als oberste Kartenschicht ÜBER allen
/// Vektor-Ebenen: Wo eine Online-Kachel lädt, deckt sie den fremden
/// Kartenstil darunter ab — zwei Stile nebeneinander sahen kaputter aus
/// als die leere Fläche, die sie verhindern sollten (#137).
///
/// Die background-Ebene des Basis-Styles wird bewusst NICHT je Quelle
/// übernommen: Sie malt deckend über die volle Kachelfläche und würde
/// alles darunter zudecken — dieselbe Lehre wie `styleWithoutBackground`
/// beim Canvas-Renderer (#119).
String composeMapLibreStyle({
  required Map<String, dynamic> baseStyle,
  required String glyphsUrl,
  required String backgroundColor,
  required List<MapStyleSource> sources,
  List<MapRasterSource> rasterSources = const [],
}) {
  final baseLayers = baseStyle['layers'] as List<dynamic>? ?? const [];

  // Attribution nur an der ERSTEN Quelle mit diesem Text: Das
  // Attributions-Widget listet jede Quellen-Attribution einzeln — vier
  // Quellen ergäben vier identische „© OpenStreetMap"-Zeilen
  // übereinander (am Gerät gesehen). Rechtlich genügt eine.
  final seenAttributions = <String>{};
  String? attributionOnce(String text) =>
      seenAttributions.add(text) ? text : null;

  final styleSources = <String, dynamic>{};
  final layers = <Map<String, dynamic>>[
    // Landton unter allem — Nachfolger von MapOptions.backgroundColor:
    // Wo (noch) keine Kachel liegt, sieht die Fläche nach „Karte lädt"
    // aus und nicht nach „kaputt".
    {
      'id': 'hintergrund',
      'type': 'background',
      'paint': {'background-color': backgroundColor},
    },
  ];

  for (final source in sources) {
    // Rechtspflicht (ODbL): der Text hängt an der Quelle, das
    // SourceAttribution-Widget zeigt ihn dauerhaft an.
    final attribution = attributionOnce('© OpenStreetMap contributors');
    styleSources[source.id] = {
      'type': 'vector',
      'url': 'pmtiles://file://${source.filePath}',
      'minzoom': source.minZoom,
      'maxzoom': source.maxZoom,
      'attribution': ?attribution,
    };
    layers.addAll(_layersFor(baseLayers, source.id));
  }

  for (final raster in rasterSources) {
    final attribution = attributionOnce('© OpenStreetMap contributors');
    styleSources[raster.id] = {
      'type': 'raster',
      'tiles': [raster.urlTemplate],
      // OSM liefert 256er-Kacheln; MapLibres Standard sind 512 — ohne
      // die Angabe läge die Beschriftungsgröße eine Zoomstufe daneben.
      'tileSize': 256,
      'maxzoom': raster.maxZoom,
      'attribution': ?attribution,
    };
    layers.add({
      'id': raster.id,
      'type': 'raster',
      'source': raster.id,
    });
  }

  return jsonEncode({
    ...baseStyle,
    'glyphs': glyphsUrl,
    'sources': styleSources,
    'layers': layers,
  });
}

/// Kopiert alle Nicht-background-Ebenen des Basis-Styles auf eine Quelle
/// um: Id mit Quellen-Präfix (Ids müssen im Style eindeutig sein),
/// `source` umgehängt, Schriften umgeschrieben.
List<Map<String, dynamic>> _layersFor(
    List<dynamic> baseLayers, String sourceId) {
  return [
    for (final layer in baseLayers.cast<Map<String, dynamic>>())
      if (layer['type'] != 'background')
        {
          ...(_rewriteFonts(layer)! as Map<String, dynamic>),
          'id': '$sourceId/${layer['id']}',
          'source': sourceId,
        },
  ];
}

/// Ersetzt die Schriftnamen des Protomaps-Styles durch die selbst
/// erzeugten Stacks aus `assets/map_glyphs/`. Läuft rekursiv über das
/// ganze Ebenen-Objekt, weil `text-font` auch in einem `case`-Ausdruck
/// stecken kann. Italic gibt es als eigenen Stack nicht — Regular ist
/// die ehrliche Näherung (Kartenbeschriftung, kein Fließtext).
Object? _rewriteFonts(Object? node) {
  if (node is String) {
    if (node == 'Noto Sans Medium') return 'noto-sans-medium';
    if (node == 'Noto Sans Regular' || node == 'Noto Sans Italic') {
      return 'noto-sans-regular';
    }
    return node;
  }
  if (node is List) return node.map(_rewriteFonts).toList();
  if (node is Map) {
    return <String, dynamic>{
      for (final e in node.entries) e.key as String: _rewriteFonts(e.value),
    };
  }
  return node;
}
