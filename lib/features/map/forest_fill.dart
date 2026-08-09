// Die Waldtypen-Fläche (#213): das Gitter direkt eingefärbt, als PNG
// durch dieselbe Bild-Overlay-Strecke wie der Regen (MapLibre über eine
// `image`-Source mit `file://`, flutter_map über `OverlayImage`).
//
// Anders als beim Regen wird NICHT geglättet: Der Regen glättet, damit
// Fläche und (frühere) Linien dieselbe Wahrheit zeigen und Sprenkel
// einzelner Zellen verschwinden — Wald hat keine Linien, und eine
// 250-m-Zelle Laubwald im Fichtenhang ist keine Störung, sondern genau
// die Information, nach der jemand sucht. Die Klötzchen sind die Daten.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;

import '../../core/app_colors.dart';
import 'forest_fill_window.dart';
import 'forest_grid.dart';
import 'overlay_png.dart';
import 'rain_grid.dart' show latFromMercatorY, mercatorY;

/// Deckkraft der Waldfläche, 0–255. Startwert = die 55 % des Regen-Fills
/// (`rainFillAlpha`), am Gerät gegenzuprüfen — der Regen brauchte dafür
/// drei Anläufe, und die Obergrenze ist dieselbe: Die Karte darunter
/// (Wege! Ortsnamen!) muss lesbar bleiben.
const forestFillAlpha = 140;

/// Alle drei Waldklassen — der Standard der Ebene und zugleich die
/// Schreibweise für „nichts abgewählt".
const allForestClasses = {
  ForestClass.broadleaf,
  ForestClass.mixed,
  ForestClass.conifer,
};

/// Färbt das Waldgitter ein und gibt ein PNG zurück.
///
/// „Kein Wald" bleibt durchsichtig — die Ebene sagt, wo Wald steht,
/// nicht, wo keiner steht. „Keine Daten" ist ebenfalls durchsichtig;
/// den Unterschied erklärt das Blatt (Abdeckung: DACH).
///
/// [classes] sind die eingeblendeten Teil-Ebenen (#231): Abgewählte
/// Klassen werden durchsichtig wie „kein Wald". So bleibt neben der
/// Regenfläche (#232) genau die Klasse stehen, die einen interessiert,
/// statt dass die ganze Karte unter zwei Schleiern abstumpft.
///
/// **Die Zeilen des PNGs sind MERCATOR-verteilt, nicht grad-verteilt**
/// (#247, seit 1.68.1): Beide Engines spannen ein Bild linear in
/// Web-Mercator zwischen seine Eckpunkte — ein grad-lineares Bild stimmt
/// dann nur am Nord- und Südrand und liegt in der Mitte der Box um bis zu
/// ~26 km daneben. Genau davor warnt der Kopfkommentar in
/// `forest_grid.dart` („linear in Breite UND Länge, anders als der
/// Regen"); dieser Maler hat es ignoriert, und am Brocken zeigte die
/// Fläche das Buchenland des Südharzes (Feldbericht 2026-08-09, mit
/// Pixelfarben nachgemessen). Der Regen-Fill braucht keine Umrechnung,
/// weil sein Gitter SELBST Mercator-Zeilen hat.
///
/// Je Ausgabepixel wird die Zelle unter seinem Mittelpunkt gewählt
/// (nearest) — die Werte sind Klassen, Mitteln wäre Datenerfindung.
///
/// [window] ist der zu malende AUSSCHNITT samt Pixelmaßen (#249) — der
/// Planer (`forest_fill_window.dart`) hält ihn im Budget. Ohne Angabe
/// wird das ganze Gitter gemalt, ein Pixel je Spalte und Zeile — der Weg
/// der Bestandstests, und mit dem 250-m-Asset noch tragbar (52 MB
/// Puffer); die Karte selbst geht seit #249 immer über ein Fenster.
Uint8List forestFillPng(ForestGrid grid,
    {int alpha = forestFillAlpha,
    Set<ForestClass> classes = allForestClasses,
    FillWindow? window}) {
  window ??= FillWindow(
    west: grid.west,
    east: grid.east,
    north: grid.north,
    south: grid.south,
    width: grid.width,
    height: grid.height,
  );
  final width = window.width;
  final palette = _paletteFor(alpha, classes);

  final rows = window.height;
  final mercNorth = mercatorY(window.north);
  final mercSpan = mercatorY(window.south) - mercNorth;

  if (grid.isHex) {
    final raw = _emptyRaster(window);
    _paintHexes(raw, grid, window, palette,
        mercNorth: mercNorth, mercSpan: mercSpan);
    return overlayPng(window.width, rows, raw);
  }

  // Spalte -> Gitterspalte, einmal statt je Zeile: Die Länge ist in
  // beiden Abbildungen linear, nur der Ausschnitt verschiebt sie.
  final columnMap = Int32List(width);
  for (var x = 0; x < width; x++) {
    final lon =
        window.west + (x + 0.5) / width * (window.east - window.west);
    final gridX = ((lon - grid.west) / (grid.east - grid.west) * grid.width)
        .floor()
        .clamp(0, grid.width - 1);
    columnMap[x] = gridX;
  }

  final raw = Uint8List(rows * (width * 4 + 1));
  var cursor = 0;
  for (var y = 0; y < rows; y++) {
    raw[cursor++] = 0; // Filter „None"
    // Zeilenmitte in Mercator -> Breite -> Gitterzeile (nearest).
    final lat = latFromMercatorY(mercNorth + (y + 0.5) / rows * mercSpan);
    final gridY = ((grid.north - lat) /
            (grid.north - grid.south) *
            grid.height)
        .floor()
        .clamp(0, grid.height - 1);
    final row = gridY * grid.width;
    for (var x = 0; x < width; x++) {
      final offset = grid.values[row + columnMap[x]] * 4;
      raw[cursor++] = palette[offset];
      raw[cursor++] = palette[offset + 1];
      raw[cursor++] = palette[offset + 2];
      raw[cursor++] = palette[offset + 3];
    }
  }

  return overlayPng(width, rows, raw);
}

/// Nachschlagetabelle wie beim Regen: Millionen Zellen, 256 Einträge.
/// Abgewählte Klassen und „kein Wald" bleiben durchsichtig (Alpha 0).
Uint8List _paletteFor(int alpha, Set<ForestClass> classes) {
  final palette = Uint8List(256 * 4);
  for (var value = 0; value < 256; value++) {
    final forestClass = classOfByte(value);
    if (forestClass == ForestClass.none || !classes.contains(forestClass)) {
      continue; // durchsichtig
    }
    final Color colour;
    switch (forestClass) {
      case ForestClass.none:
        continue; // oben schon behandelt — der Vollständigkeit halber
      case ForestClass.broadleaf:
        colour = AppColors.forestBroadleaf;
      case ForestClass.mixed:
        colour = AppColors.forestMixed;
      case ForestClass.conifer:
        colour = AppColors.forestConifer;
    }
    final offset = value * 4;
    palette[offset] = (colour.r * 255).round();
    palette[offset + 1] = (colour.g * 255).round();
    palette[offset + 2] = (colour.b * 255).round();
    palette[offset + 3] = alpha;
  }
  return palette;
}

/// Die feine Stufe (#253): mehrere Blockgitter in EIN Fensterbild. Die
/// Blöcke kacheln das globale Gitter ohne Überlappung, jeder malt seine
/// Waben mit seinem eigenen Anker — die Naht zwischen zwei Blöcken ist
/// damit dieselbe Wabenkante wie mitten im Block, und
/// `test/forest_fill_test.dart` hält fest, dass das Ergebnis pixelgleich
/// zum Ganzgitter ist.
Uint8List forestFillPngMulti(List<ForestGrid> grids,
    {int alpha = forestFillAlpha,
    Set<ForestClass> classes = allForestClasses,
    required FillWindow window}) {
  final palette = _paletteFor(alpha, classes);
  final mercNorth = mercatorY(window.north);
  final mercSpan = mercatorY(window.south) - mercNorth;
  final raw = _emptyRaster(window);
  for (final grid in grids) {
    _paintHexes(raw, grid, window, palette,
        mercNorth: mercNorth, mercSpan: mercSpan);
  }
  return overlayPng(window.width, window.height, raw);
}

/// Der leere RGBA-Rasterpuffer im PNG-Zeilenformat (1 Filterbyte je
/// Zeile, dann `width` Pixel).
Uint8List _emptyRaster(FillWindow window) =>
    Uint8List(window.height * (window.width * 4 + 1));

/// Der Sechseck-Zeichner (#251): je Hex ein konvexes Polygon per
/// Scanline, Spitze oben. Die sechs Eckpunkte werden EINZELN durch die
/// Mercator-Abbildung geschickt (innerhalb eines ~250-m-Hexes ist die
/// Krümmung belanglos, aber die LAGE muss stimmen — die Lehre aus #247).
///
/// Geteilte Kantenpixel malt der jeweils spätere Nachbar — bei
/// Datengrenzen gewinnt also eine Seite; das ist eine halbe Pixelbreite
/// und keine Aussage. Der Prototyp dieses Zeichners ist gemessen: ~8 ms
/// Rasterarbeit gegen ~150 ms PNG-Kompression, das Performance-Tor des
/// Betreibers ist bestanden.
///
/// Malt in [raw] hinein statt ein PNG zu liefern, damit die feine Stufe
/// (#253) mehrere Blockgitter in dasselbe Bild setzen kann.
void _paintHexes(
    Uint8List raw, ForestGrid grid, FillWindow window, Uint8List palette,
    {required double mercNorth, required double mercSpan}) {
  final width = window.width;
  final rows = window.height;
  final lonStep = grid.hexLonStep!;
  final latStep = grid.hexLatStep!;
  final rDeg = latStep / 1.5; // Umkreisradius in Grad Breite

  final lonSpan = window.east - window.west;
  double xOf(double lon) => (lon - window.west) / lonSpan * width;
  double yOf(double lat) =>
      (mercatorY(lat) - mercNorth) / mercSpan * rows;

  // Hex-Zeilen/-Spalten, die das Fenster berühren (plus Rand).
  final hy0 = (((grid.north - window.north) / latStep) - 2).floor();
  final hy1 = (((grid.north - window.south) / latStep) + 2).ceil();
  final hx0 = (((window.west - grid.west) / lonStep) - 2).floor();
  final hx1 = (((window.east - grid.west) / lonStep) + 2).ceil();
  final wPx = lonStep / lonSpan * width;

  for (var hy = hy0; hy <= hy1; hy++) {
    if (hy < 0 || hy >= grid.height) continue;
    final odd = hy.isOdd ? 0.5 : 0.0;
    final latC = grid.north - latStep * (hy + 2 / 3);
    // Die vier Höhenlinien des Sechsecks, einzeln projiziert.
    final yTop = yOf(latC + rDeg);
    final yUp = yOf(latC + rDeg / 2);
    final yLow = yOf(latC - rDeg / 2);
    final yBot = yOf(latC - rDeg);
    if (yBot < 0 || yTop >= rows) continue;
    final rowBase = hy * grid.width;
    for (var hx = hx0; hx <= hx1; hx++) {
      if (hx < 0 || hx >= grid.width) continue;
      final offset = grid.values[rowBase + hx] * 4;
      if (palette[offset + 3] == 0) continue; // durchsichtig
      final cx = xOf(grid.west + lonStep * (hx + 0.5 + odd));
      if (cx + wPx / 2 < 0 || cx - wPx / 2 >= width) continue;
      final py0 = math.max(0, yTop.ceil());
      final py1 = math.min(rows - 1, yBot.floor());
      for (var py = py0; py <= py1; py++) {
        final yc = py + 0.5;
        double half;
        if (yc <= yUp) {
          final t = (yc - yTop) / (yUp - yTop);
          half = wPx / 2 * t;
        } else if (yc >= yLow) {
          final t = (yBot - yc) / (yBot - yLow);
          half = wPx / 2 * t;
        } else {
          half = wPx / 2;
        }
        if (half <= 0) continue;
        final x0 = math.max(0, (cx - half).round());
        final x1 = math.min(width - 1, (cx + half).round() - 1);
        var cursor = py * (width * 4 + 1) + 1 + x0 * 4;
        for (var px = x0; px <= x1; px++) {
          raw[cursor++] = palette[offset];
          raw[cursor++] = palette[offset + 1];
          raw[cursor++] = palette[offset + 2];
          raw[cursor++] = palette[offset + 3];
        }
      }
    }
  }
}
