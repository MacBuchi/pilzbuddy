// Die Kombi-Ebene „Wald + Pilzwetter" (Betreiber-Wunsch 2026-08-09):
// dieselben Waben, aber die mit gutem Wetter leuchten — und zwar in der
// Farbe IHRER Waldklasse (seit 1.80.0, feste Tabelle statt einem Ton
// für alle).
//
// Geprüft wird an den PIXELN unter den Wabenmittelpunkten — dort ist
// jede Zellform eindeutig, und dort steht die Aussage, um die es geht:
// leuchtet diese Wabe, wie stark, und in welchem Wald.
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/ampel/ampel_fill.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/forest_fill.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart' show mercatorY;

import 'forest_grid_test.dart' show hexOf;
import 'rain_fill_test.dart' show decodePng;

/// Ein Stufen-Gitter über der Testbox: [rows] zeilenweise, Werte aus
/// [AmpelLevel] oder `null` für „keine Aussage".
///
/// Seit dem Zutaten-Umbau (Berchtesgaden 2026-08-17) trägt das Gitter
/// keine fertigen Stufen mehr — die gewünschte Stufe wird hier über
/// den Regenfaktor eingestellt (Mittel 13 °C ⇒ Glocke 1,0, der Score
/// IST der Regenfaktor): 1,0 → günstig, 0,3 → verhalten, 0,1 →
/// ungünstig. Stationshöhe 0, damit ohne Höhengitter nichts verschiebt.
AmpelLevels levelsOf(List<List<AmpelLevel?>> rows,
    {double west = 10,
    double east = 10.018,
    double north = 50,
    double south = 49.988,
    double meanC = 13.0}) {
  final flat = [for (final row in rows) ...row];
  return AmpelLevels([
    AmpelLevelGrid(
    // **Die Regenfaktoren kommen aus den Schwellen, nicht aus dem
    // Kopf.** Bei 13 °C ist die Herbst-Glocke 1,0, der Score also genau
    // der Regenfaktor — jeder Wert hier landet somit in der Stufe, die
    // danebensteht. Bis zum 2026-09-19 standen hier 0,1 / 0,3 / 1,0
    // fest; mit der Neukalibrierung (verhalten ab 0,389 statt 0,187)
    // wurde aus der 0,3 stillschweigend „ungünstig", und drei Tests
    // prüften plötzlich eine andere Aussage als ihren Namen.
    rainFactor: Float32List.fromList([
      for (final level in flat)
        switch (level) {
          null => 0,
          AmpelLevel.unguenstig => ampelHerbstClass.verhaltenAbove / 2,
          AmpelLevel.verhalten => (ampelHerbstClass.verhaltenAbove +
                  ampelHerbstClass.guenstigAbove) /
              2,
          AmpelLevel.guenstig => 1.0,
        },
    ]),
    // 13 °C, sofern der Test nichts anderes sagt — der Gipfel der
    // Herbstglocke, damit die Regenfaktoren oben ihre Stufe treffen.
    meanC: Float32List.fromList(List.filled(flat.length, meanC)),
    stationHeightM: Int16List(flat.length),
    valid: Uint8List.fromList([for (final l in flat) l == null ? 0 : 1]),
    width: rows.first.length,
    height: rows.length,
    west: west,
    east: east,
    north: north,
    south: south,
    newest: DateTime.utc(2026, 8, 9),
    ),
  ]);
}

void main() {
  // 4×4 Waben, überall Laubwald — so ist jeder Farbunterschied im Bild
  // das Wetter und nicht die Waldklasse.
  final forest = hexOf([
    for (var hy = 0; hy < 4; hy++) List<int>.filled(4, 11),
  ]);
  // Und dasselbe Gitter mit allen drei Klassen nebeneinander (Byte 11 =
  // Laub, 51 = Misch, 91 = Nadel, Schwellen in `classOfByte`).
  final gemischt = hexOf([
    for (var hy = 0; hy < 4; hy++) const [11, 51, 91, 11],
  ]);
  const window = FillWindow(
      west: 10, east: 10.018, north: 50, south: 49.988,
      width: 180, height: 120);

  ({int r, int g, int b, int a}) at(
      ({int width, int height, Uint8List pixels}) png, double lat, double lon) {
    final x = ((lon - window.west) / (window.east - window.west) * window.width)
        .floor();
    final f = (mercatorY(window.north) - mercatorY(lat)) /
        (mercatorY(window.north) - mercatorY(window.south));
    final y = (f * window.height).floor();
    final o = (y * png.width + x) * 4;
    return (
      r: png.pixels[o],
      g: png.pixels[o + 1],
      b: png.pixels[o + 2],
      a: png.pixels[o + 3],
    );
  }

  /// Die Farbe eines Wabenpixels als (r, g, b) — zum Vergleich mit den
  /// Tabellenwerten aus [AppColors.ampelCombined].
  (int, int, int) rgbOf(Color colour) => (
        (colour.r * 255).round(),
        (colour.g * 255).round(),
        (colour.b * 255).round(),
      );

  // Wabenmittelpunkte des Testgitters (odd-r, Spitze oben).
  double latOf(int hy) => 50 - 0.003 * (hy + 2 / 3);
  double lonOf(int hx, int hy) =>
      10 + 0.004 * (hx + 0.5 + (hy.isOdd ? 0.5 : 0.0));

  test('nur die Waben mit gutem Wetter leuchten — der Rest bleibt Wald', () {
    // Stufen-Gitter 2×2 über der Box: oben links günstig, oben rechts
    // verhalten, unten beides ungünstig.
    final png = decodePng(forestAmpelFillPng(
      [forest],
      ampelClasses: ampelShippedClasses,
      window: window,
      levels: levelsOf([
        [AmpelLevel.guenstig, AmpelLevel.verhalten],
        [AmpelLevel.unguenstig, AmpelLevel.unguenstig],
      ]),
    ));

    final good = at(png, latOf(0), lonOf(0, 0));
    final fair = at(png, latOf(0), lonOf(3, 0));
    final none = at(png, latOf(3), lonOf(0, 3));

    final (mild, strong) = AppColors.ampelCombined.first; // Laub
    expect((good.r, good.g, good.b), rgbOf(strong),
        reason: 'günstig leuchtet im kräftigen Ton SEINER Waldklasse');
    expect(good.a, ampelGuenstigAlpha);
    expect((fair.r, fair.g, fair.b), rgbOf(mild),
        reason: 'verhalten im hellen Ton derselben Spalte …');
    expect(fair.a, ampelVerhaltenAlpha,
        reason: '… und schwächer: Die Stufe steckt in der Deckkraft, '
            'die Waldklasse im Farbton (Betreiber, 2026-08-10)');

    expect(none.r, (AppColors.forestBroadleaf.r * 255).round(),
        reason: 'ungünstig heißt: bleibt Wald');
    expect(none.a, forestCombinedAlpha,
        reason: 'und der Wald tritt zurück, statt zu verschwinden');
  });

  test('eine abgewählte Gruppe leuchtet nicht (Chips im Filter)', () {
    // **Die Auswahl muss bis in den Zeichner durchschlagen**, sonst
    // leuchtet die Fläche weiter für eine Gruppe, die der Chip auf der
    // Karte gar nicht mehr nennt.
    //
    // Das Testgitter steht hier auf 9 °C bei vollem Regen: Im
    // Herbstfenster (13 °C) ist die Glocke exp(-0,64) = 0,53 —
    // „verhalten"; im Pfifferling-Fenster (14,5 °C seit 2026-09-20)
    // exp(-1,21) = 0,30 und damit unter jeder Schwelle (0,348). Bis
    // dahin stand das Gitter auf 13 °C mit Regen 0,3 gegen ein
    // Sommerfenster von 17,5 °C; mit 14,5 liegen beide Glocken bei 13 °C
    // so nah beieinander, dass kein Regenfaktor sie mehr trennt.
    Map<String, Object> pixelAt(List<AmpelClass> classes,
        {AmpelLevel? level = AmpelLevel.guenstig}) {
      final png = decodePng(forestAmpelFillPng(
        [forest],
        ampelClasses: classes,
        window: window,
        levels: levelsOf([
          [level, level],
          [level, level],
        ], meanC: 9),
      ));
      final px = at(png, latOf(0), lonOf(0, 0));
      return {'rgb': (px.r, px.g, px.b), 'a': px.a};
    }

    final beide = pixelAt(ampelShippedClasses);
    final nurSommer = pixelAt(const [ampelSommerClass]);
    final garNicht =
        pixelAt(ampelShippedClasses, level: AmpelLevel.unguenstig);

    expect(beide['a'], ampelVerhaltenAlpha,
        reason: 'mit dem Herbstfenster leuchtet die Wabe');
    expect(nurSommer, garNicht,
        reason: 'ohne das Herbstfenster ist es derselbe Pixel wie bei '
            'ungünstigem Wetter — Wald, kein Leuchten');
    expect(nurSommer, isNot(beide));
  });

  test('bei gleichem Wetter bleibt die Waldklasse unterscheidbar', () {
    // Der Kern der Umstellung (Betreiber, 2026-08-10): Bis 1.79.0 trug
    // JEDE leuchtende Wabe denselben Ton — die Waldklasse war genau
    // dort weg, wo man sie wissen will. Hier steht überall dasselbe
    // Wetter, und trotzdem müssen drei verschiedene Farben herauskommen.
    for (final (level, alpha, strong) in [
      (AmpelLevel.guenstig, ampelGuenstigAlpha, true),
      (AmpelLevel.verhalten, ampelVerhaltenAlpha, false),
    ]) {
      final png = decodePng(forestAmpelFillPng(
        [gemischt],
        ampelClasses: ampelShippedClasses,
        window: window,
        levels: levelsOf([
          [level, level],
          [level, level],
        ]),
      ));

      final farben = [
        for (var hx = 0; hx < 3; hx++)
          () {
            final p = at(png, latOf(0), lonOf(hx, 0));
            return (p.r, p.g, p.b, p.a);
          }()
      ];

      for (var klasse = 0; klasse < 3; klasse++) {
        final pair = AppColors.ampelCombined[klasse];
        final (r, g, b) = rgbOf(strong ? pair.$2 : pair.$1);
        expect(farben[klasse], (r, g, b, alpha),
            reason: 'Spalte $klasse der Tabelle, Stufe ${level.name}');
      }
      expect(farben.map((f) => (f.$1, f.$2, f.$3)).toSet(), hasLength(3),
          reason: 'drei Waldklassen, drei Töne — sonst ist die '
              'Kombi-Ebene wieder nur eine Wetterebene');
    }
  });

  test('ohne Wetteraussage bleibt der Wald stehen — nicht leer', () {
    // Außerhalb Deutschlands liefert das Gitter nichts. „Leuchtet
    // nicht" darf dort nicht „kein Wald" heißen, sonst läse sich die
    // Abdeckungsgrenze als Landschaft.
    final png = decodePng(forestAmpelFillPng(
      [forest],
      ampelClasses: ampelShippedClasses,
      window: window,
      levels: levelsOf([
        [null, null],
        [null, null],
      ]),
    ));
    final cell = at(png, latOf(1), lonOf(1, 1));
    expect(cell.r, (AppColors.forestBroadleaf.r * 255).round());
    expect(cell.a, forestCombinedAlpha);
  });

  test('jede Wabe leuchtet nach IHRER Höhe, nicht nach der Regenzelle',
      () {
    // Der Berchtesgaden-Befund (2026-08-17): EINE 1-km-Regenzelle über
    // steilem Gelände, EINE Stufe je Zelle — die Wabenfarbe konnte der
    // Punkt-Ablesung nie überall zustimmen. Hier: EIN Stufen-Eintrag
    // (13 °C, Regen satt → günstig) über der ganzen Box, Station auf
    // 0 m; das Höhengitter legt die Osthälfte auf 3000 m. Dort schiebt
    // die Lapse-Rechnung das Mittel auf −6,5 °C → die Glocke kippt →
    // kein Leuchten. Westhälfte: unverändert günstig. Dieselbe
    // Auswertung nimmt der Zeichner für grobe wie feine Waben — der
    // Test prüft an den Wabenmittelpunkten die PIXEL, also den ganzen
    // Weg.
    final elevation = ElevationGrid(
      values: Uint8List.fromList([
        for (var y = 0; y < 6; y++)
          for (var x = 0; x < 6; x++) x < 3 ? 0 : 150,
      ]),
      width: 6,
      height: 6,
      west: 10,
      east: 10.018,
      north: 50,
      south: 49.988,
      hexLonStep: 0.003,
      hexLatStep: 0.002,
    );
    final oneCell = levelsOf([
      [AmpelLevel.guenstig],
    ]);

    final corrected = decodePng(forestAmpelFillPng(
      [forest],
      ampelClasses: ampelShippedClasses,
      window: window,
      levels: oneCell,
      elevation: elevation,
    ));
    final plain = decodePng(forestAmpelFillPng(
      [forest],
      ampelClasses: ampelShippedClasses,
      window: window,
      levels: oneCell,
    ));

    final (_, strong) = AppColors.ampelCombined.first; // Laub
    final west = at(corrected, latOf(1), lonOf(0, 1));
    final east = at(corrected, latOf(1), lonOf(3, 1));
    expect((west.r, west.g, west.b), rgbOf(strong),
        reason: 'Tal-Wabe (0 m = Stationshöhe): leuchtet günstig');
    expect(west.a, ampelGuenstigAlpha);
    expect(east.r, (AppColors.forestBroadleaf.r * 255).round(),
        reason: 'Berg-Wabe (3000 m): dieselbe Regenzelle, aber die '
            'Glocke kippt auf Wabenhöhe — bleibt Wald');
    expect(east.a, forestCombinedAlpha);

    // Und die Gegenrichtung im selben Test: OHNE Höhengitter leuchtet
    // auch der Berg — sonst hätte die Höhe gar nicht gerechnet und
    // beide Erwartungen oben wären aus anderem Grund erfüllbar.
    final eastPlain = at(plain, latOf(1), lonOf(3, 1));
    expect((eastPlain.r, eastPlain.g, eastPlain.b), rgbOf(strong),
        reason: 'unkorrigiert leuchtet die Berg-Wabe — der Unterschied '
            'IST die Höhenauswertung je Wabe');

    // Blatt-Abgleich am selben Punkt: Was die Wabe malt, muss der
    // `levelAt`-Weg (und damit die Punkt-Ablesung) genauso sagen.
    expect(
        oneCell.levelAt(latOf(1), lonOf(3, 1),
            classes: ampelShippedClasses, elevation: elevation),
        isNot(AmpelLevel.guenstig),
        reason: 'die Auswertung hinter dem Pixel');
    expect(oneCell.levelAt(latOf(1), lonOf(0, 1),
            classes: ampelShippedClasses, elevation: elevation),
        AmpelLevel.guenstig);
  });

  test('abgewählte Klassen leuchten auch nicht (#231)', () {
    // Die Teil-Ebenen bleiben die Teil-Ebenen: Wer nur Nadelwald
    // einblendet, will auch im Kombi-Modus keinen leuchtenden
    // Laubwald — sonst käme eine abgewählte Klasse durch die
    // Hintertür zurück, nur bunter.
    final png = decodePng(forestAmpelFillPng(
      [forest],
      ampelClasses: ampelShippedClasses,
      window: window,
      levels: levelsOf([
        [AmpelLevel.guenstig, AmpelLevel.guenstig],
        [AmpelLevel.guenstig, AmpelLevel.guenstig],
      ]),
      classes: const {ForestClass.conifer},
    ));
    expect(at(png, latOf(1), lonOf(1, 1)).a, 0,
        reason: 'Laubwald ist abgewählt — also nichts, auch kein Leuchten');
  });

  test('Wald ohne Wetter und Wetter ohne Wald ergeben verschiedene Bilder',
      () {
    // Der Test, der „malt überhaupt jemand etwas anderes?" beantwortet:
    // Dieselben Waben einmal schlicht, einmal kombiniert.
    final plain = forestFillPng(forest, window: window);
    final lit = forestAmpelFillPng(
      [forest],
      ampelClasses: ampelShippedClasses,
      window: window,
      levels: levelsOf([
        [AmpelLevel.guenstig, AmpelLevel.guenstig],
        [AmpelLevel.guenstig, AmpelLevel.guenstig],
      ]),
    );
    expect(lit, isNot(plain));
  });
}
