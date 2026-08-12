// Die Wald- und Artenzeile im Spot-Blatt (#213, #227).
//
// Gezielt auf die Section statt durch die ganze App: Geprüft werden vier
// Formulierungen und drei Fälle, in denen bewusst NICHTS steht. Dass die
// Section auch wirklich im Blatt hängt, hält der Flow-Test in
// `flows/here_sheet_flow_test.dart` fest.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_block_providers.dart';
import 'package:pilzbuddy/features/map/forest_blocks.dart';
import 'package:pilzbuddy/features/map/forest_species.dart';
import 'package:pilzbuddy/features/map/forest_species_providers.dart';
import 'package:pilzbuddy/features/spots/widgets/spot_forest_section.dart';

import 'forest_grid_test.dart' show forestOf;
import 'forest_species_test.dart' show speciesOf;

void main() {
  // Der Mittelpunkt der ersten Zelle des ARTENGITTERS. Das ist der
  // kleinere der beiden Kästen (seine Ausdehnung folgt aus den
  // Zellschritten), und ein Punkt außerhalb bekäme still keine
  // Artenzeile — beim ersten Anlauf genau so passiert.
  const lat = 55 - 0.002 * (2 / 3);
  const lon = 10 + 0.004 * 0.5;

  /// [conifer] ist der Byte-Wert des Waldgitters: 0 = kein Wald,
  /// sonst 1 + Nadelanteil in Prozent.
  Future<void> pumpSection(
    WidgetTester tester, {
    required int conifer,
    int? speciesByte,
  }) async {
    final forest = forestOf([
      [conifer, conifer],
      [conifer, conifer],
    ], west: 10, east: 14, north: 55, south: 47);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        forestViewProvider.overrideWithValue(ForestView(base: forest)),
        forestSpeciesGridProvider.overrideWith((ref) async => speciesByte ==
                null
            ? null
            : speciesOf([
                [speciesByte, speciesByte],
                [speciesByte, speciesByte],
              ], west: 10, north: 55)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SpotForestSection(lat: lat, lon: lon)),
      ),
    ));
    await tester.pump();
  }

  testWidgets('Wald mit beiden Arten — Nadel zuerst im Nadelwald',
      (tester) async {
    // 81 % Nadel, Fichte (Lo 1) und Buche (Hi 1).
    await pumpSection(tester, conifer: 82, speciesByte: 0x11);
    expect(find.textContaining('überwiegend Nadelwald (81 % Nadel)'),
        findsOneWidget);
    expect(find.textContaining('Bäume: Fichte und Buche · Stand 2022'),
        findsOneWidget);
  });

  testWidgets('im Laubwald steht der Laubbaum vorn', (tester) async {
    // 20 % Nadel, dieselben zwei Arten — nur die Reihenfolge dreht sich.
    await pumpSection(tester, conifer: 21, speciesByte: 0x11);
    expect(find.textContaining('überwiegend Laubwald (20 % Nadel)'),
        findsOneWidget);
    expect(find.textContaining('Bäume: Buche und Fichte'), findsOneWidget);
  });

  testWidgets('nur eine Art: keine Aufzählung', (tester) async {
    await pumpSection(tester, conifer: 96, speciesByte: 0x02);
    expect(find.textContaining('Bäume: Kiefer · Stand 2022'), findsOneWidget);
    expect(find.textContaining(' und '), findsNothing);
  });

  testWidgets('kein Wald, aber Bäume: „Einzelne Bäume"', (tester) async {
    // Der gemessene Waldrand-Fall (3,9 %, #227). Schweigen wäre hier
    // schlechter — eine Eiche am Wiesenrand ist ein Hinweis.
    await pumpSection(tester, conifer: 0, speciesByte: 0x20);
    expect(find.textContaining('kein Wald'), findsOneWidget);
    expect(find.textContaining('Einzelne Bäume: Eiche'), findsOneWidget);
  });

  testWidgets('ohne Artengitter bleibt die Waldzeile allein',
      (tester) async {
    // Österreich und die Schweiz, und jedes kaputte Asset: Die Waldzeile
    // darf davon nicht abhängen.
    await pumpSection(tester, conifer: 50, speciesByte: null);
    expect(find.textContaining('Mischwald'), findsOneWidget);
    expect(find.textContaining('Bäume'), findsNothing);
  });

  testWidgets('keine Aussage im Artengitter: keine zweite Zeile',
      (tester) async {
    await pumpSection(tester, conifer: 50, speciesByte: speciesNoData);
    expect(find.textContaining('Mischwald'), findsOneWidget);
    expect(find.textContaining('Bäume'), findsNothing);
  });

  testWidgets('Kronenverlust wird noch nicht angezeigt', (tester) async {
    // Reserviert, nicht angezeigt (#227): Wo der Kahlschlag anhält, sagt
    // das neuere Waldgitter ohnehin „kein Wald". Dieser Test hält die
    // Entscheidung fest — wer sie umdreht, muss ihn anfassen.
    await pumpSection(tester, conifer: 0, speciesByte: speciesCanopyLoss);
    expect(find.textContaining('kein Wald'), findsOneWidget);
    expect(find.textContaining('Bäume'), findsNothing);
    expect(find.textContaining('Kronenverlust'), findsNothing);
  });
}
