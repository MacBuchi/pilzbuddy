// Startet die komplette App gegen das In-Memory-Backend: alle
// Repository-Provider werden mit Fakes überschrieben, der Karten-Kachel-
// Provider liefert ein transparentes 1×1-PNG (keine OSM-Requests) und der
// Update-Check ist stillgelegt. Damit laufen echte End-to-End-Abläufe
// (Login → Karte → Spot → Teilen) als schnelle Widget-Tests.
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/app.dart';
import 'package:pilzbuddy/core/update_check.dart';
import 'package:pilzbuddy/data/providers.dart';
import 'package:pilzbuddy/features/map/map_screen.dart';

import 'fake_backend.dart';

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

List<Override> overridesFor(FakeBackend backend) => [
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
Future<void> pumpApp(WidgetTester tester, FakeBackend backend) async {
  addTearDown(backend.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: overridesFor(backend),
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
