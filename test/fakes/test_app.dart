// Startet die komplette App gegen das In-Memory-Backend: alle
// Repository-Provider werden mit Fakes überschrieben, der Karten-Kachel-
// Provider liefert ein transparentes 1×1-PNG (keine OSM-Requests) und der
// Update-Check ist stillgelegt. Damit laufen echte End-to-End-Abläufe
// (Login → Karte → Spot → Teilen) als schnelle Widget-Tests.
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pilzbuddy/app.dart';
import 'package:pilzbuddy/core/update_check.dart';
import 'package:pilzbuddy/data/providers.dart';
import 'package:pilzbuddy/features/map/map_screen.dart';
import 'package:pilzbuddy/features/map/position_provider.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';

import 'fake_backend.dart';
import 'fake_offline_maps.dart';

/// 1×1 transparentes PNG als Offline-Kartenkachel.
final Uint8List kTransparentTile = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(kTransparentTile);
}

/// Test-Position ohne Geolocator-Plugin (alle Pflichtfelder gefüllt).
Position fakePosition(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );

List<Override> overridesFor(FakeBackend backend,
        {FakeOfflineMapRepository? offlineMaps,
        List<ConnectivityResult> connectivity = const [
          ConnectivityResult.wifi
        ],
        Position? position}) =>
    [
      positionStreamProvider.overrideWith((ref) => Stream.value(position)),
      offlineMapRepositoryProvider
          .overrideWithValue(offlineMaps ?? FakeOfflineMapRepository()),
      connectivityProvider.overrideWith((ref) => Stream.value(connectivity)),
      // Wartezeiten des Download-Managers testtauglich verkürzen.
      mapDownloadDelaysProvider.overrideWithValue((
        retry: const Duration(milliseconds: 50),
        networkPoll: const Duration(milliseconds: 50),
      )),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
      spotRepositoryProvider.overrideWithValue(FakeSpotRepository(backend)),
      profileRepositoryProvider
          .overrideWithValue(FakeProfileRepository(backend)),
      friendRepositoryProvider.overrideWithValue(FakeFriendRepository(backend)),
      feedbackRepositoryProvider
          .overrideWithValue(FakeFeedbackRepository(backend)),
      tileProviderFactoryProvider.overrideWithValue(FakeTileProvider.new),
      updateInfoProvider.overrideWith((ref) => Future.value(null)),
    ];

/// App starten und die Intro-Animation (2,6 s) durchlaufen lassen.
Future<void> pumpApp(WidgetTester tester, FakeBackend backend,
    {FakeOfflineMapRepository? offlineMaps,
    List<ConnectivityResult> connectivity = const [
      ConnectivityResult.wifi
    ],
    Position? position}) async {
  addTearDown(backend.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: overridesFor(backend,
        offlineMaps: offlineMaps,
        connectivity: connectivity,
        position: position),
    child: const PilzBuddyApp(),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await settle(tester);
}

/// Feste Frames statt pumpAndSettle — die Buddy-Pilze auf dem Login-Screen
/// animieren endlos, pumpAndSettle würde dort nie zurückkehren.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// SnackBar-Timer auslaufen lassen, damit am Testende nichts mehr tickt.
Future<void> drainSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}
