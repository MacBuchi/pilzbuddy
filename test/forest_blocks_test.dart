// Die nachladbare feine Waldstufe (#253): Katalog-Parsing, der
// Blockverbund und die kombinierte Sicht.
//
// Der Maßstab fast aller Tests hier ist das GANZGITTER: Die Blöcke sind
// per Bauregel nur Ausschnitte desselben Hex-Gitters, also muss der
// Verbund für jeden Punkt exakt dieselbe Wabe treffen und denselben
// Umkreis zählen wie das Gitter am Stück — besonders an den Nähten, wo
// eine eigene Block-Zuordnung (Bbox statt globalem Index) danebengriffe.
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_blocks.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';

import 'forest_grid_test.dart' show encodeForest, hexOf;

/// Schneidet [rows] wie `cut_blocks` im Werkzeug: an geraden Hexzeilen
/// ([stepY] gerade!) und ganzen Spalten, mit denselben Bbox-Formeln —
/// inklusive der halben Spalte/ganzen Zeile Hex-Überstand. Liefert den
/// Katalog (über `tryParse`, damit die Index-Herleitung mitgeprüft
/// wird), die dekodierten Blockgitter und das Ganzgitter als Maßstab.
({
  ForestBlockCatalog catalog,
  Map<String, ForestGrid> grids,
  ForestGrid whole,
}) cutHexGrid(List<List<int>> rows,
    {int stepX = 3, int stepY = 2, int referenceYear = 2024}) {
  assert(stepY.isEven, 'Bauregel aus cut_blocks: Schnitt an geraden Zeilen');
  const west = 10.0;
  const north = 50.0;
  const lonStep = 0.004;
  const latStep = 0.003;
  final height = rows.length;
  final width = rows.first.length;

  final entries = <Map<String, dynamic>>[];
  final grids = <String, ForestGrid>{};
  var by = 0;
  for (var hy0 = 0; hy0 < height; hy0 += stepY, by++) {
    final h = hy0 + stepY > height ? height - hy0 : stepY;
    var bx = 0;
    for (var hx0 = 0; hx0 < width; hx0 += stepX, bx++) {
      final w = hx0 + stepX > width ? width - hx0 : stepX;
      final blockRows = [
        for (var j = 0; j < h; j++) rows[hy0 + j].sublist(hx0, hx0 + w),
      ];
      final payload = encodeForest(blockRows);
      final name = 'forest_block_x${bx}_y$by.bin.gz';
      final blockWest = west + hx0 * lonStep;
      final blockNorth = north - hy0 * latStep;
      final blockEast = west + (hx0 + w + 0.5) * lonStep;
      final blockSouth = north - (hy0 + h + 1) * latStep;
      entries.add({
        'file': name,
        'width': w,
        'height': h,
        'west': blockWest,
        'north': blockNorth,
        'east': blockEast,
        'south': blockSouth,
        'bytes': payload.length,
        'sha256': sha256.convert(payload).toString(),
      });
      grids[name] = ForestGrid.decode(
        payload,
        width: w,
        height: h,
        west: blockWest,
        east: blockEast,
        north: blockNorth,
        south: blockSouth,
        referenceYear: referenceYear,
        hexLonStep: lonStep,
        hexLatStep: latStep,
      );
    }
  }
  final catalog = ForestBlockCatalog.tryParse({
    'reference_year': referenceYear,
    'lattice': 'hex-odd-r',
    'hex_lon_step': lonStep,
    'hex_lat_step': latStep,
    'blocks': entries,
  });
  return (catalog: catalog!, grids: grids, whole: hexOf(rows));
}

void main() {
  // 6×6 Waben, jede mit eigenem Wert (1–36): Wer die falsche Wabe
  // trifft, liefert garantiert die falsche Zahl.
  final rows = [
    for (var hy = 0; hy < 6; hy++)
      [for (var hx = 0; hx < 6; hx++) hy * 6 + hx + 1],
  ];
  final cut = cutHexGrid(rows);
  final all = ForestBlockSet(catalog: cut.catalog, loaded: cut.grids);

  group('ForestBlockCatalog', () {
    test('Indexversatz kommt aus der Bbox, Maße aus den Blöcken', () {
      expect(cut.catalog.gridWidth, 6);
      expect(cut.catalog.gridHeight, 6);
      expect(cut.catalog.west, 10.0);
      expect(cut.catalog.north, 50.0);
      final byFile = {for (final b in cut.catalog.blocks) b.file: b};
      expect(byFile['forest_block_x1_y2.bin.gz']!.hx0, 3);
      expect(byFile['forest_block_x1_y2.bin.gz']!.hy0, 4);
      expect(byFile['forest_block_x0_y0.bin.gz']!.hx0, 0);
    });

    test('unbekanntes Gitterformat wird abgelehnt', () {
      expect(
          ForestBlockCatalog.tryParse({
            'reference_year': 2024,
            'lattice': 'hex-even-r',
            'hex_lon_step': 0.004,
            'hex_lat_step': 0.003,
            'blocks': const [],
          }),
          isNull);
    });

    test('ein Schnitt an UNGERADER Zeile kippt die Parität — abgelehnt',
        () {
      // Handgebauter Katalog: ein Block, der bei hy0 = 1 beginnt. Seine
      // lokale Zeile 0 wäre global ungerade — jede zweite Wabe läge um
      // eine halbe Breite versetzt, still.
      expect(
          ForestBlockCatalog.tryParse({
            'reference_year': 2024,
            'lattice': 'hex-odd-r',
            'hex_lon_step': 0.004,
            'hex_lat_step': 0.003,
            'blocks': [
              {
                'file': 'forest_block_x0_y0.bin.gz',
                'width': 2,
                'height': 2,
                'west': 10.0,
                'north': 50.0 - 0.003, // eine Zeile tiefer als der Anker
                'east': 10.0 + 0.004 * 2.5,
                'south': 50.0 - 0.003 * 4,
                'bytes': 1,
                'sha256': '00',
              },
              {
                'file': 'forest_block_x0_y1.bin.gz',
                'width': 2,
                'height': 2,
                'west': 10.0,
                'north': 50.0,
                'east': 10.0 + 0.004 * 2.5,
                'south': 50.0 - 0.003 * 3,
                'bytes': 1,
                'sha256': '00',
              },
            ],
          }),
          isNull);
    });
  });

  group('ForestBlockSet', () {
    test('trifft für JEDEN Punkt dieselbe Wabe wie das Ganzgitter — auch '
        'über die Nähte', () {
      // Punktraster über die ganze Box, deutlich feiner als die Waben:
      // Es überstreicht damit auch die Überstands-Zonen der Block-Bboxen
      // (halbe Spalte Ost, ganze Zeile Süd), wo eine Zuordnung über die
      // Block-Bbox statt über den globalen Index die NACHBAR-Wabe des
      // falschen Blocks nähme.
      var probed = 0;
      for (var lat = 50.001; lat > 50 - 0.003 * 7.5; lat -= 0.0007) {
        for (var lon = 9.999; lon < 10 + 0.004 * 7; lon += 0.0009) {
          final cell = cut.whole.hexCellAt(lat, lon);
          final expected =
              cell == null ? null : cut.whole.byteAt(cell.$1, cell.$2);
          expect(all.byteAtPoint(lat, lon), expected,
              reason: 'Punkt ($lat, $lon)');
          probed++;
        }
      }
      expect(probed, greaterThan(500), reason: 'sonst prüft der Test wenig');
    });

    test('fehlt der Block unterm Punkt, sagt der Verbund nichts', () {
      final partial = ForestBlockSet(
        catalog: cut.catalog,
        loaded: {...cut.grids}..remove('forest_block_x1_y0.bin.gz'),
      );
      // Mittelpunkt von (4,0) — liegt im entfernten Block x1_y0.
      expect(partial.byteAtPoint(50 - 0.003 * (2 / 3), 10 + 0.004 * 4.5),
          isNull);
      // Mittelpunkt von (1,0) — liegt im geladenen Block x0_y0.
      expect(partial.byteAtPoint(50 - 0.003 * (2 / 3), 10 + 0.004 * 1.5),
          rows[0][1]);
    });

    test('der Umkreis an der Naht zählt beide Blöcke — wie das Ganzgitter',
        () {
      // Punkt auf der Naht zwischen x0 und x1 (Spalten 2|3), Radius so,
      // dass der Kreis im Gitter bleibt, aber mehrere Spalten beider
      // Seiten fasst. Wer hier nur den eigenen Block zählte, bekäme
      // einen anderen Faktor.
      final lat = 50 - 0.003 * 2.6;
      final lon = 10 + 0.004 * 3.0;
      final expected = cut.whole.broadleafFactorAround(lat, lon,
          radiusMeters: 400);
      final got = all.factorAround(lat, lon, radiusMeters: 400);
      expect(expected, isNotNull);
      expect(got, isNotNull);
      expect(got!.factor, closeTo(expected!.factor!, 1e-12));
      expect(got.forestShare, expected.forestShare);
    });

    test('fehlt auch nur ein Block des Umkreises, gibt es KEINE Zahl', () {
      // Ein halber Umkreis wäre keine kleinere Antwort, sondern eine
      // andere — der Rückfall aufs Asset übernimmt dann ganz.
      final partial = ForestBlockSet(
        catalog: cut.catalog,
        loaded: {...cut.grids}..remove('forest_block_x1_y1.bin.gz'),
      );
      final lat = 50 - 0.003 * 2.6;
      final lon = 10 + 0.004 * 3.0;
      expect(partial.factorAround(lat, lon, radiusMeters: 400), isNull);
      // Weit weg von der Lücke bleibt die Zahl die des Ganzgitters.
      final farLat = 50 - 0.003 * 0.7;
      final farLon = 10 + 0.004 * 1.5;
      expect(
          partial.factorAround(farLat, farLon, radiusMeters: 150)!.factor,
          all.factorAround(farLat, farLon, radiusMeters: 150)!.factor);
    });

    test('covers: nur wenn alle geschnittenen Blöcke geladen sind', () {
      const window = FillWindow(
          west: 10.002,
          east: 10.02,
          north: 49.998,
          south: 49.9945,
          width: 8,
          height: 4);
      expect(all.covers(window), isTrue);
      final partial = ForestBlockSet(
        catalog: cut.catalog,
        loaded: {...cut.grids}..remove('forest_block_x1_y0.bin.gz'),
      );
      expect(partial.covers(window), isFalse,
          reason: 'das Fenster reicht bis Spalte 5 — die liegt in x1_y0');
      // Ein Fenster über den Gitterrand hinaus (mehr als die Toleranz)
      // deckt der Verbund nie — dort müsste das Asset malen.
      const outside = FillWindow(
          west: 10.002,
          east: 10.1,
          north: 49.998,
          south: 49.9945,
          width: 8,
          height: 4);
      expect(all.covers(outside), isFalse);
    });
  });

  group('ForestView', () {
    // Basis sagt überall Nadel (96), die feine Stufe an (1,0) „kein
    // Wald" (0) und an (0,0) Laub (11). Referenzjahr der feinen Stufe
    // bewusst ANDERS, damit `referenceYearAt` die Quelle verrät.
    final base = hexOf([
      for (var hy = 0; hy < 6; hy++) List<int>.filled(6, 96),
    ]);
    final fineCut = cutHexGrid([
      [11, 0, 96, 96, 96, 96],
      for (var hy = 1; hy < 6; hy++) List<int>.filled(6, 96),
    ], referenceYear: 2025);
    final view = ForestView(
      base: base,
      fine: ForestBlockSet(catalog: fineCut.catalog, loaded: fineCut.grids),
    );
    final latRow0 = 50 - 0.003 * (2 / 3);

    test('ein feines „kein Wald" wird NICHT vom Asset überstimmt', () {
      // Die Ehrlichkeits-Regel des Rückfalls: null heißt beim Verbund
      // „weiß nicht", 0 heißt „weiß es — kein Wald". Wer beides in
      // einen Topf wirft, lässt das grobe Gitter Wald behaupten, den
      // die feine Karte gerade weggenommen hat.
      expect(view.classAt(latRow0, 10 + 0.004 * 1.5), ForestClass.none);
      expect(view.shareAt(latRow0, 10 + 0.004 * 1.5), isNull);
      expect(view.classAt(latRow0, 10 + 0.004 * 0.5), ForestClass.broadleaf);
      expect(view.usesFineAt(latRow0, 10 + 0.004 * 1.5), isTrue);
      expect(view.referenceYearAt(latRow0, 10 + 0.004 * 1.5), 2025);
    });

    test('ohne feine Antwort gilt das Asset', () {
      final partialView = ForestView(
        base: base,
        fine: ForestBlockSet(
          catalog: fineCut.catalog,
          loaded: {...fineCut.grids}..remove('forest_block_x0_y0.bin.gz'),
        ),
      );
      expect(partialView.classAt(latRow0, 10 + 0.004 * 1.5),
          ForestClass.conifer,
          reason: 'Block fehlt → Asset antwortet');
      expect(partialView.usesFineAt(latRow0, 10 + 0.004 * 1.5), isFalse);
      expect(partialView.referenceYearAt(latRow0, 10 + 0.004 * 1.5), 2024);
      // Und der Umkreis: Lücke im Kreis → komplette Asset-Zahl statt
      // eines halben feinen Kreises.
      final around = partialView.broadleafFactorAround(
          latRow0, 10 + 0.004 * 1.5,
          radiusMeters: 300);
      expect(around!.factor, closeTo(0.05, 1e-9),
          reason: 'Byte 96 überall im Asset: Laubfaktor 1 − 95/100');
    });

    test('ganz ohne feine Stufe ist die Sicht das Asset', () {
      final bare = ForestView(base: base);
      expect(bare.classAt(latRow0, 10 + 0.004 * 1.5), ForestClass.conifer);
      expect(bare.usesFineAt(latRow0, 10 + 0.004 * 1.5), isFalse);
    });
  });
}
