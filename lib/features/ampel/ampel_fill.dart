// Die Pilzwetter-Fläche (Frage b der Ampel-Vorschau, 2026-08-09):
// „Wo in meiner Umgebung ist es zurzeit besonders gut?" — als Ebene
// über Deutschland, gerechnet aus denselben lokalen Gittern wie die
// Spot-Ampel. KEINE fremden Spots, keine Koordinate verlässt das
// Gerät: Es ist reine Wetterfläche.
//
// Dieselbe Bild-Overlay-Strecke wie Regen (#156) und Wald (#213): das
// Stapel-Gitter direkt eingefärbt, ein Pixel je Zelle, als PNG. Das
// Regen-Gitter hat ~550 000 Zellen — der Puffer ist mit ~2 MB der
// bewährte Normalfall dieser Strecke, kein Fensterproblem wie beim
// 100-m-Wald.
//
// **Farben aus einer wählbaren Familie** ([AmpelPalette]), Deckkraft die
// der Regenfläche (140, gemessen in 1.48.0). Bis 1.74.0 lieh sich die
// Fläche die Töne der Stufen-Worte (forestGreen / forestBroadleaf) —
// und stand damit im selben Grün-Ocker wie die Waldebene, mit der man
// sie kombinieren WILL: Über Laubwald war „verhalten" nicht mehr zu
// erkennen (Betreiber-Rückmeldung zur 1.73.0). Seither bricht die
// Ampel aus den Erdtönen aus; die Begründung je Familie steht an
// [AmpelPalette].
//
// „Ungünstig" bleibt TRANSPARENT: Die Karte hebt hervor, wo es sich
// lohnt, statt das Land braun zu färben — „keine Stufe heißt
// aussichtslos" gilt auf der Karte wörtlich.
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;

import '../../core/app_colors.dart';
import '../../core/geo.dart' show distanceKm;
import '../../data/rain_grid_repository.dart' show RainStackData;
import '../map/overlay_png.dart';
import '../map/rain_grid.dart';
import '../map/spot_weather.dart';
import 'ampel_model.dart';
import 'ampel_providers.dart' show ampelMinRainDays, ampelMinTempDays;

/// Deckkraft wie die Regenfläche — dieselbe Messung, dieselbe
/// Obergrenze: Die Karte darunter muss lesbar bleiben.
const ampelFillAlpha = 140;

/// Kantenlänge der Temperatur-Blöcke in Zellen (~16 km): Stationen
/// stehen ~30 km auseinander, eine feinere Zuordnung wäre
/// Scheingenauigkeit — und je Zelle die nächste von ~460 Stationen zu
/// suchen wäre eine Viertelmilliarde Distanzen.
const ampelTempBlockCells = 16;

/// Das Ergebnis: PNG plus die Grenzen SEINES Gitters und der jüngste
/// Tag (er wird zum Dateinamen — ein neuer Stand braucht eine neue
/// URL, die MapLibre-Strecke ist idempotent darauf).
class AmpelFill {
  const AmpelFill({
    required this.png,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.newest,
  });

  final Uint8List png;
  final double west;
  final double east;
  final double north;
  final double south;
  final DateTime newest;
}

/// Färbt die Fläche ein — `null`, wenn der Stapel die 26 Modell-Tage
/// nicht lückenlos trägt (dieselbe Strenge wie die Sektion: lieber
/// keine Ebene als eine mit still verschobenen Altersgewichten; ein
/// DWD-Lückentag heilt sich am Folgetag von selbst).
AmpelFill? ampelFillFrom(RainStackData stack, WeatherTable? table,
    {int alpha = ampelFillAlpha,
    AmpelPalette palette = defaultAmpelPalette}) {
  final grid = ampelLevelsFrom(stack, table);
  return grid == null
      ? null
      : ampelFillOfLevels(grid, palette: palette, alpha: alpha);
}

/// Dasselbe Bild aus einem fertigen Stufen-Gitter — der Weg der App:
/// Die Stufen rechnet ein Isolate einmal, das Einfärben läuft danach je
/// Farbwahl neu, ohne die 26 Gitter noch einmal auszupacken.
AmpelFill ampelFillOfLevels(AmpelLevelGrid grid,
        {AmpelPalette palette = defaultAmpelPalette,
        int alpha = ampelFillAlpha}) =>
    AmpelFill(
      png: overlayPng(grid.width, grid.height, grid.paint(palette, alpha)),
      west: grid.west,
      east: grid.east,
      north: grid.north,
      south: grid.south,
      newest: grid.newest,
    );

/// Dasselbe Ergebnis eine Stufe früher: die STUFE je Zelle, noch ohne
/// Farbe. Zwei Kunden — die Fläche oben und die Kombi-Ebene „Wald +
/// Pilzwetter" (dort fragt jede Waldwabe ihren Mittelpunkt ab).
///
/// `null` unter denselben Bedingungen wie die Fläche: kein lückenloses
/// 26-Tage-Fenster, keine Stationstabelle.
AmpelLevelGrid? ampelLevelsFrom(RainStackData stack, WeatherTable? table) {
  final info = stack.info;
  final width = info.width;
  final height = info.height;

  // Die 26 Kalendertage bis zum jüngsten, lückenlos — Index == Alter,
  // exakt die Ordnung, die auch `ampelReadingFrom` ans Modell gibt.
  final byDate = <int, ({DateTime date, List<int> gzipped})>{};
  DateTime? newest;
  for (final day in stack.days) {
    if (newest == null || day.date.isAfter(newest)) newest = day.date;
  }
  if (newest == null) return null;
  for (final day in stack.days) {
    final age = newest.difference(day.date).inDays;
    if (age >= 0 && age < ampelRainWindow) byDate[age] = day;
  }
  if (byDate.length < ampelRainWindow) return null;

  // Regen: gewichtete Kumulation je Zelle, ein Tag nach dem anderen im
  // Speicher (die Lehre des Stapels: alle auf einmal wären ~10 MB roh).
  final weighted = Float32List(width * height);
  final known = Uint8List(width * height);
  var weightsTotal = 0.0;
  for (var age = 0; age < ampelRainWindow; age++) {
    final weight = 1.0 - age / ampelRainWindow;
    weightsTotal += weight;
    final RainGrid grid;
    try {
      grid = RainGrid.decode(
        byDate[age]!.gzipped,
        width: width,
        height: height,
        west: info.west,
        east: info.east,
        north: info.north,
        south: info.south,
        measured: byDate[age]!.date,
      );
    } catch (_) {
      // Ein kaputter Tag macht die Ebene unehrlich — weg damit, wie
      // bei der lückigen Reihe.
      return null;
    }
    for (var i = 0; i < width * height; i++) {
      final mm = grid.values[i];
      if (mm == rainNoData) continue;
      weighted[i] += mm * weight;
      known[i]++;
    }
  }

  // Temperatur: Faktor je Station einmal, dann je ~16-km-Block die
  // nächste brauchbare Station — zwischen den Blöcken konstant.
  final stationFactors = <({double lat, double lon, double factor})>[];
  for (final station in table?.air ?? const <AirStation>[]) {
    final maxs = station.max;
    final mins = station.min;
    final temps = <double?>[
      for (var i = maxs.length - 1; i >= 0; i--)
        (maxs[i] != null && mins[i] != null)
            ? (maxs[i]! + mins[i]!) / 2
            : null,
    ];
    final tempKnown =
        temps.take(ampelTempWindow).where((c) => c != null).length;
    if (tempKnown < ampelMinTempDays) continue;
    stationFactors.add((
      lat: station.lat,
      lon: station.lon,
      factor: ampelTemperatureFactor(temps),
    ));
  }
  if (stationFactors.isEmpty) return null;

  final blocksX = (width + ampelTempBlockCells - 1) ~/ ampelTempBlockCells;
  final blocksY = (height + ampelTempBlockCells - 1) ~/ ampelTempBlockCells;
  final blockFactor = Float32List(blocksX * blocksY);
  final blockUsable = Uint8List(blocksX * blocksY);
  final probe = RainGrid(
    values: Uint8List(0),
    width: width,
    height: height,
    west: info.west,
    east: info.east,
    north: info.north,
    south: info.south,
    measured: newest,
  );
  for (var by = 0; by < blocksY; by++) {
    // Mitte aus Blockanfang und -ENDE — der letzte (angeschnittene)
    // Block hat seine Mitte sonst außerhalb des Gitters.
    final rowEnd = (by + 1) * ampelTempBlockCells > height
        ? height
        : (by + 1) * ampelTempBlockCells;
    final lat =
        probe.latAtRow((by * ampelTempBlockCells + rowEnd) / 2);
    for (var bx = 0; bx < blocksX; bx++) {
      final colEnd = (bx + 1) * ampelTempBlockCells > width
          ? width
          : (bx + 1) * ampelTempBlockCells;
      final lon =
          probe.lonAtColumn((bx * ampelTempBlockCells + colEnd) / 2);
      double bestKm = double.infinity;
      double bestFactor = 0;
      for (final station in stationFactors) {
        final km = distanceKm(lat, lon, station.lat, station.lon);
        if (km < bestKm) {
          bestKm = km;
          bestFactor = station.factor;
        }
      }
      if (bestKm <= WeatherTable.maxStationKm) {
        blockFactor[by * blocksX + bx] = bestFactor;
        blockUsable[by * blocksX + bx] = 1;
      }
    }
  }

  // Die Stufe je Zelle. 0 heißt „keine Aussage" — zu wenige Regentage
  // oder keine Station in Reichweite; auf der Karte ist beides
  // transparent, und in der Kombi-Ebene leuchtet dort nichts.
  final levels = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final blockRow = (y ~/ ampelTempBlockCells) * blocksX;
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      final block = blockRow + x ~/ ampelTempBlockCells;
      if (known[i] < ampelMinRainDays || blockUsable[block] == 0) continue;
      final effective = weighted[i] / weightsTotal * ampelRainWindow;
      final rainFactor = effective >= ampelRainSaturationMm
          ? 1.0
          : effective / ampelRainSaturationMm;
      levels[i] = ampelLevelOf(rainFactor * blockFactor[block]).index + 1;
    }
  }
  return AmpelLevelGrid(
    levels: levels,
    width: width,
    height: height,
    west: info.west,
    east: info.east,
    north: info.north,
    south: info.south,
    newest: newest,
  );
}

/// Die Ampel-Stufen als Gitter — dieselbe Geometrie wie das
/// Regen-Gitter, aus dem sie stammen (Mercator-Zeilen!).
class AmpelLevelGrid {
  const AmpelLevelGrid({
    required this.levels,
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.newest,
  });

  /// Je Zelle: 0 = keine Aussage, sonst `AmpelLevel.index + 1`.
  final Uint8List levels;
  final int width;
  final int height;
  final double west;
  final double east;
  final double north;
  final double south;

  /// Der jüngste Tag des Stapels — der „Stand" für Dateinamen.
  final DateTime newest;

  /// Die Stufe an einem Punkt — `null` außerhalb des Gitters oder wo es
  /// keine Aussage gibt.
  AmpelLevel? levelAt(double lat, double lon) {
    final row = rowAt(lat);
    final column = columnAt(lon);
    if (row == null || column == null) return null;
    return levelAtCell(row, column);
  }

  /// Die Gitterzeile zu einer Breite — `null` außerhalb.
  ///
  /// **Zeilen in MERCATOR**, wie beim Regen: In Grad gerechnet läge die
  /// Zuordnung am Südrand um Kilometer daneben (dieselbe Falle wie
  /// #247).
  ///
  /// Getrennt von [columnAt], weil die Kombi-Ebene über WABENZEILEN
  /// läuft: Die Breite ist dort je Zeile konstant, die Länge ändert sich
  /// je Wabe. So kostet die Zeile einmal zwei Logarithmen statt einmal
  /// je Wabe — bei Millionen Waben ist das der Unterschied zwischen
  /// „läuft" und „ruckelt".
  int? rowAt(double lat) {
    if (lat > north || lat < south) return null;
    final top = mercatorY(north);
    final fraction = (mercatorY(lat) - top) / (mercatorY(south) - top);
    final row = (fraction * height).floor();
    return row < 0 || row >= height ? null : row;
  }

  /// Die Gitterspalte zu einer Länge — `null` außerhalb.
  int? columnAt(double lon) {
    if (lon < west || lon > east) return null;
    final column = ((lon - west) / (east - west) * width).floor();
    return column < 0 || column >= width ? null : column;
  }

  /// Die Stufe einer Zelle — ohne Bereichsprüfung, wie [RainGrid.at].
  AmpelLevel? levelAtCell(int row, int column) {
    final value = levels[row * width + column];
    return value == 0 ? null : AmpelLevel.values[value - 1];
  }

  /// Die Fläche als PNG-Scanlines: drei Stufen, „ungünstig" und alles
  /// Unbeantwortbare transparent.
  Uint8List paint(AmpelPalette palette, int alpha) {
    Color colour(AmpelLevel level) => switch (level) {
          AmpelLevel.guenstig => palette.strong,
          AmpelLevel.verhalten => palette.mild,
          AmpelLevel.unguenstig => const Color(0x00000000),
        };
    final raw = Uint8List(height * (width * 4 + 1));
    var cursor = 0;
    for (var y = 0; y < height; y++) {
      raw[cursor++] = 0; // Filter „None"
      for (var x = 0; x < width; x++) {
        final value = levels[y * width + x];
        if (value == 0) {
          cursor += 4;
          continue;
        }
        final c = colour(AmpelLevel.values[value - 1]);
        if (c.a == 0) {
          cursor += 4;
          continue;
        }
        raw[cursor++] = (c.r * 255).round();
        raw[cursor++] = (c.g * 255).round();
        raw[cursor++] = (c.b * 255).round();
        raw[cursor++] = alpha;
      }
    }
    return raw;
  }
}
