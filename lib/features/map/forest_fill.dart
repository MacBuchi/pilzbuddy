// Die Waldtypen-Fläche (#213): das Gitter direkt eingefärbt, als PNG
// durch dieselbe Bild-Overlay-Strecke wie der Regen (MapLibre über eine
// `image`-Source mit `file://`, flutter_map über `OverlayImage`).
//
// Anders als beim Regen wird NICHT geglättet: Der Regen glättet, damit
// Fläche und (frühere) Linien dieselbe Wahrheit zeigen und Sprenkel
// einzelner Zellen verschwinden — Wald hat keine Linien, und eine
// 250-m-Zelle Laubwald im Fichtenhang ist keine Störung, sondern genau
// die Information, nach der jemand sucht. Die Klötzchen sind die Daten.
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
  // Nachschlagetabelle wie beim Regen: Millionen Zellen, 256 Einträge.
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

  final rows = window.height;
  final mercNorth = mercatorY(window.north);
  final mercSpan = mercatorY(window.south) - mercNorth;

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
