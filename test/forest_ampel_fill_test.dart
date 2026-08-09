// Die Kombi-Ebene „Wald + Pilzwetter" (Betreiber-Wunsch 2026-08-09):
// dieselben Waben, aber die mit gutem Wetter leuchten.
//
// Geprüft wird an den PIXELN unter den Wabenmittelpunkten — dort ist
// jede Zellform eindeutig, und dort steht die Aussage, um die es geht:
// leuchtet diese Wabe, und wie stark.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/ampel/ampel_fill.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/map/forest_fill.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart' show mercatorY;

import 'forest_grid_test.dart' show hexOf;
import 'rain_fill_test.dart' show decodePng;

/// Ein Stufen-Gitter über der Testbox: [levels] zeilenweise, Werte aus
/// [AmpelLevel] oder `null` für „keine Aussage".
AmpelLevelGrid levelsOf(List<List<AmpelLevel?>> rows,
        {double west = 10,
        double east = 10.018,
        double north = 50,
        double south = 49.988}) =>
    AmpelLevelGrid(
      levels: Uint8List.fromList([
        for (final row in rows)
          for (final level in row) level == null ? 0 : level.index + 1,
      ]),
      width: rows.first.length,
      height: rows.length,
      west: west,
      east: east,
      north: north,
      south: south,
      newest: DateTime.utc(2026, 8, 9),
    );

void main() {
  // 4×4 Waben, überall Laubwald — so ist jeder Farbunterschied im Bild
  // das Wetter und nicht die Waldklasse.
  final forest = hexOf([
    for (var hy = 0; hy < 4; hy++) List<int>.filled(4, 11),
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

  // Wabenmittelpunkte des Testgitters (odd-r, Spitze oben).
  double latOf(int hy) => 50 - 0.003 * (hy + 2 / 3);
  double lonOf(int hx, int hy) =>
      10 + 0.004 * (hx + 0.5 + (hy.isOdd ? 0.5 : 0.0));

  test('nur die Waben mit gutem Wetter leuchten — der Rest bleibt Wald', () {
    // Stufen-Gitter 2×2 über der Box: oben links günstig, oben rechts
    // verhalten, unten beides ungünstig.
    final png = decodePng(forestAmpelFillPng(
      [forest],
      window: window,
      levels: levelsOf([
        [AmpelLevel.guenstig, AmpelLevel.verhalten],
        [AmpelLevel.unguenstig, AmpelLevel.unguenstig],
      ]),
      palette: AmpelPalette.violett,
    ));

    final good = at(png, latOf(0), lonOf(0, 0));
    final fair = at(png, latOf(0), lonOf(3, 0));
    final none = at(png, latOf(3), lonOf(0, 3));

    expect(good.r, (AmpelPalette.violett.highlight.r * 255).round(),
        reason: 'günstig leuchtet im Highlight-Ton');
    expect(good.a, ampelHighlightGuenstigAlpha);
    expect(fair.r, (AmpelPalette.violett.highlight.r * 255).round(),
        reason: 'verhalten leuchtet in derselben Farbe …');
    expect(fair.a, ampelHighlightVerhaltenAlpha,
        reason: '… nur schwächer — eine Farbe, zwei Stärken');

    expect(none.r, (AppColors.forestBroadleaf.r * 255).round(),
        reason: 'ungünstig heißt: bleibt Wald');
    expect(none.a, forestCombinedAlpha,
        reason: 'und der Wald tritt zurück, statt zu verschwinden');
  });

  test('ohne Wetteraussage bleibt der Wald stehen — nicht leer', () {
    // Außerhalb Deutschlands liefert das Gitter nichts. „Leuchtet
    // nicht" darf dort nicht „kein Wald" heißen, sonst läse sich die
    // Abdeckungsgrenze als Landschaft.
    final png = decodePng(forestAmpelFillPng(
      [forest],
      window: window,
      levels: levelsOf([
        [null, null],
        [null, null],
      ]),
      palette: AmpelPalette.violett,
    ));
    final cell = at(png, latOf(1), lonOf(1, 1));
    expect(cell.r, (AppColors.forestBroadleaf.r * 255).round());
    expect(cell.a, forestCombinedAlpha);
  });

  test('die Farbfamilie schlägt bis ins Leuchten durch', () {
    for (final palette in AmpelPalette.values) {
      final png = decodePng(forestAmpelFillPng(
        [forest],
        window: window,
        levels: levelsOf([
          [AmpelLevel.guenstig, AmpelLevel.guenstig],
          [AmpelLevel.guenstig, AmpelLevel.guenstig],
        ]),
        palette: palette,
      ));
      expect(at(png, latOf(1), lonOf(1, 1)).b,
          (palette.highlight.b * 255).round(),
          reason: palette.label);
    }
  });

  test('abgewählte Klassen leuchten auch nicht (#231)', () {
    // Die Teil-Ebenen bleiben die Teil-Ebenen: Wer nur Nadelwald
    // einblendet, will auch im Kombi-Modus keinen leuchtenden
    // Laubwald — sonst käme eine abgewählte Klasse durch die
    // Hintertür zurück, nur bunter.
    final png = decodePng(forestAmpelFillPng(
      [forest],
      window: window,
      levels: levelsOf([
        [AmpelLevel.guenstig, AmpelLevel.guenstig],
        [AmpelLevel.guenstig, AmpelLevel.guenstig],
      ]),
      palette: AmpelPalette.violett,
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
      window: window,
      levels: levelsOf([
        [AmpelLevel.guenstig, AmpelLevel.guenstig],
        [AmpelLevel.guenstig, AmpelLevel.guenstig],
      ]),
      palette: AmpelPalette.violett,
    );
    expect(lit, isNot(plain));
  });
}
