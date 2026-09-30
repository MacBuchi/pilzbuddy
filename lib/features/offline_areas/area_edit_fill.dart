// Was auf dem Gerät liegt und was der Entwurf ändert — als EIN Bild über
// der Karte, solange die Werkzeugleiste der Kartenbereiche offen ist
// (#630, Stufe 2b).
//
// **Warum ein Bild und keine Polygone:** TrailBuddy zeichnet Maske,
// Schraffur und gestrichelte Ränder als Polygone und Linien seiner
// Kartenfassade. PilzBuddys Fassade kann keine Polygone, und beide
// Engines darum zu erweitern wäre die größere Baustelle als der Rest
// dieser Stufe. Ein Bild über den bewährten Weg der Wald- und
// Fundorte-Fläche (Isolate, `overlayPng`, in MapLibre `writeFill` +
// `applyImageFill`) können beide schon — und es liegt in Kartenkoordinaten,
// wandert also beim Verschieben mit.
//
// Die Regel aus TrailBuddy („Design Turn 2") bleibt: **Helligkeit = was
// auf dem Gerät liegt, Schraffur = offene Änderung.** Was nicht liegt,
// ist abgedunkelt; „kommt dazu" trägt helle Striche `/` auf dem Dunkel,
// „fällt weg" dunkle Striche `\` auf dem Hellen, beide mit einem Rand
// in derselben Tinte. Keine neue Farbe: Grün heißt auf dieser Karte Wald
// und Hauptaktion, Rot gibt es nicht.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/forest_data_providers.dart' show mapIdleBoundsProvider;
import '../map/forest_fill_window.dart';
import '../map/overlay_png.dart';
import '../map/rain_data_providers.dart' show rainGridRepositoryProvider;
import '../map/rain_grid.dart' show mercatorY;
import 'area_draw.dart';
import 'area_plan.dart';

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
        final key = TileSetShape.keyOf(x, y, zoom);
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

/// Der Bildausschnitt — Gedächtnis wie bei den anderen Flächen, geplant
/// über der ganzen Welt (Bereiche gibt es überall, wo der Host Kacheln
/// hat). Ohne offene Leiste null: dann rechnet hier nichts.
class AreaEditWindowNotifier extends Notifier<FillWindow?> {
  FillWindow? _last;

  @override
  FillWindow? build() {
    if (!ref.watch(areaToolsOpenProvider)) return _last = null;
    final bounds = ref.watch(mapIdleBoundsProvider);
    if (bounds == null) return _last;
    _last = planFillWindow(
          previous: _last,
          viewport: bounds,
          gridWest: -180,
          gridEast: 180,
          gridNorth: 85,
          gridSouth: -85,
        ) ??
        _last;
    return _last;
  }
}

final areaEditWindowProvider =
    NotifierProvider<AreaEditWindowNotifier, FillWindow?>(
        AreaEditWindowNotifier.new);

class AreaEditFill {
  const AreaEditFill({
    required this.png,
    required this.window,
    required this.revision,
  });

  final Uint8List png;
  final FillWindow window;

  /// Wechselt mit jedem Inhalt — gehört in den Dateinamen, weil die
  /// MapLibre-Strecke auf der URL idempotent ist.
  final String revision;

  double get west => window.west;
  double get east => window.east;
  double get north => window.north;
  double get south => window.south;
}

/// Das gemalte Bild — nur bei offener Leiste. Während der Neurechnung
/// behält `valueOrNull` den alten Stand.
final areaEditFillProvider = FutureProvider<AreaEditFill?>((ref) async {
  if (!ref.watch(areaToolsOpenProvider)) return null;
  final window = ref.watch(areaEditWindowProvider);
  if (window == null) return null;
  final stored = ref.watch(storedTileKeysProvider);
  final draft = ref.watch(areaDraftProvider);
  final adds = draft?.adds ?? const <int>{};
  final removes = draft?.removes ?? const <int>{};
  final png = await compute(_paint,
      (window: window, stored: stored, adds: adds, removes: removes));
  final revision = [
    stored.length,
    Object.hashAllUnordered(stored),
    adds.length,
    Object.hashAllUnordered(adds),
    removes.length,
    Object.hashAllUnordered(removes),
  ].map((v) => (v & 0x7fffffff).toRadixString(36)).join('-');
  return AreaEditFill(png: png, window: window, revision: revision);
});

Uint8List _paint(
        ({
          FillWindow window,
          Set<int> stored,
          Set<int> adds,
          Set<int> removes
        }) i) =>
    areaEditFillPng(
        window: i.window, stored: i.stored, adds: i.adds, removes: i.removes);

/// Dasselbe Bild als Datei — der Weg für MapLibre.
final areaEditFillFileProvider =
    FutureProvider<({String url, AreaEditFill fill})?>((ref) async {
  final fill = await ref.watch(areaEditFillProvider.future);
  if (fill == null) return null;
  final url = await ref.watch(rainGridRepositoryProvider).writeFill(
      'bereiche', DateTime.utc(2026, 1, 1), fill.png,
      variant: '${fill.window.key}_${fill.revision}');
  return url == null ? null : (url: url, fill: fill);
});
