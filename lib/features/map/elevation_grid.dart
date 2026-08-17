// Das Höhengitter: mittlere Geländehöhe je Wabe, wie es
// `tool/elevation_grid.py` aus dem Copernicus DEM GLO-90 baut. Ein Byte
// je Zelle in 20-m-Stufen, 0xFF heißt „keine Aussage" (nur Randzellen
// über dem Ostrand des Rasters).
//
// Zweck: die Temperaturkorrektur von Spot-Blatt und Pilzampel. Die
// nächste Wetterstation kann Hunderte Höhenmeter neben dem Spot liegen
// (#279, die Zugspitze als Referenz ihrer Täler); mit der Spothöhe wird
// die Stationstemperatur um 0,65 K je 100 m Differenz umgerechnet. Die
// Validierung hat immer schon Temperaturen AUF Spothöhe gesehen
// (Open-Meteo rechnet über ein 90-m-DEM herunter) — die Korrektur führt
// die App also zum validierten Aufbau hin.
//
// Reines Dart ohne Flutter, wie `forest_grid.dart` und aus demselben
// Grund. **Dasselbe Hex-Gitter wie [ForestGrid]** — die Zuordnung
// Punkt → Zelle ruft `hexNearestCell`, keine zweite Geometrie.
//
// Die Kodierung steht im Manifest: Zeilen-Delta + gzip wie beim Regen
// (Höhen sind glatt), aber der Bau MISST beide Wege und erklärt den
// gewählten — dieser Leser kann beide und lehnt alles andere ab.
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'forest_grid.dart' show hexNearestCell;

/// „Hier wissen wir nichts" — kommt nur in Randzellen vor.
const elevationNoData = 0xFF;

/// Meter je Byte-Stufe — muss zum Werkzeug passen (`QUANT_M`).
const elevationQuantM = 20;

/// 0,65 K je 100 m: die Standard-Lapse-Rate, mit der auch Open-Meteo
/// (und damit die Validierung) Temperaturen auf Zielhöhe bringt.
const lapseKPer100m = 0.65;

class ElevationGrid {
  const ElevationGrid({
    required this.values,
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.hexLonStep,
    required this.hexLatStep,
  });

  /// `width * height` Bytes, zeilenweise von Nord nach Süd.
  final Uint8List values;
  final int width;
  final int height;

  /// Die AUSSENKANTEN in Grad — nicht Zellmittelpunkte.
  final double west;
  final double east;
  final double north;
  final double south;

  /// Hexbreite in Grad Länge und Zeilenschritt in Grad Breite —
  /// identisch mit denen des Waldgitters.
  final double hexLonStep;
  final double hexLatStep;

  /// Packt aus, was `tool/elevation_grid.py` geschrieben hat.
  ///
  /// [encoding] kommt aus dem Manifest: `gzip+row-delta` oder `gzip`.
  /// Alles andere ist ein Formatfehler — ablehnen statt still falsch
  /// auspacken (die Lehre aus dem Baumarten-Leser).
  factory ElevationGrid.decode(
    List<int> gzipped, {
    required String encoding,
    required int width,
    required int height,
    required double west,
    required double east,
    required double north,
    required double south,
    required double hexLonStep,
    required double hexLatStep,
  }) {
    if (encoding != 'gzip' && encoding != 'gzip+row-delta') {
      throw FormatException('Höhengitter mit fremder Kodierung: $encoding');
    }
    final flat = GZipDecoder().decodeBytes(gzipped);
    if (flat.length != width * height) {
      throw FormatException(
          'Höhengitter hat ${flat.length} Bytes, erwartet ${width * height}');
    }
    final values = Uint8List.fromList(flat);
    if (encoding == 'gzip+row-delta') {
      // Das Delta wird JE ZEILE zurückgesetzt — dieselbe Kodierung wie
      // bei Wald und Regen, derselbe Test-Fallstrick.
      for (var y = 0; y < height; y++) {
        final row = y * width;
        var previous = 0;
        for (var x = 0; x < width; x++) {
          previous = (previous + values[row + x]) & 0xFF;
          values[row + x] = previous;
        }
      }
    }
    return ElevationGrid(
      values: values,
      width: width,
      height: height,
      west: west,
      east: east,
      north: north,
      south: south,
      hexLonStep: hexLonStep,
      hexLatStep: hexLatStep,
    );
  }

  /// Die mittlere Geländehöhe der Wabe an einem Punkt in Metern —
  /// `null` außerhalb des Gitters oder in einer Randzelle ohne Daten.
  int? heightMetersAt(double lat, double lon) {
    if (lat > north || lat < south || lon < west || lon > east) return null;
    final cell = hexNearestCell(
      u: (lon - west) / hexLonStep,
      v: (north - lat) / hexLatStep,
      width: width,
      height: height,
    );
    if (cell == null) return null;
    final byte = values[cell.$2 * width + cell.$1];
    if (byte == elevationNoData) return null;
    return byte * elevationQuantM;
  }
}

/// Die Gradzahl, um die eine Stationstemperatur auf die Zielhöhe
/// gebracht wird: positiv, wenn die Station HÖHER liegt als das Ziel
/// (im Tal ist es wärmer als auf der Zugspitze).
///
/// Eine Funktion statt dreier Inline-Rechnungen: Blatt-Ablesung,
/// Kartenfläche und Tests müssen exakt dieselbe Zahl sehen — das ist
/// die #279-Regel („Fläche und Blatt sagen dasselbe") für die Höhe.
double lapseCorrectionK(
        {required int stationHeightM, required int targetHeightM}) =>
    (stationHeightM - targetHeightM) * lapseKPer100m / 100.0;
