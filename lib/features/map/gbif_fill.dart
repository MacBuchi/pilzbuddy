// Die Fläche der gemeldeten Fundorte (#467): je Zeile des Assets EINE
// Scheibe in der Größe ihrer Koordinaten-Unschärfe, als PNG durch
// dieselbe Bild-Overlay-Strecke wie Wald und Regen (`overlay_png.dart`).
//
// **Warum Scheiben und keine Heatmap.** Die Messung im Issue hat es
// entschieden: In Sammler-Auflösung wäre eine Dichtekarte auf 91–98 %
// von DACH leer, und „leer" läse sich als „hier wächst nichts". Eine
// Scheibe behauptet nur „hier hat jemand diese Art gemeldet, auf so
// viel Meter genau" — das ist wahr, Zeile für Zeile. Wo sich Scheiben
// überlagern, wird die Fläche dichter; die Dichte ENTSTEHT, sie wird
// nicht behauptet.
//
// **Die Größe ist die Unschärfe, nicht der Zoom.** Ein deutscher
// naturgucker-Punkt (250 m) ist bei Landkreis-Maßstab ein Pünktchen und
// beim Hineinzoomen ein Kreis von 500 m Durchmesser — genau die Fläche,
// innerhalb derer der Fund liegt. Ein Schweizer Quadrat (3535 m) bleibt
// die Fläche eines Quadrats. Nach unten gibt es eine Mindestgröße in
// Pixeln, sonst verschwänden die scharfen Punkte im Übersichtszoom;
// nach oben gibt es keine.
//
// **Scharf und grob tragen verschiedene Deckkraft.** Ein 250-m-Punkt
// sagt viel über wenig Fläche, ein 3,5-km-Quadrat wenig über viel —
// gleich kräftig gemalt, deckte die Schweiz die Karte zu, während
// Deutschland gesprenkelt bliebe. Und über allem liegt ein Deckel
// ([gbifMaxAlpha]): Auf einem Rasterpunkt mit dreißig Arten
// summierte sich die Deckkraft sonst zu einem undurchsichtigen Fleck,
// und die Obergrenze aller Flächen dieser Karte gilt auch hier — Wege
// und Ortsnamen darunter müssen lesbar bleiben.
//
// **Die groben Scheiben werden bei Bedarf KLEINER gemalt.** 40 000
// Schweizer Quadrate bei 100 km Fensterbreite sind Scheiben von 54 px
// Radius — 360 Millionen Pixeloperationen, im Isolate mehrere Sekunden.
// Übersteigt die Summe der Scheibenflächen das Budget, entstehen sie in
// einem um 2, 4, 8 … verkleinerten Puffer und werden bilinear
// hochgezogen; für Scheiben dieser Größe ist das nicht zu sehen. Die
// scharfen Punkte bleiben immer in voller Auflösung — sie sind klein
// und billig, und an ihnen sähe man es.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;

import '../../core/app_colors.dart';
import '../ampel/ampel_model.dart' show ampelClassFor, ampelClassKeyOf;
import 'forest_fill_window.dart';
import 'gbif_finds.dart';
import 'overlay_png.dart';
import 'rain_grid.dart' show mercatorY;

/// Deckkraft einer scharfen Scheibe (Unschärfe bis [gbifCoarseFromM]).
const gbifSharpAlpha = 130;

/// Deckkraft einer groben Scheibe — Quadrate, Rasterpunkte, unbekannt.
const gbifCoarseAlpha = 48;

/// Ab hier gilt eine Meldung als grob.
const gbifCoarseFromM = 1000;

/// Deckel über der SUMME — siehe Kopfkommentar.
const gbifMaxAlpha = 175;

/// Kleiner wird keine Scheibe, sonst verschwinden die scharfen Punkte im
/// Übersichtszoom.
const gbifMinRadiusPx = 3.0;

/// Pixeloperationen, die der grobe Puffer in voller Auflösung höchstens
/// kosten darf; darüber wird verkleinert gemalt.
const gbifPaintBudget = 24 * 1000 * 1000;

/// Meter je Grad Länge am Äquator.
const _metersPerDegree = 111320.0;

/// Was der Maler je Art wissen muss — vorab im Haupt-Isolate aufgelöst,
/// damit drüben weder `ampelClassFor` noch die Artenliste gebraucht
/// werden: [colours] ARGB je Artindex, [allowed] 1 = zeichnen.
typedef GbifPaint = ({Int32List colours, Uint8List allowed});

/// Farbe und Sichtbarkeit je Art.
///
/// [species] und [classes] sind die Mengen aus `SpotFilter` — **leer =
/// alle**, wie dort. Die Klassenwahl greift auf die Ampel-Klasse der
/// Art; eine Art OHNE Klasse fällt bei gesetzter Klassenwahl heraus,
/// wie beim Ampel-Filter der Spots. Die Farbe kommt aus
/// [AppColors.gbifClassColours], grau für Arten ohne Klasse.
GbifPaint gbifPaintFor(GbifFinds finds,
    {Set<String> species = const {}, Set<String> classes = const {}}) {
  final colours = Int32List(finds.species.length);
  final allowed = Uint8List(finds.species.length);
  for (var i = 0; i < finds.species.length; i++) {
    final name = finds.species[i].name;
    final klass = ampelClassFor(name);
    final key = klass == null ? null : ampelClassKeyOf(klass);
    final colour = key == null
        ? AppColors.gbifNoClass
        : AppColors.gbifClassColours[key] ?? AppColors.gbifNoClass;
    colours[i] = colour.toARGB32();
    final speciesOk = species.isEmpty || species.contains(name);
    final classOk = classes.isEmpty || (key != null && classes.contains(key));
    allowed[i] = speciesOk && classOk ? 1 : 0;
  }
  return (colours: colours, allowed: allowed);
}

/// Malt die Fundorte in [window] und gibt ein PNG zurück.
///
/// Die Zeilen liegen MERCATOR-verteilt wie beim Wald (#247): Beide
/// Engines spannen ein Bild linear in Web-Mercator auf.
Uint8List gbifFillPng(GbifFinds finds,
    {required FillWindow window,
    required GbifPaint paint,
    int budget = gbifPaintBudget}) {
  final width = window.width;
  final rows = window.height;
  final lonSpan = window.east - window.west;
  final mercNorth = mercatorY(window.north);
  final mercSpan = mercatorY(window.south) - mercNorth;
  final degPerPx = lonSpan / width;

  // Erst sammeln, dann malen: Die groben Scheiben brauchen die SUMME
  // ihrer Flächen, bevor der Puffer dimensioniert werden kann.
  final sharp = _DiscList();
  final coarse = _DiscList();
  var coarseArea = 0.0;
  for (var i = 0; i < finds.length; i++) {
    final s = finds.speciesIndex[i];
    if (paint.allowed[s] == 0) continue;
    final lat = finds.latAt(i);
    final lon = finds.lonAt(i);
    final cx = (lon - window.west) / lonSpan * width;
    final cy = (mercatorY(lat) - mercNorth) / mercSpan * rows;
    final metersPerPx =
        degPerPx * _metersPerDegree * math.cos(lat * math.pi / 180);
    final unc = finds.uncertaintyAt(i);
    final r = math.max(gbifMinRadiusPx, unc / metersPerPx);
    if (cx + r < 0 || cx - r > width || cy + r < 0 || cy - r > rows) {
      continue;
    }
    final colour = paint.colours[s];
    if (unc > gbifCoarseFromM) {
      coarse.add(cx, cy, r, colour, gbifCoarseAlpha);
      // Nur der SICHTBARE Teil zählt fürs Budget — eine Scheibe, die das
      // Fenster überragt, kostet höchstens das Fenster.
      coarseArea += math.min(math.pi * r * r, width * rows.toDouble());
    } else {
      sharp.add(cx, cy, r, colour, gbifSharpAlpha);
    }
  }

  var scale = 1;
  while (coarseArea / (scale * scale) > budget) {
    scale *= 2;
  }

  final canvas = _Canvas(width, rows);
  if (coarse.length > 0) {
    if (scale == 1) {
      coarse.paintInto(canvas, 1);
    } else {
      final small = _Canvas((width / scale).ceil(), (rows / scale).ceil());
      coarse.paintInto(small, scale);
      canvas.drawUpscaled(small, scale);
    }
  }
  sharp.paintInto(canvas, 1);
  return overlayPng(width, rows, canvas.scanlines(maxAlpha: gbifMaxAlpha));
}

/// Scheiben, gesammelt als flache Listen — kein Objekt je Zeile.
class _DiscList {
  final _cx = <double>[];
  final _cy = <double>[];
  final _r = <double>[];
  final _colour = <int>[];
  final _alpha = <int>[];

  int get length => _cx.length;

  void add(double cx, double cy, double r, int colour, int alpha) {
    _cx.add(cx);
    _cy.add(cy);
    _r.add(r);
    _colour.add(colour);
    _alpha.add(alpha);
  }

  /// Malt alle Scheiben in [canvas], dessen Pixel [scale]-mal so groß
  /// sind wie die Fensterpixel.
  void paintInto(_Canvas canvas, int scale) {
    for (var i = 0; i < _cx.length; i++) {
      canvas.disc(_cx[i] / scale, _cy[i] / scale, _r[i] / scale, _colour[i],
          _alpha[i]);
    }
  }
}

/// Ein RGBA-Puffer mit gerader (nicht vormultiplizierter) Deckkraft und
/// Source-over-Mischung.
class _Canvas {
  _Canvas(this.width, this.height) : rgba = Uint8List(width * height * 4);

  final int width;
  final int height;
  final Uint8List rgba;

  /// Source-over für EIN Pixel, Ganzzahlen.
  void blend(int x, int y, int r, int g, int b, int a) {
    if (a <= 0) return;
    final o = (y * width + x) * 4;
    final da = rgba[o + 3];
    if (da == 0) {
      rgba[o] = r;
      rgba[o + 1] = g;
      rgba[o + 2] = b;
      rgba[o + 3] = a;
      return;
    }
    // outA = a + da·(1−a); outC = (c·a + dc·da·(1−a)) / outA — alles in
    // 1/255-Einheiten, gerundet.
    final keep = da * (255 - a); // ×255
    final outA255 = a * 255 + keep; // outA ×255
    rgba[o] = (r * a * 255 + rgba[o] * keep) ~/ outA255;
    rgba[o + 1] = (g * a * 255 + rgba[o + 1] * keep) ~/ outA255;
    rgba[o + 2] = (b * a * 255 + rgba[o + 2] * keep) ~/ outA255;
    rgba[o + 3] = (outA255 + 127) ~/ 255;
  }

  /// Eine Scheibe mit weicher Kante: Der äußerste Pixelring bekommt die
  /// halbe Deckkraft. Mehr Kantenglättung braucht eine Fläche mit
  /// dieser Deckkraft nicht.
  void disc(double cx, double cy, double radius, int colour, int alpha) {
    final r = (colour >> 16) & 0xFF;
    final g = (colour >> 8) & 0xFF;
    final b = colour & 0xFF;
    final inner = math.max(0.0, radius - 1.0);
    final y0 = math.max(0, (cy - radius).floor());
    final y1 = math.min(height - 1, (cy + radius).ceil());
    for (var y = y0; y <= y1; y++) {
      final dy = y + 0.5 - cy;
      final dy2 = dy * dy;
      if (dy2 > radius * radius) continue;
      final halfOuter = math.sqrt(radius * radius - dy2);
      final halfInner2 = inner * inner - dy2;
      final halfInner = halfInner2 > 0 ? math.sqrt(halfInner2) : -1.0;
      final x0 = math.max(0, (cx - halfOuter).floor());
      final x1 = math.min(width - 1, (cx + halfOuter).ceil());
      for (var x = x0; x <= x1; x++) {
        final dx = (x + 0.5 - cx).abs();
        if (dx > halfOuter) continue;
        blend(x, y, r, g, b, dx <= halfInner ? alpha : alpha ~/ 2);
      }
    }
  }

  /// Zieht [small] bilinear auf diesen Puffer hoch — in VORMULTIPLIZIERTER
  /// Form, sonst zieht die Mischung mit durchsichtigen Nachbarn dunkle
  /// Ränder um jede Scheibe.
  void drawUpscaled(_Canvas small, int scale) {
    final sw = small.width;
    final sh = small.height;
    final src = small.rgba;
    for (var y = 0; y < height; y++) {
      final fy = ((y + 0.5) / scale - 0.5).clamp(0.0, sh - 1.0);
      final y0 = fy.floor();
      final y1 = math.min(sh - 1, y0 + 1);
      final wy = fy - y0;
      for (var x = 0; x < width; x++) {
        final fx = ((x + 0.5) / scale - 0.5).clamp(0.0, sw - 1.0);
        final x0 = fx.floor();
        final x1 = math.min(sw - 1, x0 + 1);
        final wx = fx - x0;
        var pr = 0.0, pg = 0.0, pb = 0.0, pa = 0.0;
        void tap(int sx, int sy, double w) {
          if (w == 0) return;
          final o = (sy * sw + sx) * 4;
          final a = src[o + 3] / 255 * w;
          pr += src[o] * a;
          pg += src[o + 1] * a;
          pb += src[o + 2] * a;
          pa += a;
        }

        tap(x0, y0, (1 - wx) * (1 - wy));
        tap(x1, y0, wx * (1 - wy));
        tap(x0, y1, (1 - wx) * wy);
        tap(x1, y1, wx * wy);
        if (pa <= 0) continue;
        final o = (y * width + x) * 4;
        rgba[o] = (pr / pa).round();
        rgba[o + 1] = (pg / pa).round();
        rgba[o + 2] = (pb / pa).round();
        rgba[o + 3] = (pa * 255).round().clamp(0, 255);
      }
    }
  }

  /// PNG-Scanlines (Filter-Byte 0 je Zeile), Deckkraft bei [maxAlpha]
  /// gedeckelt.
  Uint8List scanlines({required int maxAlpha}) {
    final out = Uint8List(height * (width * 4 + 1));
    var cursor = 0;
    var src = 0;
    for (var y = 0; y < height; y++) {
      out[cursor++] = 0;
      for (var x = 0; x < width; x++) {
        out[cursor++] = rgba[src++];
        out[cursor++] = rgba[src++];
        out[cursor++] = rgba[src++];
        out[cursor++] = math.min(maxAlpha, rgba[src++]);
      }
    }
    return out;
  }
}

/// Die Farbe einer Ampel-Klasse in der Legende — dieselbe Tabelle wie
/// beim Malen, damit Legende und Fläche nie zwei Töne zeigen.
Color gbifClassColour(String? classKey) => classKey == null
    ? AppColors.gbifNoClass
    : AppColors.gbifClassColours[classKey] ?? AppColors.gbifNoClass;
