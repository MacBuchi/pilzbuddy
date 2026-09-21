// Die Farben der Fundorte-Scheiben (#467) müssen sich unterscheiden —
// und zwar so, wie sie auf der Karte liegen: mit der Deckkraft der
// Scheiben über dem Kartengrund. 1.154.0 hatte Magenta neben Rot; als
// Vollton zwei Farben, bei Alpha 130 zwei Rottöne (Betreiber,
// 2026-09-21). Ein Test auf die Vollton-Werte hätte das nicht gesehen.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/map/gbif_fill.dart';

/// Farbabstand in CIELAB (ΔE76) — grob, aber gut genug, um „zwei
/// Rottöne" von „zwei Farben" zu trennen. Ab etwa 20 gilt ein Paar als
/// auf einen Blick verschieden.
double deltaE(Color a, Color b) {
  List<double> lab(Color c) {
    double lin(double v) =>
        v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4).toDouble() : v / 12.92;
    final r = lin(c.r), g = lin(c.g), bl = lin(c.b);
    final x = (r * 0.4124 + g * 0.3576 + bl * 0.1805) / 0.95047;
    final y = r * 0.2126 + g * 0.7152 + bl * 0.0722;
    final z = (r * 0.0193 + g * 0.1192 + bl * 0.9505) / 1.08883;
    double f(double t) =>
        t > 0.008856 ? pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
  }

  final la = lab(a), lb = lab(b);
  return sqrt(pow(la[0] - lb[0], 2) + pow(la[1] - lb[1], 2) +
      pow(la[2] - lb[2], 2));
}

/// So sieht eine scharfe Scheibe auf der leeren Karte aus.
Color onMap(Color c) => Color.alphaBlend(
    c.withAlpha(gbifSharpAlpha), AppColors.mapBackground);

void main() {
  test('keine zwei Scheibenfarben sind auf der Karte Nachbarn', () {
    final family = {
      ...AppColors.gbifClassColours,
      'ohne Ampel': AppColors.gbifNoClass,
    };
    final keys = family.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      for (var j = i + 1; j < keys.length; j++) {
        final d = deltaE(onMap(family[keys[i]]!), onMap(family[keys[j]]!));
        // 22: Magenta gegen Rot lag bei 19, das gemessen engste Paar
        // der jetzigen Familie (Türkis gegen Grau) bei 24.
        expect(d, greaterThanOrEqualTo(22),
            reason: '${keys[i]} und ${keys[j]} liegen bei ΔE '
                '${d.toStringAsFixed(1)} — auf der Karte zwei Töne '
                'derselben Farbe');
      }
    }
  });

  test('das Blatt, die Legende und die Fläche nehmen dieselbe Tabelle',
      () {
    for (final entry in AppColors.gbifClassColours.entries) {
      expect(gbifClassColour(entry.key), entry.value);
    }
    expect(gbifClassColour(null), AppColors.gbifNoClass);
  });
}
