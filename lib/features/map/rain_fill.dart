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

import '../../core/app_colors.dart';
import 'overlay_png.dart';
import 'rain_grid.dart';

/// Deckkraft der Fläche, 0–255.
///
/// 140 ≈ 55 %. **Die Fläche ist seit 1.48.0 die Aussage, nicht mehr die
/// Orientierung** — die Höhenlinien werden nicht mehr gezeichnet.
///
/// Der Weg dorthin, gemessen statt geschätzt: Bei 82 (32 %) verschob die
/// Fläche die Kartenfarben um (−33, −20, −31) von 255. Das ist da, aber
/// zu wenig, um zwei benachbarte Bänder zu unterscheiden — der Betreiber
/// las es als „die Flächen sind gar nicht ausgefüllt", und für die
/// Nutzerin ist das dasselbe. Drei Varianten am Gerät verglichen
/// (2026-08-04, Ausschnitt Kassel–Göttingen): 32 % unsichtbar, 55 %
/// Bänder klar und Ortsnamen lesbar, 75 % Bänder sehr klar und Ortsnamen
/// verblasst — Letzteres genau der Befund, an dem die Vollfläche in
/// 1.45.0 gescheitert war. Der Betreiber hat 55 % gewählt.
///
/// **Die Obergrenze bleibt die Karte darunter.** Wer diesen Wert
/// hochdreht, holt 1.45.0 zurück.
const rainFillAlpha = 140;

/// Färbt das Gitter ein und gibt ein PNG zurück.
///
/// Zellen **unterhalb** der untersten Höhenlinie bleiben durchsichtig:
/// Keine Farbe heißt „weniger als die erste Stufe" und nicht „keine
/// Daten" — Letzteres ist ebenfalls durchsichtig, aber dort fehlen auch
/// die Linien, und die Legende sagt, wo die Messung aufhört.
///
/// [smooth] mittelt vorher über 3×3 — **dieselbe Vorgabe wie bei
/// [rainContours], und aus demselben Grund zwingend**: Die Linien
/// entstehen aus dem geglätteten Feld. Zeichnete die Fläche das rohe,
/// stünden zwei verschiedene Wahrheiten übereinander — eine Linie „50 mm"
/// mitten in einer Fläche, die dort schon zum nächsten Band gehört, und
/// Sprenkel genau dort, wo bewusst keine Linie gezogen wird (gemessen:
/// 3×3 entfernt 95 % der Einzelzellen). Die *exakten* Werte bleiben
/// davon unberührt — die liest die Regensumme am Spot aus dem rohen
/// Gitter.
///
/// Reines Dart; die PNG-Kodierung selbst liegt in `overlay_png.dart`.
Uint8List rainFillPng(
  RainGrid rawGrid, {
  required List<int> levels,
  int alpha = rainFillAlpha,
  bool smooth = true,
}) {
  final grid = smooth ? rawGrid.smoothed() : rawGrid;
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

  // Kodierung in `overlay_png.dart` — seit dem Waldgitter (#213) ein
  // geteilter Schreiber.
  return overlayPng(width, height, raw);
}
