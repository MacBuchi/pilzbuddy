// Die halbtransparente Fläche zwischen den Höhenlinien.
//
// Kein Polygon: Das Gitter wird direkt eingefärbt und als PNG durch die
// Bild-Overlay-Strecke geschickt, die seit 1.45.0 ohnehin läuft (MapLibre
// über eine `image`-Source mit `file://`, flutter_map über `OverlayImage`).
// Damit kostet die Fläche den Renderer nichts, was Polygone gekostet
// hätten — 40–70 Tsd. Füllsegmente waren der Grund, sie zu verwerfen.
//
// **Die Fläche ist die Orientierung, die Linien sind die Aussage.** Bei
// Deckkraft 0,4 hat eine Vollfläche am Pixel 7 die Karte darunter
// gelöscht (2026-08-04, gemessen: keine Ortsbeschriftung mehr lesbar).
// Deshalb liegt [rainFillAlpha] deutlich darunter, und deshalb darf es
// nie so weit hochgedreht werden, dass man die Linien nicht mehr braucht.
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/app_colors.dart';
import 'rain_grid.dart';

/// Deckkraft der Fläche, 0–255.
///
/// 82 ≈ 32 %. Vom Betreiber am gerenderten Ausschnitt gewählt (2026-08-04,
/// „könnte sogar minimal weniger Transparenz sein" gegenüber 27 %).
/// Die Wahl fiel über leerem Grund — über einer Karte mit Wegen und
/// Ortsnamen ist sie noch nicht bestätigt.
const rainFillAlpha = 82;

/// Färbt das Gitter ein und gibt ein PNG zurück.
///
/// Zellen **unterhalb** der untersten Höhenlinie bleiben durchsichtig:
/// Keine Farbe heißt „weniger als die erste Stufe" und nicht „keine
/// Daten" — Letzteres ist ebenfalls durchsichtig, aber dort fehlen auch
/// die Linien, und die Legende sagt, wo die Messung aufhört.
///
/// Reines Dart samt PNG-Kodierung (zlib und CRC aus `package:archive`,
/// das für den KMZ-Import ohnehin im Projekt liegt) — damit läuft es im
/// Isolate, im Web und im Test, ohne `dart:ui` und ohne Canvas.
Uint8List rainFillPng(
  RainGrid grid, {
  required List<int> levels,
  int alpha = rainFillAlpha,
}) {
  final width = grid.width;
  final height = grid.height;
  // Eine Nachschlagetabelle statt einer Schleife je Zelle: 550 000 Zellen
  // mal acht Vergleiche wären Arbeit, die 255 Einträge einmal erledigen.
  final palette = Uint8List(256 * 4);
  for (var value = 0; value < 255; value++) {
    var band = 0;
    for (final level in levels) {
      if (value >= level) band++;
    }
    if (band == 0) continue; // durchsichtig, siehe oben
    final colour = AppColors.rainLine(band - 1);
    final offset = value * 4;
    palette[offset] = (colour.r * 255).round();
    palette[offset + 1] = (colour.g * 255).round();
    palette[offset + 2] = (colour.b * 255).round();
    palette[offset + 3] = alpha;
  }

  final raw = Uint8List(height * (width * 4 + 1));
  var cursor = 0;
  for (var y = 0; y < height; y++) {
    raw[cursor++] = 0; // Filter „None" — die Flächen sind ohnehin gleichförmig
    final row = y * width;
    for (var x = 0; x < width; x++) {
      final offset = grid.values[row + x] * 4;
      raw[cursor++] = palette[offset];
      raw[cursor++] = palette[offset + 1];
      raw[cursor++] = palette[offset + 2];
      raw[cursor++] = palette[offset + 3];
    }
  }

  return _png(width, height, raw);
}

Uint8List _png(int width, int height, Uint8List scanlines) {
  final header = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = Uint8List(13);
  final view = ByteData.view(ihdr.buffer);
  view.setUint32(0, width);
  view.setUint32(4, height);
  ihdr[8] = 8; // Bittiefe
  ihdr[9] = 6; // RGBA
  header.add(_chunk('IHDR', ihdr));
  header.add(_chunk(
      'IDAT', Uint8List.fromList(const ZLibEncoder().encode(scanlines))));
  header.add(_chunk('IEND', Uint8List(0)));
  return header.toBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final out = Uint8List(data.length + 12);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, data.length);
  for (var i = 0; i < 4; i++) {
    out[4 + i] = type.codeUnitAt(i);
  }
  out.setRange(8, 8 + data.length, data);
  view.setUint32(8 + data.length, getCrc32(out.sublist(4, 8 + data.length)));
  return out;
}
