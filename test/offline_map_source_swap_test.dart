// Der Quellenwechsel der Offline-Karte (Issue #144).
//
// `_offlineTileSourceProvider` schließt beim Neuaufbau die PMTiles-Archive
// — und neu aufgebaut wird er bei jedem App-Resume, weil `_refreshData()`
// dann `installedMapsProvider` invalidiert. `vector_map_tiles` prüft beim
// Aktualisieren aber nur Theme, Sprites, tileOffset, layerMode und
// maximumZoom (`hasRenderDifferences`); ein Wechsel der `tileProviders`
// fällt durch. Ohne eigenen Schlüssel behielte der Layer also seine Caches
// samt der gerade geschlossenen Archive, und ab da wirft jede Kachel
// „withResource() may not be called on a closed Pool" — gemessen 121-mal
// in einem Stresslauf auf dem Pixel 7 Pro, bis zum App-Neustart.
//
// Zwei Zusagen hält dieser Test fest:
//
// * Eine neue Quelle ⇒ ein neuer Layer (frische Caches auf offenen Archiven).
// * Ein doch noch gefragtes, geschlossenes Archiv meldet „Kachel fehlt"
//   statt eines unbehandelten Fehlers pro Kachel.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:pilzbuddy/features/offline_maps/pmtiles_tile_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import 'fakes/fake_backend.dart';
import 'fakes/test_app.dart';
import 'fakes/vector_map_fakes.dart';

/// Die mitgelieferte Übersicht — ein echtes PMTiles-Archiv, damit der Test
/// nicht gegen eine Attrappe des Fehlerfalls prüft.
const _archivePath = 'assets/offline_maps/overview_dach.pmtiles';

/// Hochzählen erzwingt eine neue Generation der Offline-Quelle, so wie es
/// der echte Provider tut, wenn er die Archive neu öffnet.
final _sourceGeneration = StateProvider<int>((ref) => 0);

Override _swappableOfflineMap() =>
    offlineMapStyleProvider.overrideWith((ref) async {
      ref.watch(_sourceGeneration);
      // Bewusst bei jedem Durchlauf frische Objekte: Genau daran — und nur
      // daran — kann der Layer den Wechsel erkennen.
      return OfflineMapStyle(
        theme: protomapsTestTheme(),
        tileProviders: vmt.TileProviders({'protomaps': EmptyTileProvider()}),
      );
    });

/// Der Detail-Layer ist der im Vektor-Modus; die Übersicht darunter
/// rendert als Raster (#119).
Finder get _detailMap => find.byWidgetPredicate((widget) =>
    widget is vmt.VectorTileLayer &&
    widget.layerMode == vmt.VectorTileLayerMode.vector);

FakeBackend _signedIn() {
  final backend = FakeBackend();
  final me = backend.addUser(username: 'testpilz');
  backend.signInAs(me.id);
  return backend;
}

void main() {
  testWidgets('Eine neue Kachelquelle ersetzt den Detail-Layer',
      (tester) async {
    await pumpApp(tester, _signedIn(),
        extraOverrides: [_swappableOfflineMap()]);
    await settle(tester);

    expect(_detailMap, findsOneWidget);
    final before = tester.element(_detailMap);

    ProviderScope.containerOf(before, listen: false)
        .read(_sourceGeneration.notifier)
        .state++;
    await settle(tester);

    expect(_detailMap, findsOneWidget);
    expect(identical(tester.element(_detailMap), before), isFalse,
        reason: 'Der Layer muss samt Caches neu entstehen. Bleibt dasselbe '
            'Element stehen, hält er die Archive der alten Generation fest '
            '— die sind beim Neuaufbau geschlossen worden, und die '
            'Offline-Karte ist bis zum App-Neustart tot (Issue #144).');

    // Der frische Layer legt in `initState` einen 3-Sekunden-Timer an
    // (`applyConstraints`). Ihn ablaufen lassen, sonst endet der Test mit
    // einem offenen Timer — was übrigens genau beweist, dass hier wirklich
    // ein neuer Layer entstanden ist.
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
  });

  test('Ein geschlossenes Archiv meldet „Kachel fehlt" statt StateError',
      () async {
    final provider = await PmTilesVectorTileProvider.open(_archivePath);
    final tile = vmt.TileIdentity(0, 0, 0);

    expect(await provider.provide(tile), isNotEmpty,
        reason: 'Vor dem Schließen muss die Kachel wirklich kommen — sonst '
            'prüft der zweite Teil nichts.');

    await provider.close();

    await expectLater(
      provider.provide(tile),
      throwsA(isA<vmt.ProviderException>()
          .having((e) => e.statusCode, 'statusCode', 410)),
      reason: 'Der Lesepool von pmtiles wirft einen StateError. Ungefangen '
          'wäre das ein unbehandelter Fehler pro Kachel und damit eine '
          'Zeile in error_reports — 121 in einem einzigen Stresslauf.',
    );
  });
}
