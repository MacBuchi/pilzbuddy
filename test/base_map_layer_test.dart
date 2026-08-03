// Die unterste Kartenschicht (Issues #118/#119/#137).
//
// Zwei Regeln, die sich widersprechen könnten, und deshalb beide hier
// festgenagelt sind:
//
// * Unter den ONLINE-Kacheln liegt sie nicht (#137). Wo eine OSM-Kachel
//   schon lag und die nächste fehlte, standen zwei Kartenstile
//   nebeneinander — das sah kaputter aus als die leere Fläche.
// * Ohne Empfang liegt sie drin (#118). Dann kommt keine Kachel, es gibt
//   also nichts, womit sie sich mischen könnte, und sie ist der
//   Unterschied zwischen einer groben Karte und einer leeren Fläche.
//
// Ihr Render-Modus ist `raster`, weil sie bei allen mitläuft und ihre
// Daten bei Zoom 7 enden — hochskaliert wird ohnehin (#119).
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import 'fakes/fake_backend.dart';
import 'fakes/test_app.dart';
import 'fakes/vector_map_fakes.dart';

/// Der echte Provider entpackt ein Asset über `path_provider` — im Test
/// gibt es den Platform-Channel nicht, und die Schicht fiele still weg.
Override _baseMapAvailable() =>
    baseMapStyleProvider.overrideWith((ref) async => OfflineMapStyle(
          theme: protomapsTestTheme(),
          tileProviders: vmt.TileProviders({'protomaps': EmptyTileProvider()}),
        ));

/// Stellt eine geladene Offline-Karte nach (sonst hängt der Detail-Layer
/// an Archiven auf der Platte).
Override _offlineMapActive() =>
    offlineMapStyleProvider.overrideWith((ref) async => OfflineMapStyle(
          theme: protomapsTestTheme(),
          tileProviders: vmt.TileProviders({'protomaps': EmptyTileProvider()}),
        ));

Finder get _baseMap => find.byKey(const ValueKey('base-map'));

FakeBackend _signedIn() {
  final backend = FakeBackend();
  final me = backend.addUser(username: 'testpilz');
  backend.signInAs(me.id);
  return backend;
}

void main() {
  testWidgets('Mit Empfang und Online-Karte liegt keine Basiskarte darunter',
      (tester) async {
    await pumpApp(tester, _signedIn(), useRealMap: true,
        extraOverrides: [_baseMapAvailable()]);
    await settle(tester);

    expect(_baseMap, findsNothing,
        reason: 'Zwei Kartenstile nebeneinander sahen kaputter aus als die '
            'leere Fläche, die die Schicht verhindern sollte (Issue #137).');
  });

  testWidgets('Ohne Empfang liegt die Basiskarte drin', (tester) async {
    // Der Anlass von #118: Wald, kein Netz, noch keine Region geladen.
    await pumpApp(tester, _signedIn(), useRealMap: true,
        connectivity: const [ConnectivityResult.none],
        extraOverrides: [_baseMapAvailable()]);
    await settle(tester);

    expect(_baseMap, findsOneWidget,
        reason: 'Ohne Netz kommt keine OSM-Kachel — dann ist die Übersicht '
            'der Unterschied zwischen Karte und leerer Fläche.');
  });

  testWidgets('Bei aktiver Offline-Karte liegt sie ebenfalls drin',
      (tester) async {
    // Hier mischt sich nichts: Detailkarte und Übersicht nutzen dasselbe
    // Protomaps-Thema.
    await pumpApp(tester, _signedIn(), useRealMap: true,
        extraOverrides: [_baseMapAvailable(), _offlineMapActive()]);
    await settle(tester);

    expect(_baseMap, findsOneWidget);
  });

  testWidgets('Die Basiskarte rendert als Raster, nicht als Vektor',
      (tester) async {
    await pumpApp(tester, _signedIn(), useRealMap: true,
        connectivity: const [ConnectivityResult.none],
        extraOverrides: [_baseMapAvailable()]);
    await settle(tester);

    final layer = tester.widget<vmt.VectorTileLayer>(_baseMap);

    expect(layer.layerMode, vmt.VectorTileLayerMode.raster,
        reason: 'Der Vektor-Modus rendert bei jeder Zwischen-Zoomstufe neu '
            '("can result in low frame rates", Paket-Doku) und kostet hier '
            'nichts an Schärfe — die Daten enden bei Zoom 7 (Issue #119).');
    expect(layer.maximumTileSubstitutionDifference, 1,
        reason: 'In #118 stand hier 3, um graue Löcher zu schließen. Gemessen '
            'war genau das der Haupttreiber des Vektor-Speichers: Spitze '
            '512 → 224 MB, GPU 188 → 37 MB (Issue #142). Löcher entstehen '
            'dadurch keine — das Hochskalieren der Übersicht kommt vom '
            '`maximumZoom = 7` des Providers, nicht von der Substitution. '
            'Wer den Wert wieder anhebt, muss vorher messen.');
  });
}
