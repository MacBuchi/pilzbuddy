// Der Maler des Bereichs-Entwurfs — ohne Flutter, weil er im Browser in
// einem Web Worker läuft (#689, B2). Warum ein Bild und welche Regel es
// zeigt, steht in `area_edit_fill.dart`.

import 'dart:typed_data';

import '../map/forest_fill_window.dart';
import '../map/overlay_png.dart';
import '../map/rain_grid.dart' show mercatorY;
import 'area_tile_key.dart';

/// Die Abdunkelung dessen, was nicht auf dem Gerät liegt (Alpha 0–255).
const kAreaMaskAlpha = 105;

/// Die Tinte der Schraffur: hell auf Dunklem („kommt dazu") …
const kAreaInkLight = (r: 255, g: 255, b: 255, a: 225);

/// … dunkel auf Hellem („fällt weg"), der Textton des hellen Modus.
const kAreaInkDark = (r: 0x13, g: 0x1A, b: 0x16, a: 215);

/// Abstand und Breite der Schraffur in Bildpunkten.
const kAreaHatchSpacing = 8;
const kAreaHatchWidth = 2;

// Zustand je Bildpunkt.
const _none = 0, _stored = 1, _add = 2, _remove = 3;

/// Malt Maske und Entwurf in [window] (Zeilen Mercator-verteilt wie bei
/// Wald und Fundorten) — alle Mengen als Kacheln bei [zoom].
Uint8List areaEditFillPng({
  required FillWindow window,
  required Set<int> stored,
  required Set<int> adds,
  required Set<int> removes,
  int zoom = kAreaShapeZoom,
}) {
  final width = window.width;
  final rows = window.height;
  final n = 1 << zoom;

  // Je Spalte und Zeile die Kachel unter der Pixelmitte.
  final tx = Int32List(width);
  for (var c = 0; c < width; c++) {
    final lon = window.west + (c + 0.5) / width * (window.east - window.west);
    tx[c] = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  }
  final mercNorth = mercatorY(window.north);
  final mercSpan = mercatorY(window.south) - mercNorth;
  // Kachel-y aus Mercator-Metern: y = (R·π − m) / (2·R·π) · n.
  const halfWorld = 20037508.342789244;
  final ty = Int32List(rows);
  for (var r = 0; r < rows; r++) {
    final m = mercNorth + (r + 0.5) / rows * mercSpan;
    ty[r] = ((halfWorld - m) / (2 * halfWorld) * n).floor().clamp(0, n - 1);
  }

  Uint8List stateRow(int r) {
    final out = Uint8List(width);
    final y = ty[r];
    var lastX = -1, last = _none;
    for (var c = 0; c < width; c++) {
      final x = tx[c];
      if (x != lastX) {
        final key = areaTileKey(x, y, zoom);
        if (stored.contains(key)) {
          last = removes.contains(key) ? _remove : _stored;
        } else {
          last = adds.contains(key) ? _add : _none;
        }
        lastX = x;
      }
      out[c] = last;
    }
    return out;
  }

  final stride = width * 4 + 1;
  final raw = Uint8List(rows * stride);
  Uint8List? above;
  var cur = stateRow(0);
  for (var r = 0; r < rows; r++) {
    final below = r + 1 < rows ? stateRow(r + 1) : null;
    var o = r * stride + 1; // Filter-Byte 0
    for (var c = 0; c < width; c++, o += 4) {
      final s = cur[c];
      if (s == _stored) continue; // hell = durchsichtig
      final change = s == _add || s == _remove;
      final edge = change &&
          ((c > 0 && cur[c - 1] != s) ||
              (c + 1 < width && cur[c + 1] != s) ||
              (above != null && above[c] != s) ||
              (below != null && below[c] != s));
      final hatch = s == _add
          ? (c + r) % kAreaHatchSpacing < kAreaHatchWidth
          : s == _remove &&
              (c - r) % kAreaHatchSpacing < kAreaHatchWidth;
      if (edge || hatch) {
        final ink = s == _add ? kAreaInkLight : kAreaInkDark;
        raw[o] = ink.r;
        raw[o + 1] = ink.g;
        raw[o + 2] = ink.b;
        raw[o + 3] = ink.a;
      } else if (s != _remove) {
        raw[o + 3] = kAreaMaskAlpha; // schwarz, halb durchsichtig
      }
    }
    above = cur;
    if (below != null) cur = below;
  }
  return overlayPng(width, rows, raw);
}
