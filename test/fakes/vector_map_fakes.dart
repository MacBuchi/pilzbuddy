// Bausteine für Tests am Vektor-Kartenstapel: ein Provider, der leere
// Kacheln liefert, und ein minimales Thema dazu. Beides bewusst so klein
// wie möglich — geprüft wird die Verdrahtung der Layer, nicht das Zeichnen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Liefert leere Kacheln. Reicht: Der Renderer kommt mit leeren Tilesets
/// klar, und die Tests fragen nach der Schicht, nicht nach ihrem Inhalt.
class EmptyTileProvider implements vmt.VectorTileProvider {
  @override
  Future<Uint8List> provide(vmt.TileIdentity tile) async => Uint8List(0);

  @override
  int get maximumZoom => 7;

  @override
  int get minimumZoom => 0;

  @override
  vmt.TileOffset get tileOffset => vmt.TileOffset.DEFAULT;

  @override
  vmt.TileProviderType get type => vmt.TileProviderType.vector;
}

/// Minimal, aber mit der Quelle „protomaps" — der Layer besteht sonst auf
/// einem Provider, der zum Thema passt.
vtr.Theme protomapsTestTheme() => vtr.ThemeReader().read(jsonDecode('''
{
  "version": 8,
  "layers": [
    {
      "id": "erde",
      "type": "fill",
      "source": "protomaps",
      "source-layer": "earth",
      "paint": {"fill-color": "#e2dfda"}
    }
  ]
}
''') as Map<String, dynamic>);
