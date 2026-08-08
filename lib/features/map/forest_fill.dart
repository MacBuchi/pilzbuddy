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
import 'forest_grid.dart';
import 'overlay_png.dart';

/// Deckkraft der Waldfläche, 0–255. Startwert = die 55 % des Regen-Fills
/// (`rainFillAlpha`), am Gerät gegenzuprüfen — der Regen brauchte dafür
/// drei Anläufe, und die Obergrenze ist dieselbe: Die Karte darunter
/// (Wege! Ortsnamen!) muss lesbar bleiben.
const forestFillAlpha = 140;

/// Färbt das Waldgitter ein und gibt ein PNG zurück.
///
/// „Kein Wald" bleibt durchsichtig — die Ebene sagt, wo Wald steht,
/// nicht, wo keiner steht. „Keine Daten" ist ebenfalls durchsichtig;
/// den Unterschied erklärt das Blatt (Abdeckung: DACH).
Uint8List forestFillPng(ForestGrid grid, {int alpha = forestFillAlpha}) {
  final width = grid.width;
  final height = grid.height;
  // Nachschlagetabelle wie beim Regen: Millionen Zellen, 256 Einträge.
  final palette = Uint8List(256 * 4);
  for (var value = 0; value < 256; value++) {
    final Color colour;
    switch (classOfByte(value)) {
      case ForestClass.none:
        continue; // durchsichtig
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

  final raw = Uint8List(height * (width * 4 + 1));
  var cursor = 0;
  for (var y = 0; y < height; y++) {
    raw[cursor++] = 0; // Filter „None"
    final row = y * width;
    for (var x = 0; x < width; x++) {
      final offset = grid.values[row + x] * 4;
      raw[cursor++] = palette[offset];
      raw[cursor++] = palette[offset + 1];
      raw[cursor++] = palette[offset + 2];
      raw[cursor++] = palette[offset + 3];
    }
  }

  return overlayPng(width, height, raw);
}
