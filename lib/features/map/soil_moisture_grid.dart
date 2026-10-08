// Die Bodenfeuchte aus dem ERA5-Land-Gitter (#676, seit 1.224.0): EINE
// Quelle für ganz DACH statt der nächsten DWD-Station (Betreiber,
// 2026-10-08: „am besten nur eine Quelle"). Gebaut in CI von
// `tool/soil_moisture.py`, ausgeliefert im Release `rain-data` wie die
// Regenstapel — kein neues Netzziel.
//
// Hier wird nichts gezeichnet, nur nachgeschlagen: 0,1° in Länge und
// Breite, jede Zellmitte auf einem ERA5-Land-Punkt, Zeile 0 im Norden.
// Ein Byte je Zelle, 0,003 m³/m³ je Stufe, 255 = keine Daten.
import 'dart:typed_data';

import '../../data/rain_grid_repository.dart' show RainStackData;
import '../ampel/ampel_model.dart' show ampelMoistureWindow;
import 'rain_grid.dart';

/// m³/m³ je Byte-Stufe — wie `MOISTURE_STEP` in `tool/soil_moisture.py`.
const soilMoistureStep = 0.003;

/// „Keine Daten" — über dem Meer und außerhalb von Deutschland und der
/// Alpenbox.
const soilMoistureNoData = 255;

/// Wie viele Tage die App den jüngsten echten Tag höchstens fortschreibt
/// (Betreiber, 2026-10-08: „Höchstens 8 Tage"). ERA5-Land hängt rund
/// fünf Tage nach; Labor 25 hat genau diese Naht gemessen (≤ 0,003
/// Log-Lik. je Stratum). Drei Tage Puffer decken einen ausgefallenen
/// Lauf der Datenstrecke; was darüber liegt, ist ungemessen — dann ist
/// die Klasse grau, statt mit einer alten Feuchte zu rechnen.
const soilMoistureMaxCarryDays = 8;

/// Das 26-Tage-Mittel je Zelle, bis zu einem festen Tag ([end]).
///
/// Fehlende Tage am Ende (ERA5-Land hängt nach) bekommen den Wert des
/// jüngsten echten Tags — das Fortschreiben macht die APP, nicht CI:
/// Ein in CI fortgeschriebener Tag sähe in der Datei gemessen aus
/// (`tool/CLAUDE.md`, „Bodenfeuchte-Gitter"). Eine Lücke MITTEN im
/// Fenster heißt dagegen „kein Mittel" — eine erfundene Feuchte wäre
/// eine erfundene Beobachtung, dieselbe Regel wie `feuchte_mittel` im
/// Werkzeug.
class SoilMoistureWindow {
  const SoilMoistureWindow({
    required this.end,
    required this.newest,
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.means,
    required this.latest,
  });

  /// Der letzte Tag des Fensters (gestern) und der jüngste ECHTE Tag.
  final DateTime end;
  final DateTime newest;

  final int width;
  final int height;
  final double west;
  final double east;
  final double north;
  final double south;

  /// Je Zelle das Mittel in m³/m³, NaN ohne lückenloses Fenster.
  final Float32List means;

  /// Je Zelle das Byte des jüngsten echten Tags — für die Zeile im
  /// Spot-Blatt.
  final Uint8List latest;

  /// Wie viele Tage am Ende fortgeschrieben sind.
  int get carriedDays => end.difference(newest).inDays.clamp(0, 1 << 20);

  /// Zu alt zum Rechnen — siehe [soilMoistureMaxCarryDays].
  bool get stale => carriedDays > soilMoistureMaxCarryDays;

  int? _cell(double lat, double lon) {
    final col = ((lon - west) / (east - west) * width).floor();
    final row = ((north - lat) / (north - south) * height).floor();
    if (col < 0 || col >= width || row < 0 || row >= height) return null;
    return row * width + col;
  }

  /// Das Mittel am Punkt — `null` außerhalb des Gitters, ohne Daten,
  /// mit Lücke oder wenn der Stand zu alt ist.
  double? meanAt(double lat, double lon) {
    if (stale) return null;
    final i = _cell(lat, lon);
    if (i == null) return null;
    final value = means[i];
    return value.isNaN ? null : value;
  }

  /// Der jüngste echte Wert am Punkt — `null` außerhalb oder ohne Daten.
  double? latestAt(double lat, double lon) {
    final i = _cell(lat, lon);
    if (i == null) return null;
    final byte = latest[i];
    return byte == soilMoistureNoData ? null : byte * soilMoistureStep;
  }

  /// Was am Spot gebraucht wird, in einem Stück.
  SpotSoilMoisture at(double lat, double lon) => SpotSoilMoisture(
        mean: meanAt(lat, lon),
        latest: latestAt(lat, lon),
        newest: newest,
        stale: stale,
      );
}

/// Die Bodenfeuchte an einem Punkt.
class SpotSoilMoisture {
  const SpotSoilMoisture({
    required this.mean,
    required this.latest,
    required this.newest,
    required this.stale,
  });

  /// 26-Tage-Mittel in m³/m³ — das, womit die Ampel rechnet.
  final double? mean;

  /// Der jüngste echte Tageswert in m³/m³ — das, was das Blatt zeigt.
  final double? latest;
  final DateTime newest;
  final bool stale;
}

/// Packt den Stapel aus und mittelt bis [end] (gestern) — `null`, wenn
/// der Stapel leer ist, ein Tag kaputt ist oder kein Tag bis [end]
/// reicht.
SoilMoistureWindow? soilMoistureWindowFrom(RainStackData stack, DateTime end) {
  final info = stack.info;
  final cells = info.width * info.height;
  final byDate = <int, Uint8List>{};
  DateTime? newest;
  for (final day in stack.days) {
    final age = end.difference(day.date).inDays;
    // Tage nach [end] zählen nicht — das Fenster endet gestern.
    if (age < 0) continue;
    if (newest == null || day.date.isAfter(newest)) newest = day.date;
    if (age >= ampelMoistureWindow) continue;
    try {
      byDate[age] = RainGrid.decode(
        day.gzipped,
        width: info.width,
        height: info.height,
        west: info.west,
        east: info.east,
        north: info.north,
        south: info.south,
        measured: day.date,
      ).values;
    } catch (_) {
      // Ein kaputter Tag ist eine Lücke — und eine Lücke heißt „kein
      // Mittel", nicht „Mittel aus dem Rest".
      return null;
    }
  }
  if (newest == null) return null;
  final carried = end.difference(newest).inDays;
  final latest = carried < ampelMoistureWindow
      ? byDate[carried]
      : null;

  final means = Float32List(cells);
  for (var i = 0; i < cells; i++) {
    means[i] = double.nan;
  }
  if (latest != null) {
    final sums = Float64List(cells);
    final known = Uint8List(cells);
    // Fortgeschriebene Tage tragen den Wert des jüngsten echten.
    for (var age = 0; age < ampelMoistureWindow; age++) {
      final grid = age < carried ? latest : byDate[age];
      if (grid == null) continue;
      for (var i = 0; i < cells; i++) {
        final byte = grid[i];
        if (byte == soilMoistureNoData) continue;
        sums[i] += byte * soilMoistureStep;
        known[i]++;
      }
    }
    for (var i = 0; i < cells; i++) {
      if (known[i] == ampelMoistureWindow) {
        means[i] = sums[i] / ampelMoistureWindow;
      }
    }
  }
  return SoilMoistureWindow(
    end: end,
    newest: newest,
    width: info.width,
    height: info.height,
    west: info.west,
    east: info.east,
    north: info.north,
    south: info.south,
    means: means,
    latest: latest ?? (Uint8List(cells)..fillRange(0, cells, soilMoistureNoData)),
  );
}
