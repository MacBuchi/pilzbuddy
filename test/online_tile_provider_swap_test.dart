// Nach einem Ausflug in den Offline-Modus (auch dem automatischen bei
// Empfangsverlust) muss der Online-Layer einen FRISCHEN TileProvider
// bekommen: flutter_map ruft beim Aushängen des TileLayer
// `tileProvider.dispose()` auf und schließt damit dessen HTTP-Client.
// Die alte Instanz weiterzureichen heißt: Jede frische Kachel scheitert
// bis zum App-Neustart, nur der Platten-Cache liefert noch — Bereiche
// erscheinen und verschwinden je nach Zoomstufe und Gegend (#157,
// „graue Kacheln auch online").
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/map_view/flutter_map_view.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import 'fakes/fake_backend.dart';
import 'fakes/test_app.dart';
import 'fakes/vector_map_fakes.dart';

/// Schaltbarer Offline-Zustand: null = online (OSM-Layer), sonst offline.
final _offlineSwitch = StateProvider<OfflineMapStyle?>((ref) => null);

OfflineMapStyle _style() => OfflineMapStyle(
      theme: protomapsTestTheme(),
      tileProviders: vmt.TileProviders({'protomaps': EmptyTileProvider()}),
    );

void main() {
  testWidgets(
      'Nach dem Offline-Ausflug bekommt der TileLayer eine frische '
      'Provider-Instanz', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    var created = 0;
    await pumpApp(tester, backend, useRealMap: true, extraOverrides: [
      tileProviderFactoryProvider.overrideWithValue(() {
        created++;
        return FakeTileProvider();
      }),
      offlineMapStyleProvider
          .overrideWith((ref) async => ref.watch(_offlineSwitch)),
    ]);

    final first = tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider;
    expect(created, 1);

    // Empfang weg → Auto-Offline: der TileLayer verschwindet und flutter_map
    // entsorgt seinen Provider (schließt den HTTP-Client).
    final container =
        ProviderScope.containerOf(tester.element(find.byType(FlutterMap)));
    container.read(_offlineSwitch.notifier).state = _style();
    await settle(tester);
    expect(find.byType(TileLayer), findsNothing,
        reason: 'Im Offline-Modus darf kein OSM-Layer eingehängt sein.');

    // Empfang zurück → Online. Die entsorgte Instanz wäre eine Leiche.
    container.read(_offlineSwitch.notifier).state = null;
    await settle(tester);
    final second =
        tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider;
    expect(identical(first, second), isFalse,
        reason: 'Die alte Instanz wurde beim Aushängen entsorgt — ihr '
            'HTTP-Client ist zu, jede frische Kachel würde scheitern.');
    expect(created, 2);
    // Der Vektor-Layer hinterlässt beim Aushängen einen einmaligen Timer,
    // den sein Dispose nicht abräumt (vector_map_tiles-Intern). Virtuelle
    // Zeit vorspulen, bis er abgelaufen ist, sonst schlägt die
    // Teardown-Prüfung auf hängende Timer an.
    await tester.pump(const Duration(minutes: 1));
  });
}
