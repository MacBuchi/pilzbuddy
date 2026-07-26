// Die unterste Kartenschicht (Issues #118/#119).
//
// Sie liegt seit #130 bei ALLEN Nutzern unter der Karte, nicht nur bei
// Offline-Nutzern — deshalb entscheidet ihr Render-Modus über die
// Bildrate der ganzen App. `raster` ist laut Paket-Doku der schnellste
// Modus; Schärfe verliert sie dabei nicht, weil ihre Daten bei Zoom 7
// enden und ohnehin immer hochskaliert werden.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'fakes/fake_backend.dart';
import 'fakes/test_app.dart';

/// Liefert leere Kacheln. Reicht: Geprüft wird die Verdrahtung des Layers,
/// nicht das Zeichnen — und der Renderer kommt mit leeren Tilesets klar.
class _EmptyTileProvider implements vmt.VectorTileProvider {
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

/// Der echte Provider entpackt ein Asset über `path_provider` — im Test
/// gibt es den Platform-Channel nicht, und die Schicht fiele still weg.
List<Override> _withBaseMap() {
  // Minimal, aber mit der Quelle „protomaps" — der Layer besteht sonst auf
  // einem Provider, der zum Thema passt.
  final theme = vtr.ThemeReader().read(jsonDecode('''
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
  return [
    baseMapStyleProvider.overrideWith((ref) async => OfflineMapStyle(
          theme: theme,
          tileProviders: vmt.TileProviders({'protomaps': _EmptyTileProvider()}),
        )),
  ];
}

void main() {
  testWidgets('Die Basiskarte rendert als Raster, nicht als Vektor',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend, extraOverrides: _withBaseMap());
    await settle(tester);

    final layer = tester.widget<vmt.VectorTileLayer>(
        find.byKey(const ValueKey('base-map')));

    expect(layer.layerMode, vmt.VectorTileLayerMode.raster,
        reason: 'Der Vektor-Modus rendert bei jeder Zwischen-Zoomstufe neu '
            '("can result in low frame rates", Paket-Doku) und kostet hier '
            'nichts an Schärfe — die Daten enden bei Zoom 7 (Issue #119).');
  });

  testWidgets('Die Basiskarte ersetzt fehlende Kacheln aus tieferen Stufen',
      (tester) async {
    // Ohne das läge unter dem Finger wieder eine leere Fläche — der
    // Kern von #118/#119.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend, extraOverrides: _withBaseMap());
    await settle(tester);

    final layer = tester.widget<vmt.VectorTileLayer>(
        find.byKey(const ValueKey('base-map')));

    expect(layer.maximumTileSubstitutionDifference, greaterThanOrEqualTo(3));
  });
}
