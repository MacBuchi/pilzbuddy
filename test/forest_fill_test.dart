// Die Waldtypen-Fläche (#213): zurückdekodiert statt längengeprüft —
// dieselbe Begründung wie beim Regen-Fill: „durchsichtig, weil kein Wald"
// und „durchsichtig, weil kaputt" sehen auf der Karte gleich aus.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart'
    show forestFillStamp;
import 'package:pilzbuddy/features/map/forest_fill.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart' show ForestClass;

import 'package:pilzbuddy/features/map/rain_grid.dart' show mercatorY;

import 'forest_grid_test.dart' show forestOf;
import 'rain_fill_test.dart' show decodePng;

int _r(int byte) => byte;

void main() {
  test('Klassen bekommen ihre Farbe, kein Wald bleibt durchsichtig', () {
    // Byte 0 = kein Wald, 11 = 10 % Nadel (Laub), 51 = 50 % (Misch),
    // 96 = 95 % (Nadel), 255 = keine Daten.
    final grid = forestOf([
      [0, 11, 51, 96, 255],
    ]);
    final png = decodePng(forestFillPng(grid));
    expect(png.width, 5);
    expect(png.height, 1);

    ({int r, int g, int b, int a}) pixel(int x) => (
          r: png.pixels[x * 4],
          g: png.pixels[x * 4 + 1],
          b: png.pixels[x * 4 + 2],
          a: png.pixels[x * 4 + 3],
        );

    expect(pixel(0).a, 0, reason: 'kein Wald ist durchsichtig');
    expect(pixel(4).a, 0, reason: 'keine Daten ebenso');

    expect(pixel(1).a, forestFillAlpha);
    expect(_r(pixel(1).r), (AppColors.forestBroadleaf.r * 255).round());
    expect(pixel(2).g, (AppColors.forestMixed.g * 255).round());
    expect(pixel(3).b, (AppColors.forestConifer.b * 255).round());
    // Und die drei sind wirklich verschieden — eine Palette, die alle
    // Klassen gleich einfärbt, wäre formal korrekt und nutzlos.
    expect(pixel(1).r, isNot(pixel(3).r));
    expect(pixel(2).g, isNot(pixel(3).g));
  });

  test('die Zeilen liegen MERCATOR-verteilt — sonst wandert der Wald (#247)',
      () {
    // Der Feldfall vom 2026-08-09, verkleinert: Beide Engines spannen
    // das Bild linear in Mercator auf. Ein grad-linear gemaltes Bild
    // zeigt in der Mitte der DACH-Box Zellen von ~25 km weiter südlich —
    // am Brocken lag das Buchenland des Südharzes.
    //
    // Gitter über der echten Box, eine Nadel-Zeile bei ~51,75°N
    // (Gitterzeile 33 von 94), alles andere Laub.
    const rowsInGrid = 94;
    final grid = forestOf([
      for (var y = 0; y < rowsInGrid; y++)
        [y == 33 ? 96 : 11],
    ], west: 5.8, east: 17.3, north: 55.1, south: 45.7);

    const outRows = 940;
    final png = decodePng(forestFillPng(grid, outHeight: outRows));
    expect(png.height, outRows);

    // Wo ZEIGT die Engine die Breite 51,746° an? Linear in Mercator.
    const lat = 51.746;
    final fMerc = (mercatorY(55.1) - mercatorY(lat)) /
        (mercatorY(55.1) - mercatorY(45.7));
    final shownRow = (fMerc * outRows).floor();
    // Grad-linear läge dieselbe Breite woanders — sonst prüft der Test
    // nichts.
    final degreeRow = ((55.1 - lat) / (55.1 - 45.7) * outRows).floor();
    expect(shownRow, isNot(degreeRow));

    int redAt(int row) => png.pixels[row * png.width * 4];
    final conifer = (AppColors.forestConifer.r * 255).round();
    final broadleaf = (AppColors.forestBroadleaf.r * 255).round();
    expect(redAt(shownRow), conifer,
        reason: 'an 51,75°N muss die Nadel-Zeile ERSCHEINEN — also im '
            'PNG dort liegen, wo Mercator sie hinprojiziert');
    expect(redAt(degreeRow), broadleaf,
        reason: 'die grad-lineare Zeile zeigt auf der Karte ~52,0°N — '
            'dort steht Laub; wer hier Nadel malt, malt grad-linear');
  });

  test('abgewählte Klassen werden durchsichtig wie kein Wald (#231)', () {
    // Byte 11 = Laub, 51 = Misch, 96 = Nadel. Nur Nadel eingeblendet:
    // Die anderen beiden verschwinden — neben der Regenfläche (#232)
    // bleibt so genau die Klasse stehen, die einen interessiert.
    final grid = forestOf([
      [11, 51, 96],
    ]);
    final png = decodePng(
        forestFillPng(grid, classes: const {ForestClass.conifer}));

    int alphaAt(int x) => png.pixels[x * 4 + 3];
    expect(alphaAt(0), 0, reason: 'Laub ist abgewählt');
    expect(alphaAt(1), 0, reason: 'Misch ist abgewählt');
    expect(alphaAt(2), forestFillAlpha, reason: 'Nadel bleibt');
    expect(png.pixels[2 * 4 + 2], (AppColors.forestConifer.b * 255).round());
  });

  test('der Datei-Stand kodiert die Klassenwahl — jede Auswahl eine '
      'eigene URL (#231)', () {
    // Die MapLibre-Strecke ist idempotent auf der URL: Ein PNG mit
    // anderer Klassenwahl unter demselben Stand würde nicht getauscht,
    // die Karte zeigte still die alte Auswahl.
    final all = <DateTime>{};
    for (final classes in [
      const {ForestClass.broadleaf},
      const {ForestClass.mixed},
      const {ForestClass.conifer},
      const {ForestClass.broadleaf, ForestClass.mixed},
      const {ForestClass.broadleaf, ForestClass.conifer},
      const {ForestClass.mixed, ForestClass.conifer},
      allForestClasses,
    ]) {
      all.add(forestFillStamp(2024, classes));
    }
    expect(all, hasLength(7),
        reason: 'zwei Auswahlen teilen sich einen Stand');
    // Und stabil: dieselbe Auswahl ergibt denselben Stand.
    expect(forestFillStamp(2024, const {ForestClass.mixed}),
        forestFillStamp(2024, const {ForestClass.mixed}));
    // Anderes Jahr, anderer Stand — sonst überlebte ein altes Bild ein
    // Gitter-Update.
    expect(forestFillStamp(2025, allForestClasses),
        isNot(forestFillStamp(2024, allForestClasses)));
  });

  test('ein reines Nicht-Wald-Gitter ergibt ein vollständig transparentes '
      'Bild', () {
    final grid = forestOf([
      [0, 0],
      [255, 0],
    ]);
    final png = decodePng(forestFillPng(grid));
    for (var i = 3; i < png.pixels.length; i += 4) {
      expect(png.pixels[i], 0);
    }
  });
}
