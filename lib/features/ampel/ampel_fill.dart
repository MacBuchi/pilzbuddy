// Die Pilzwetter-Rechnung für die Karte (Frage b der Ampel-Vorschau,
// 2026-08-09): „Wo in meiner Umgebung ist es zurzeit besonders gut?" —
// gerechnet aus denselben lokalen Gittern wie die Spot-Ampel. KEINE
// fremden Spots, keine Koordinate verlässt das Gerät.
//
// **Die Ampel färbt nur noch WALD** (Betreiber, 2026-08-10: „ich würde
// die Pilzampel auch nur mit dem Wald überlagern, es gibt keinen Grund,
// warum man andere Bereiche damit einfärben sollte"). Bis 1.75.0 lag sie
// als eigene Fläche über allem — auch über Feldern, Städten und Seen, wo
// die Aussage niemanden interessiert. Seit 1.76.0 gibt es nur noch die
// Kombi-Ebene: Der Wabenzeichner der Waldfläche
// (`forestAmpelFillPng`) lässt die Waben leuchten, wo das Wetter stimmt.
//
// Übrig bleibt hier die RECHNUNG — die Stufe je Zelle, ohne Farbe. Genau
// das ist auch das, was der Betreiber als Zukunftsbild beschrieben hat:
// dieselben Sechsecke, auf Array-Ebene gefärbt, ein Rendern statt zwei
// Ebenen übereinander.
import 'dart:typed_data';

import '../../core/geo.dart' show distanceKm;
import '../../data/rain_grid_repository.dart' show RainStackData;
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
}
