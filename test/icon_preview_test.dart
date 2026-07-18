import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

/// Smoke-Test: Alle Icon-Varianten rendern ohne Fehler.
/// Mit `--dart-define=PILZ_PREVIEW_DIR=pfad` wird zusätzlich ein
/// Übersichtsbild (PNG) für den Design-Review gespeichert.
void main() {
  testWidgets('alle Pilz-Icon-Varianten rendern', (tester) async {
    await tester.binding.setSurfaceSize(const Size(760, 1080));
    final key = GlobalKey();

    final groups = <(String, SpeciesGroup?)>[
      for (final g in SpeciesGroup.values) (g.label, g),
      ('Unbekannt', null),
    ];

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Container(
          color: const Color(0xFFE8E0D0), // kartenähnlicher Hintergrund
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, group) in groups)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(label,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ),
                      // Marker-Größe 44 px in fünf Seed-Varianten
                      for (var seed = 0; seed < 5; seed++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: MushroomIcon(
                              seed: seed * 17 + 3, size: 44, group: group),
                        ),
                      // einmal groß + einmal als Freundes-Variante
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: MushroomIcon(seed: 3, size: 72, group: group),
                      ),
                      MushroomIcon(
                          seed: 20, size: 44, group: group, friend: true),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    const previewDir = String.fromEnvironment('PILZ_PREVIEW_DIR');
    if (previewDir.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$previewDir/mushroom_preview.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
