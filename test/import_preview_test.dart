// Smoke-Test und Design-Vorschau für den Wiederherstellungspfad des
// Imports (#112).
//
// Gleiches Muster wie `icon_preview_test.dart` und
// `season_preview_test.dart`: rendert den Bildschirm und schreibt mit
// `--dart-define=PILZ_PREVIEW_DIR=pfad` ein PNG für die Sichtprüfung.
// Ohne die Angabe ist es ein reiner Rendering-Test.
//
// Was ein Flow-Test nicht zeigt: ob die Liste lesbar ist, ob der Vermerk
// „hast du schon" auffällt und ob der Knopf am unteren Rand erreichbar
// bleibt.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/import_export/import_screen.dart';
import 'package:pilzbuddy/features/import_export/waypoint_parser.dart';

import 'fakes/fake_backend.dart';
import 'fakes/test_app.dart';

/// Lädt Roboto aus dem Flutter-SDK, damit im Bild echter Text steht statt
/// der Platzhalterkästchen des Testrenderers.
Future<void> loadRoboto() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      '/Volumes/MacStore/Programming/Flutter/SDK/flutter';
  final file =
      File('$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  if (!file.existsSync()) return;
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
  await loader.load();
}

void main() {
  testWidgets('der Wiederherstellungspfad rendert', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    if (const String.fromEnvironment('PILZ_PREVIEW_DIR').isNotEmpty) {
      await loadRoboto();
    }

    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    addTearDown(backend.dispose);
    // Einer davon liegt schon im Konto — er muss in der Liste als
    // Duplikat erkennbar sein.
    backend.addSpot(
        ownerId: me.id, lat: 51.2, lng: 10.4, name: 'Buchenhang');

    final waypoints = [
      ImportedWaypoint(name: 'Buchenhang', lat: 51.2, lng: 10.4, finds: [
        ImportedFind(species: 'Steinpilz', count: 5, foundOn: DateTime(2026, 7, 12)),
      ]),
      ImportedWaypoint(name: 'Fichtenkante', lat: 51.31, lng: 10.52, finds: [
        ImportedFind(species: 'Pfifferling', foundOn: DateTime(2026, 7, 20)),
        ImportedFind(species: 'Marone', count: 3, foundOn: DateTime(2026, 8, 1)),
        ImportedFind(species: 'Steinpilz', foundOn: DateTime(2026, 8, 4)),
      ]),
      const ImportedWaypoint(
          name: 'Alter Steinbruch am langen Weg',
          lat: 50.98,
          lng: 10.77,
          finds: []),
      // Ohne PilzBuddy-Daten: darf nicht anhakbar sein.
      const ImportedWaypoint(name: 'Aus einer fremden App', lat: 50.5, lng: 10.1),
    ];

    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesFor(backend),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: ImportScreen(initialWaypoints: waypoints),
        ),
      ),
    ));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('PilzBuddy-Sicherung erkannt'), findsOneWidget);

    const previewDir = String.fromEnvironment('PILZ_PREVIEW_DIR');
    if (previewDir.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$previewDir/import_preview.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
