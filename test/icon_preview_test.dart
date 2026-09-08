import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/core/widgets/location_pin.dart';
import 'package:pilzbuddy/core/widgets/mushroom_avatar.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

/// Smoke-Test: Alle Icon-Varianten rendern ohne Fehler.
/// Mit `--dart-define=PILZ_PREVIEW_DIR=pfad` wird zusätzlich ein
/// Übersichtsbild (PNG) für den Design-Review gespeichert.
void main() {
  testWidgets('alle Pilz-Icon-Varianten rendern', (tester) async {
    await tester.binding.setSurfaceSize(const Size(760, 2600));
    final key = GlobalKey();

    final groups = <(String, SpeciesGroup?)>[
      for (final g in SpeciesGroup.values) (g.label, g),
      ('Unbekannt', null),
    ];

    // Arten mit eigenem Look (zusätzlich zur Gruppen-Zeile)
    const speciesRows = [
      'Pfifferling',
      'Herbsttrompete',
      'Edelreizker',
      'Lachsreizker',
      'Kiefernreizker',
      'Fichtenreizker',
      'Marone',
      'Steinpilz',
      'Samtfußrübling',
      'Netzstieliger Hexenröhrling',
      'Flockenstieliger Hexenröhrling',
      'Käppchenmorchel',
      'Morchelbecherling',
      'Böhmische Verpel',
      'Semmelstoppelpilz',
      'Habichtspilz',
      'Krause Glucke',
      'Ziegenbart',
      'Scheidenstreifling',
      'Igelstachelbart',
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
              const Divider(height: 8),
              // Der wartende Zustand (#267): halb durchsichtig mit Uhr,
              // in Marker-, Blatt- und Listengröße. Er muss auf einen
              // Blick als „noch nicht gesichert" lesbar sein, ohne dass
              // der Pilz darunter verschwindet.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 130,
                      child: Text('wartet (Korb)',
                          style: TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                    for (final group in [
                      SpeciesGroup.roehrlinge,
                      SpeciesGroup.leistlinge,
                      SpeciesGroup.wulstlinge,
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: MushroomIcon(
                            seed: 3, size: 44, group: group, pending: true),
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: MushroomIcon(
                          seed: 3,
                          size: 72,
                          group: SpeciesGroup.roehrlinge,
                          pending: true),
                    ),
                    const MushroomIcon(
                        seed: 3,
                        size: 30,
                        group: SpeciesGroup.roehrlinge,
                        pending: true),
                    const SizedBox(width: 6),
                    // Zum Vergleich derselbe Pilz, übertragen.
                    const MushroomIcon(
                        seed: 3, size: 44, group: SpeciesGroup.roehrlinge),
                  ],
                ),
              ),
              const Divider(height: 8),
              for (final name in speciesRows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(name,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ),
                      for (var seed = 0; seed < 3; seed++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: MushroomIcon(
                              seed: seed * 17 + 3,
                              size: 44,
                              group: groupFor(name),
                              species: name),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: MushroomIcon(
                            seed: 3,
                            size: 72,
                            group: groupFor(name),
                            species: name),
                      ),
                      MushroomIcon(
                          seed: 20,
                          size: 44,
                          group: groupFor(name),
                          species: name,
                          friend: true),
                      // Detail-Sheet-Größe: muss auch bei 30 px lesbar sein
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: MushroomIcon(
                            seed: 3,
                            size: 30,
                            group: groupFor(name),
                            species: name),
                      ),
                      // Listen-Größen (Fund-Zeile 28, Top-Arten 24) — ohne
                      // Boden, weil die Ellipse Karten-Sprache ist.
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: MushroomIcon.forSpecies(name),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: MushroomIcon.forSpecies(name, size: 24),
                      ),
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

  testWidgets('alle Avatare rendern (Katalog + Picker-Größen)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 560));
    final key = GlobalKey();

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Container(
          color: const Color(0xFFF1F8E9),
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < kAvatarCatalog.length; i++)
                MushroomAvatar(index: i, size: 64),
              // Unbekannte Arten (#417): Form und Farbe aus dem Seed,
              // dazu das Fragezeichen. Dieselben Größen wie in der App —
              // 44 px Karte, 30 px Blatt, 24 px Listenzeile.
              //
              // **Das Abzeichen erscheint hier als leeres Kästchen.** Im
              // Testlauf ist keine Icon-Schrift geladen (deshalb auch die
              // roten Balken statt Beschriftungen); dieselbe Anzeige hat
              // die Uhr des Ausgangskorbs, die in der App seit #267
              // funktioniert. Was dieses Bild BEANTWORTET, ist die Frage,
              // ob die Seed-Variation erhalten bleibt: Zwei eigene Arten
              // müssen verschieden aussehen, sonst hätte man auf der
              // Karte identische Marker für verschiedene Pilze.
              for (final size in [44.0, 30.0, 24.0])
                MushroomIcon.forSpecies('Mein Geheimpilz', size: size),
              for (final size in [44.0, 30.0, 24.0])
                MushroomIcon.forSpecies('Noch ein Rätsel', size: size),
              // Zum Vergleich eine BEKANNTE Art in denselben Größen …
              for (final size in [44.0, 30.0, 24.0])
                MushroomIcon.forSpecies('Steinpilz', size: size),
              // … und der wartende Eintrag, dessen Uhr gegen das
              // Fragezeichen gewinnt.
              const MushroomIcon(
                  seed: 3,
                  size: 44,
                  pending: true,
                  unknown: true,
                  species: 'Mein Geheimpilz'),
              // Robustheit: Index außerhalb des Katalogs fällt auf 0 zurück
              const MushroomAvatar(index: 999, size: 22),
              const MushroomAvatar(index: -1, size: 22),
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
        File('$previewDir/avatar_preview.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });

  testWidgets('Standort-Marker rendern (Tropfen, eigen und Buddy)',
      (tester) async {
    // #403: Die Spitze gehört auf die Koordinate. Angesehen wird das
    // Bild — die rote Linie markiert die Höhe, auf der die Spitzen
    // sitzen müssen; liegt ein Marker daneben, sieht man es sofort.
    await tester.binding.setSurfaceSize(const Size(560, 260));
    final key = GlobalKey();

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
              for (final (label, color) in [
                ('eigen', AppColors.forestGreen),
                ('Buddy', AppColors.friendBlue),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                          width: 60,
                          child: Text(label,
                              style: const TextStyle(fontSize: 11))),
                      for (final avatar in [0, 1, 4, 8, 24])
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: LocationPin(avatar: avatar, color: color),
                        ),
                      // Klein: so groß wie ein Listen-Eintrag
                      LocationPin(avatar: 0, color: color, headSize: 24),
                    ],
                  ),
                ),
              Container(height: 2, color: Colors.red),
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
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$previewDir/location_pin_preview.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
