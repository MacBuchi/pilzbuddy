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
import 'package:flutter_map/flutter_map.dart' show TileLayer;
import 'package:pilzbuddy/features/map/online_map.dart';
import 'package:pilzbuddy/features/offline_areas/area_providers.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import 'fakes/fake_backend.dart';
import 'fakes/fake_settings.dart';
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

/// Das OSM-Raster — nicht „irgendein TileLayer": Die Übersicht im
/// Raster-Modus bringt intern selbst einen mit.
Finder get _osm => find.byWidgetPredicate((w) =>
    w is TileLayer && (w.urlTemplate ?? '').contains('openstreetmap'));

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

  // Die Neue Karte vom Kartenhost (#630): derselbe Kartenstil wie die
  // Übersicht, also liegt sie darunter — und das OSM-Raster fällt weg.
  testWidgets('Neue Karte: Vektorkarte statt OSM, Übersicht darunter',
      (tester) async {
    await pumpApp(tester, _signedIn(), useRealMap: true, extraOverrides: [
      _baseMapAvailable(),
      onlineMapStyleProvider.overrideWith((ref) async => OfflineMapStyle(
            theme: protomapsTestTheme(),
            tileProviders:
                vmt.TileProviders({'protomaps': EmptyTileProvider()}),
          )),
    ]);
    await settle(tester);

    expect(_osm, findsNothing,
        reason: 'Mit der Neuen Karte kommt keine OSM-Kachel mehr.');
    expect(_baseMap, findsOneWidget);
    expect(find.byType(vmt.VectorTileLayer), findsNWidgets(2),
        reason: 'Übersicht UND die Online-Vektorkarte darüber.');
  });

  testWidgets(
      'Neue Karte ohne Empfang: KEIN OSM, nur die Übersicht (Feldbefund '
      '1.216.0 — der Browser gab alte OSM-Kacheln aus dem Cache)',
      (tester) async {
    await pumpApp(tester, _signedIn(),
        useRealMap: true,
        settings: FakeSettings(newMapEnabled: true),
        connectivity: const [ConnectivityResult.none],
        extraOverrides: [_baseMapAvailable()]);
    await settle(tester);

    expect(_osm, findsNothing,
        reason: 'Ein Flickenteppich im fremden Stil über der Übersicht ist '
            'genau die Mischung, die #137 verbietet.');
    expect(_baseMap, findsOneWidget);
  });

  testWidgets('Neue Karte nicht verfügbar ⇒ OSM wie bisher', (tester) async {
    await pumpApp(tester, _signedIn(), useRealMap: true, extraOverrides: [
      _baseMapAvailable(),
      onlineMapStyleProvider.overrideWith((ref) async => null),
    ]);
    await settle(tester);

    expect(_osm, findsOneWidget);
    expect(_baseMap, findsNothing);
  });

  // Gespeicherte Kartenbereiche (#630, Stufe 2): zuoberst, auch über OSM
  // — im Funkloch mit einem Balken kommt keine OSM-Kachel.
  testWidgets('Ein gespeicherter Bereich liegt als Schicht über OSM',
      (tester) async {
    final areaProviders =
        vmt.TileProviders({'protomaps': EmptyTileProvider()});
    await pumpApp(tester, _signedIn(), useRealMap: true, extraOverrides: [
      _baseMapAvailable(),
      areaMapStyleProvider.overrideWith((ref) async => OfflineMapStyle(
            theme: protomapsTestTheme(),
            tileProviders: areaProviders,
          )),
    ]);
    await settle(tester);

    final area = find.byKey(ValueKey(areaProviders));
    expect(area, findsOneWidget);
    expect(_osm, findsOneWidget);
    // Später im Baum = weiter oben gezeichnet.
    final order = [
      for (final e in find
          .byWidgetPredicate((w) =>
              w is vmt.VectorTileLayer ||
              (w is TileLayer &&
                  (w.urlTemplate ?? '').contains('openstreetmap')))
          .evaluate())
        e.widget,
    ];
    expect(order.last, isA<vmt.VectorTileLayer>());
    expect(order.indexWhere((w) => w is TileLayer),
        lessThan(order.length - 1));
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
