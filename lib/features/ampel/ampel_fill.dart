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
// **Farben = die der Stufen-Worte in der Sektion** (forestGreen /
// forestBroadleaf), Deckkraft die der Regenfläche (140, gemessen in
// 1.48.0). „Ungünstig" bleibt TRANSPARENT: Die Karte hebt hervor, wo
// es sich lohnt, statt das Land braun zu färben — „keine Stufe heißt
// aussichtslos" gilt auf der Karte wörtlich. forestGreen liegt seit
// 1.46.0 auch in der Regen-Rampe auf der Karte; der eine bekannte
// Reibungspunkt (Ampel-Ocker über Laubwald-Ocker, wenn beide Ebenen
// liegen) steht im PR zur Betreiber-Abnahme.
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
    {int alpha = ampelFillAlpha}) {
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

  // Einfärben: drei Stufen, „ungünstig" und alles Unbeantwortbare
  // transparent.
  Color colour(AmpelLevel level) => switch (level) {
        AmpelLevel.guenstig => AppColors.forestGreen,
        AmpelLevel.verhalten => AppColors.forestBroadleaf,
        AmpelLevel.unguenstig => const Color(0x00000000),
      };
  final raw = Uint8List(height * (width * 4 + 1));
  var cursor = 0;
  for (var y = 0; y < height; y++) {
    raw[cursor++] = 0; // Filter „None"
    final blockRow = (y ~/ ampelTempBlockCells) * blocksX;
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      final block = blockRow + x ~/ ampelTempBlockCells;
      if (known[i] < ampelMinRainDays || blockUsable[block] == 0) {
        cursor += 4; // transparent — keine Aussage
        continue;
      }
      final effective =
          weighted[i] / weightsTotal * ampelRainWindow;
      final rainFactor = effective >= ampelRainSaturationMm
          ? 1.0
          : effective / ampelRainSaturationMm;
      final level = ampelLevelOf(rainFactor * blockFactor[block]);
      final c = colour(level);
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
  return AmpelFill(
    png: overlayPng(width, height, raw),
    west: info.west,
    east: info.east,
    north: info.north,
    south: info.south,
    newest: newest,
  );
}
