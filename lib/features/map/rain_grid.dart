// Das Regen-Wertegitter: ein Byte je Quadratkilometer, wie es
// `tool/rain_grid.py` veröffentlicht.
//
// Reines Dart ohne Flutter — damit `test/rain_grid_test.dart` das Format
// ohne Karte prüfen kann. Ein falsch ausgepacktes Gitter fällt sonst erst
// als merkwürdige Linie auf dem Gerät auf, und dort ist nicht zu
// unterscheiden, ob die Daten, das Auspacken oder die Konturen schuld sind.
//
// **Warum überhaupt Werte statt fertiger Linien** (gemessen am 2026-08-04):
// Fertige Konturlinien wären mit 55 KB kleiner als die 216 KB dieses
// Gitters. Die 161 KB kaufen drei Dinge, die Linien nicht können — die
// Regenmenge am Spot als exakte Zahl statt als Klassenspanne, das
// Nachjustieren der Höhenstufen ohne neuen CI-Lauf (die DWD-Legende stuft
// alle 30 mm, der deutsche Median lag am 3.8. bei 37 mm — das wird sich
// ändern müssen), und die Konturlogik in Dart, wo `flutter test` sie deckt.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'contours.dart';

/// Der Wert für „hier wissen wir nichts".
///
/// Der DWD schreibt Nichtdaten sowohl als `-1.0` als auch als `NaN`;
/// `tool/rain_grid.py` fasst beides zu diesem einen Byte zusammen.
const rainNoData = 255;

/// Der Deckel der Quantisierung. Mehr als 254 mm in 30 Tagen kommt vor,
/// wird aber abgeschnitten — im Sommer 2026 lag das deutsche Maximum bei
/// 194 mm. Wer den Deckel erreicht sieht, hat ein anderes Problem als die
/// Genauigkeit dieser Zahl.
const rainMaxMm = 254;

/// Ein ausgepacktes Gitter samt seiner Ausdehnung.
class RainGrid {
  const RainGrid({
    required this.values,
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.measured,
  });

  /// `width * height` Bytes, zeilenweise von Nord nach Süd.
  final Uint8List values;
  final int width;
  final int height;

  /// Die AUSSENKANTEN des Gitters in Grad — nicht Zellmittelpunkte.
  final double west;
  final double east;
  final double north;
  final double south;

  /// Wann gemessen wurde, nicht wann geladen wurde. Der Unterschied ist
  /// bei der 30-Tage-Summe bis zu einem Tag und gehört dem Benutzer
  /// gesagt.
  final DateTime measured;

  /// Packt aus, was `tool/rain_grid.py` geschrieben hat: gzip, darunter
  /// ein Zeilen-Delta.
  ///
  /// Das Delta wird JE ZEILE zurückgesetzt. Wer das vergisst, bekommt
  /// eine korrekte erste Zeile und Unsinn darunter — deshalb prüft
  /// `test/rain_grid_test.dart` genau das mit einem Gitter, dessen
  /// Zeilen unterschiedlich anfangen.
  factory RainGrid.decode(
    List<int> gzipped, {
    required int width,
    required int height,
    required double west,
    required double east,
    required double north,
    required double south,
    required DateTime measured,
  }) {
    final flat = GZipDecoder().decodeBytes(gzipped);
    if (flat.length != width * height) {
      throw FormatException(
          'Gitter hat ${flat.length} Bytes, erwartet ${width * height}');
    }
    final values = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      var previous = 0;
      for (var x = 0; x < width; x++) {
        previous = (previous + flat[row + x]) & 0xFF;
        values[row + x] = previous;
      }
    }
    return RainGrid(
      values: values,
      width: width,
      height: height,
      west: west,
      east: east,
      north: north,
      south: south,
      measured: measured,
    );
  }

  /// Die Niederschlagsmenge an einem Punkt in Millimetern — `null`
  /// außerhalb des Gitters oder wo keine Daten liegen.
  ///
  /// DAS ist der Grund, warum das Gitter überhaupt auf dem Gerät liegt:
  /// Die Frage „wie viel Regen an diesem Spot" ist damit ein Feldzugriff.
  /// Eine Wetterabfrage je Spotkoordinate wäre die Preisgabe der
  /// Fundstelle — der DWD beantwortet sie bereitwillig
  /// (`GetFeatureInfo`), und genau deshalb wird sie nicht gestellt.
  int? mmAt(double lat, double lon) {
    if (lon < west || lon > east || lat > north || lat < south) return null;
    final x = ((lon - west) / (east - west) * width).floor();
    final y = (_mercatorFraction(lat) * height).floor();
    if (x < 0 || x >= width || y < 0 || y >= height) return null;
    final value = values[y * width + x];
    return value == rainNoData ? null : value;
  }

  /// Wo `lat` zwischen Nord- und Südkante liegt, 0 bis 1 — gerechnet IN
  /// MERCATOR, weil das Gitter dort gleichmäßig ist. In Grad gerechnet
  /// läge der Wert am Südrand Deutschlands um mehrere Kilometer daneben.
  double _mercatorFraction(double lat) {
    final top = mercatorY(north);
    return (mercatorY(lat) - top) / (mercatorY(south) - top);
  }

  /// Die Breite eines Gitterpunkts (Zellmitte) in Grad.
  double latAtRow(double row) {
    final top = mercatorY(north);
    final bottom = mercatorY(south);
    return latFromMercatorY(top + (bottom - top) * row / height);
  }

  /// Die Länge eines Gitterpunkts (Zellmitte) in Grad.
  double lonAtColumn(double column) =>
      west + (east - west) * column / width;

  /// Der Wert einer Zelle, `null` bei Nichtdaten. Ohne Bereichsprüfung —
  /// die Aufrufer laufen über das Gitter.
  int? at(int x, int y) {
    final value = values[y * width + x];
    return value == rainNoData ? null : value;
  }

  /// Dasselbe Gitter, über 3×3 gemittelt — **nur zum Zeichnen**.
  ///
  /// Gemessen am echten Deutschland-Gitter (2026-08-04): Die Zahl der
  /// Konturketten fällt von 8 874 auf 1 995, die Punkte nach der
  /// Vereinfachung von 28 806 auf 10 969, und das Konturieren wird von
  /// 102 auf 45 ms schneller, weil es weniger Kreuzungen gibt. Die
  /// Sprenkel sind die Ränder einzelner Konvektionsstreifen; benachbarte
  /// Zellen unterscheiden sich im Median nur um 0,8 mm, das Feld ist von
  /// sich aus glatt.
  ///
  /// **Warum das eine Ansichtssache bleibt und nicht in die Daten
  /// wandert:** Der Wert am Spot kommt aus [mmAt] auf dem UNGEGLÄTTETEN
  /// Gitter. Wer 43 mm liest, soll die 43 mm seiner Zelle bekommen und
  /// nicht den Mittelwert von neun Quadratkilometern — geglättet
  /// verschöbe sich das im 99. Perzentil um bis zu 14 mm.
  ///
  /// Zellen ohne Daten bleiben ohne Daten, und sie gehen nicht in den
  /// Mittelwert ein: Sonst zöge der Rand des Radarverbunds die Werte
  /// daneben nach unten und erzeugte eine Linie, die es nicht gibt.
  RainGrid smoothed() => RainGrid(
        // Die Rechnung steht in `contours.dart` — die Höhenlinien
        // brauchen sie mit anderem Wertebereich, und zwei Fassungen
        // eines 3×3-Mittels wären zwei Stellen, an denen der Rand der
        // Daten unterschiedlich behandelt wird. Die Werte hier sind
        // Bytes, deshalb der Rückweg nach Uint8List.
        values: Uint8List.fromList(smooth3x3(values,
            width: width, height: height, noData: rainNoData)),
        width: width,
        height: height,
        west: west,
        east: east,
        north: north,
        south: south,
        measured: measured,
      );
}

const _earthRadius = 6378137.0;

/// Web-Mercator: Breite in Meter. Gleiche Formel wie in
/// `tool/rain_grid.py`, damit beide Seiten dieselbe Zelle meinen.
double mercatorY(double lat) =>
    _earthRadius * math.log(math.tan(math.pi / 4 + lat * math.pi / 360));

/// Die Umkehrung dazu.
double latFromMercatorY(double y) =>
    (2 * math.atan(math.exp(y / _earthRadius)) - math.pi / 2) * 180 / math.pi;
