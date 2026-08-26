// Szenarien für das „Karten-Abo": Banner bei veralteter Offline-Karte,
// Ein-Tap-Update, automatisches Offline-Schalten ohne Empfang — und der
// Nachlauf ohne Tippen (#332).
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_repository.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_offline_maps.dart';
import '../fakes/fake_settings.dart';
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

  // ---------------------------------------------------------------
  // Der Nachlauf ohne Tippen (#332)
  // ---------------------------------------------------------------

  const wifi = [ConnectivityResult.wifi];
  const mobile = [ConnectivityResult.mobile];
  const nothing = [ConnectivityResult.none];

  group('isFreeNetwork', () {
    test('WLAN ohne Datenkosten ist frei', () {
      expect(isFreeNetwork(wifi, metered: false), isTrue);
      expect(isFreeNetwork(const [ConnectivityResult.ethernet], metered: false),
          isTrue);
    });

    test('ein Handy-Hotspot ist WLAN und trotzdem nicht frei', () {
      // Der ganze Grund für den Metered-Kanal: `connectivity_plus` sieht
      // hier WLAN, und die Karte kostet trotzdem fremdes Datenvolumen.
      expect(isFreeNetwork(wifi, metered: true), isFalse);
    });

    test('Mobilfunk ist nie frei, auch nicht als „unbegrenzt"', () {
      expect(isFreeNetwork(mobile, metered: false), isFalse);
      expect(isFreeNetwork(const [...wifi, ...mobile], metered: false), isFalse);
    });

    test('ohne Verbindung ist nichts frei', () {
      expect(isFreeNetwork(const [], metered: false), isFalse);
      expect(isFreeNetwork(nothing, metered: false), isFalse);
    });
  });

  group('planAutoMapUpdate', () {
    const berlin = AvailableMap(
      key: 'de_berlin',
      dateStamp: '20260320',
      sizeBytes: 76 * 1024 * 1024,
      downloadUrl: 'https://example.invalid/de_berlin_20260320.pmtiles',
    );

    ({AvailableMap? start, List<String> pause}) plan({
      bool enabled = true,
      bool freeNetwork = true,
      bool inForeground = true,
      List<AvailableMap> outdated = const [berlin],
      Set<String> running = const {},
      Set<String> autoStarted = const {},
      Set<String> failed = const {},
    }) =>
        planAutoMapUpdate(
          enabled: enabled,
          freeNetwork: freeNetwork,
          inForeground: inForeground,
          outdated: outdated,
          running: running,
          autoStarted: autoStarted,
          failed: failed,
        );

    test('im freien Netz mit veralteter Region: starten', () {
      expect(plan().start, berlin);
    });

    test('ohne Schalter, ohne freies Netz, im Hintergrund: nichts', () {
      expect(plan(enabled: false).start, isNull);
      expect(plan(freeNetwork: false).start, isNull);
      expect(plan(inForeground: false).start, isNull);
    });

    test('nichts Veraltetes, nichts zu tun', () {
      expect(plan(outdated: const []).start, isNull);
    });

    test('nie zwei auf einmal — auch nicht neben einem von Hand', () {
      expect(plan(running: const {'de_bayern'}).start, isNull);
    });

    test('eine in dieser Sitzung gescheiterte Region ruht', () {
      expect(plan(failed: const {'de_berlin'}).start, isNull);
    });

    test('fällt das freie Netz weg, wird der EIGENE Download angehalten', () {
      // Das ist der Punkt, den der geduldige Download-Manager sonst
      // verschluckt: Er setzt bei jeder zurückkehrenden Verbindung fort,
      // auch über Mobilfunk.
      final result = plan(
        freeNetwork: false,
        running: const {'de_berlin'},
        autoStarted: const {'de_berlin'},
      );
      expect(result.pause, ['de_berlin']);
      expect(result.start, isNull);
    });

    test('ein von Hand gestarteter Download wird NICHT angehalten', () {
      // Wer selbst getippt hat, hat sich für die Kosten entschieden.
      expect(
          plan(freeNetwork: false, running: const {'de_berlin'}).pause, isEmpty);
    });
  });

  testWidgets('freies WLAN: die veraltete Karte lädt von selbst nach',
      (tester) async {
    final (backend, offlineMaps) = outdatedSetup();
    await pumpApp(tester, backend,
        offlineMaps: offlineMaps,
        settings: FakeSettings(mapAutoUpdateEnabled: true));
    await settle(tester);

    expect(offlineMaps.installed.single.dateStamp, '20260320',
        reason: 'ohne einen einzigen Tipp');
    expect(offlineMaps.installed.map((m) => m.key), ['de_berlin'],
        reason: 'nur Regionen, die schon da waren — Bayern bleibt ungefragt '
            'liegen');
  });

  testWidgets('ohne Schalter passiert nichts von selbst', (tester) async {
    final (backend, offlineMaps) = outdatedSetup();
    await pumpApp(tester, backend, offlineMaps: offlineMaps);
    await settle(tester);

    expect(offlineMaps.downloadCalls, 0);
    expect(offlineMaps.installed.single.dateStamp, '20260101');
    expect(
        find.text('🗺️ Neue Offline-Karte für Berlin verfügbar — antippen'),
        findsOneWidget);
  });

  testWidgets('am Handy-Hotspot passiert nichts — WLAN hin oder her',
      (tester) async {
    final (backend, offlineMaps) = outdatedSetup();
    await pumpApp(tester, backend,
        offlineMaps: offlineMaps,
        settings: FakeSettings(mapAutoUpdateEnabled: true),
        metering: FakeNetworkMetering(metered: true));
    await settle(tester);

    expect(offlineMaps.downloadCalls, 0);
    expect(offlineMaps.installed.single.dateStamp, '20260101');
  });

  testWidgets('über Mobilfunk gar nicht erst nachfragen', (tester) async {
    final (backend, offlineMaps) = outdatedSetup();
    final metering = FakeNetworkMetering();
    await pumpApp(tester, backend,
        offlineMaps: offlineMaps,
        connectivity: mobile,
        metering: metering,
        settings: FakeSettings(mapAutoUpdateEnabled: true));
    await settle(tester);

    expect(offlineMaps.downloadCalls, 0);
    expect(metering.calls, 0,
        reason: 'der Transportweg entscheidet das schon — der Sprung nach '
            'Android bleibt aus');
  });

  testWidgets('fällt das WLAN weg, hält der Nachlauf an und macht später weiter',
      (tester) async {
    final (backend, offlineMaps) = outdatedSetup();
    // Lang genug, um den Download mitten im Lauf zu erwischen.
    offlineMaps.stepDelay = const Duration(seconds: 2);
    final connectivity = StreamController<List<ConnectivityResult>>();
    addTearDown(connectivity.close);
    await pumpApp(tester, backend,
        offlineMaps: offlineMaps,
        settings: FakeSettings(mapAutoUpdateEnabled: true),
        extraOverrides: [
          connectivityProvider.overrideWith((ref) => connectivity.stream),
        ]);

    connectivity.add(wifi);
    await settle(tester);
    expect(find.text('🗺️ Neue Offline-Karte wird geladen — antippen'),
        findsOneWidget,
        reason: '„antippen" allein wäre die Aufforderung zu etwas, das '
            'gerade läuft');

    connectivity.add(mobile);
    // Erst Frames, dann die Uhr: Riverpod stellt die Benachrichtigung
    // hinter das nächste Bild. Ein einzelnes `pump(3 s)` ließe den Timer
    // der Fake VOR dem Anhalten ablaufen, und der Download wäre fertig,
    // bevor jemand ihn stoppen konnte.
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(offlineMaps.installed.single.dateStamp, '20260101',
        reason: 'angehalten, nicht über Mobilfunk zu Ende geladen');
    expect(find.text('🗺️ Neue Offline-Karte für Berlin verfügbar — antippen'),
        findsOneWidget);

    offlineMaps.stepDelay = const Duration(milliseconds: 10);
    connectivity.add(wifi);
    await settle(tester);
    expect(offlineMaps.installed.single.dateStamp, '20260320',
        reason: 'mit dem freien Netz macht er von selbst weiter');
  });

  testWidgets('eine Region, die nicht kommt, läuft nicht endlos neu an',
      (tester) async {
    final (backend, offlineMaps) = outdatedSetup();
    offlineMaps
      ..stepDelay = const Duration(milliseconds: 1)
      ..failuresBeforeSuccess = 1000;
    await pumpApp(tester, backend,
        offlineMaps: offlineMaps,
        settings: FakeSettings(mapAutoUpdateEnabled: true));
    // Der Download-Manager ist geduldig (30 Anläufe) — erst danach gibt
    // er auf, und erst dann greift die Merkliste des Nachlaufs.
    await tester.pump(const Duration(seconds: 20));
    await settle(tester);

    final calls = offlineMaps.downloadCalls;
    expect(calls, greaterThan(0));
    await tester.pump(const Duration(seconds: 20));
    await settle(tester);
    expect(offlineMaps.downloadCalls, calls,
        reason: 'in dieser Sitzung ruht sie jetzt — von Hand geht sie '
            'weiterhin');
    expect(offlineMaps.installed.single.dateStamp, '20260101');
  });

  testWidgets('der Schalter merkt sich seine Stellung', (tester) async {
    final (backend, offlineMaps) = outdatedSetup();
    final settings = FakeSettings();
    await pumpApp(tester, backend, offlineMaps: offlineMaps,
        settings: settings);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);
    await tester.tap(find.text('Im WLAN von selbst aktualisieren'));
    await settle(tester);

    expect(settings.mapAutoUpdateEnabled, isTrue);
    await drainSnackbars(tester);
  });
}
