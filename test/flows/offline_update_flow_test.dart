// Szenarien für das „Karten-Abo": Banner bei veralteter Offline-Karte,
// Ein-Tap-Update und automatisches Offline-Schalten ohne Empfang.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_repository.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_offline_maps.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeOfflineMapRepository) outdatedSetup() {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    final offlineMaps = FakeOfflineMapRepository()
      ..installed.add(const InstalledMap(
        key: 'de_berlin',
        dateStamp: '20260101',
        sizeBytes: 70 * 1024 * 1024,
        filePath: '/fake/offline_maps/de_berlin_20260101.pmtiles',
      ));
    return (backend, offlineMaps);
  }

  testWidgets('Veraltete Karte zeigt das Abo-Banner, Ein-Tap-Update lädt neu',
      (tester) async {
    final (backend, offlineMaps) = outdatedSetup();
    await pumpApp(tester, backend, offlineMaps: offlineMaps);

    expect(
        find.text('🗺️ Neue Offline-Karte für Berlin verfügbar — antippen'),
        findsOneWidget);

    await tester.tap(
        find.text('🗺️ Neue Offline-Karte für Berlin verfügbar — antippen'));
    await settle(tester);

    expect(find.text('Installiert (Stand 1.1.2026) — Update verfügbar'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Berlin aktualisieren'));
    await settle(tester);

    expect(offlineMaps.installed.single.dateStamp, '20260320');
    expect(find.text('Installiert (Stand 20.3.2026)'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Aktuelle Karte zeigt kein Abo-Banner', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    final offlineMaps = FakeOfflineMapRepository()
      ..installed.add(const InstalledMap(
        key: 'de_berlin',
        dateStamp: '20260320',
        sizeBytes: 70 * 1024 * 1024,
        filePath: '/fake/offline_maps/de_berlin_20260320.pmtiles',
      ));
    await pumpApp(tester, backend, offlineMaps: offlineMaps);

    expect(find.textContaining('Neue Offline-Karte'), findsNothing);
  });

  test('noConnectivityProvider erkennt fehlenden Empfang', () async {
    final container = ProviderContainer(overrides: [
      connectivityProvider.overrideWith(
          (ref) => Stream.value(const [ConnectivityResult.none])),
    ]);
    addTearDown(container.dispose);
    await container.read(connectivityProvider.future);
    expect(container.read(noConnectivityProvider), isTrue);

    final online = ProviderContainer(overrides: [
      connectivityProvider.overrideWith(
          (ref) => Stream.value(const [ConnectivityResult.wifi])),
    ]);
    addTearDown(online.dispose);
    await online.read(connectivityProvider.future);
    expect(online.read(noConnectivityProvider), isFalse);
  });
}
