// Smoke-Test und Design-Vorschau für den Saison-Abschnitt.
//
// Gleiches Muster wie `icon_preview_test.dart`: Der Test rendert alle
// Fälle, die der Abschnitt annehmen kann, und schreibt mit
// `--dart-define=PILZ_PREVIEW_DIR=pfad` zusätzlich ein PNG für die
// Sichtprüfung. Ohne die Angabe ist es ein reiner Rendering-Test.
//
// Warum als Bild und nicht im Browser: Der Abschnitt hängt an keinem
// Backend — seine Zahlen liegen im Binary. Ein Web-Lauf bräuchte Login
// und einen Spot und zeigte am Ende dasselbe.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/widgets/species_season_section.dart';

/// Lädt Roboto aus dem Flutter-SDK, damit im Vorschaubild echter Text
/// steht statt der Platzhalterkästchen.
///
/// Ohne das rendert der Testrenderer jede Zeile als schwarze Blöcke —
/// man sieht die Umbrüche, aber nicht, was dasteht. Bei einem Abschnitt,
/// dessen heikelster Teil die **Formulierung** ist, ist das der halbe
/// Zweck der Vorschau. Nur für das Bild: Fehlt die Datei, läuft der Test
/// weiter, dann eben mit Kästchen.
Future<void> loadRoboto() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      '/Volumes/MacStore/Programming/Flutter/SDK/flutter';
  final file = File('$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  if (!file.existsSync()) return;
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
  await loader.load();
}

void main() {
  testWidgets('der Saison-Abschnitt rendert in allen Ausprägungen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1500));
    final key = GlobalKey();
    if (const String.fromEnvironment('PILZ_PREVIEW_DIR').isNotEmpty) {
      await loadRoboto();
    }

    // Die Fälle, die sich im Aussehen unterscheiden — jeder einmal.
    const cases = <(String, String?)>[
      ('Ein Gipfel über zwei Monate', 'Steinpilz'),
      ('Der Melder-Effekt korrigiert (Juli, nicht August)', 'Pfifferling'),
      ('Gipfel über den Jahreswechsel', 'Austernseitling'),
      ('Ein einzelner Monat', 'Speisemorchel'),
      ('Ein Sammelbegriff (Gattung)', 'Rotkappe'),
      ('Ein Zweitname erbt seine Kurve', 'Marone'),
      ('Ein langer Artname', 'Flockenstieliger Hexenröhrling'),
      ('Zu dünn belegt — nichts', 'Igelstachelbart'),
      ('Freitext-Art — nichts', 'Omas Geheimpilz'),
      ('Kein Fund — nichts', null),
    ];

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (label, species) in cases) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.deepOrange)),
                    ),
                    // Fester Tag, damit die Hervorhebung des laufenden
                    // Monats im Bild reproduzierbar ist.
                    SpeciesSeasonSection(
                        species: species, today: DateTime(2026, 8, 5)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // Der Smoke-Teil: Kein Überlauf, keine Ausnahme beim Zeichnen.
    expect(tester.takeException(), isNull);

    const previewDir = String.fromEnvironment('PILZ_PREVIEW_DIR');
    if (previewDir.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$previewDir/season_preview.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
