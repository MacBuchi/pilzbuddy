// Das Waldtypen-Gitter: ein Byte je 250-m-Zelle, wie es
// `tool/forest_grid.py` aus dem Copernicus-HRL „Dominant Leaf Type" baut
// (#213). Liegt als Asset im APK — die Frage „in welchen Wald fahre ich"
// stellt sich gern dort, wo kein Empfang ist.
//
// Reines Dart ohne Flutter, wie `rain_grid.dart` und aus demselben Grund:
// Ein falsch ausgepacktes Gitter fällt sonst erst als merkwürdige Fläche
// auf dem Gerät auf.
//
// **Bewusst eine EIGENE Klasse und kein verbogenes [RainGrid]:** Das
// Regen-Gitter liegt in Mercator-Zeilen (EPSG:3857-Quelle), dieses hier
// kommt in EPSG:4326 und ist damit **linear in Breite UND Länge**. Eine
// Klasse mit zwei Zeilen-Geometrien wäre genau die Falle, vor der
// `rain_stack.dart` warnt: zwei Wege zur Zelle, die auseinanderlaufen
// können.
//
// **Warum Anteile statt fertiger Klassen im Byte:** Die Schwellen, ab
// wann „Misch" zu „Nadel" wird, sind eine Darstellungsfrage — als Werte
// verschifft lassen sie sich in Dart nachstellen, ohne dass CI neu
// rechnet. Dieselbe Begründung, mit der das Regen-Gitter Werte statt
// Konturlinien transportiert.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// „Hier wissen wir nichts" — außerhalb der Abdeckung der Quelle.
const forestNoData = 255;

/// Zelle unter der Wald-Schwelle des Werkzeugs (Baumanteil zu klein).
/// 0 heißt „kein Wald", nicht „keine Daten" — der Unterschied entscheidet,
/// ob die Fläche transparent bleibt oder die Ebene sich gar nicht äußert.
const forestNoForest = 0;

/// Was an einem Punkt steht — die Klassen, die das Blatt und die
/// Spot-Zeile benennen.
enum ForestClass { none, broadleaf, mixed, conifer }

/// Ab diesem Nadelanteil gilt eine Zelle als Nadelwald, darunter bis
/// [broadleafBelow] als Mischwald. Die Schwellen sind Darstellung, nicht
/// Daten — deshalb hier und nicht im Werkzeug.
const coniferAbove = 75;
const broadleafBelow = 25;

/// Ein ausgepacktes Waldgitter samt Ausdehnung.
class ForestGrid {
  const ForestGrid({
    required this.values,
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.referenceYear,
  });

  /// `width * height` Bytes, zeilenweise von Nord nach Süd.
  /// Je Byte: 0 = kein Wald, 1..101 = Wert−1 ist der Nadelanteil in
  /// Prozent, 255 = keine Daten.
  final Uint8List values;
  final int width;
  final int height;

  /// Die AUSSENKANTEN in Grad — nicht Zellmittelpunkte.
  final double west;
  final double east;
  final double north;
  final double south;

  /// Das Referenzjahr der Quelle. Wald ändert sich langsam, aber die
  /// Borkenkäfer-Jahre haben gezeigt: Das Jahr gehört dem Benutzer
  /// gesagt.
  final int referenceYear;

  /// Packt aus, was `tool/forest_grid.py` geschrieben hat: gzip,
  /// darunter ein Zeilen-Delta. Das Delta wird JE ZEILE zurückgesetzt —
  /// dieselbe Kodierung wie beim Regen, derselbe Test-Fallstrick.
  factory ForestGrid.decode(
    List<int> gzipped, {
    required int width,
    required int height,
    required double west,
    required double east,
    required double north,
    required double south,
    required int referenceYear,
  }) {
    final flat = GZipDecoder().decodeBytes(gzipped);
    if (flat.length != width * height) {
      throw FormatException(
          'Waldgitter hat ${flat.length} Bytes, erwartet ${width * height}');
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
    return ForestGrid(
      values: values,
      width: width,
      height: height,
      west: west,
      east: east,
      north: north,
      south: south,
      referenceYear: referenceYear,
    );
  }

  /// Der Nadelanteil (0–100) am Punkt — `null` außerhalb des Gitters,
  /// ohne Daten oder wo kein Wald steht.
  ///
  /// **Linear in der Breite**, anders als [RainGrid.mmAt]: Diese Quelle
  /// ist EPSG:4326, ihre Zeilen sind Grad-gleichmäßig. Wer hier die
  /// Mercator-Rechnung des Regens abschreibt, liegt am Südrand um
  /// Kilometer daneben — `test/forest_grid_test.dart` hält die beiden
  /// Rechnungen ausdrücklich auseinander.
  int? shareAt(double lat, double lon) {
    if (lon < west || lon > east || lat > north || lat < south) return null;
    final x = ((lon - west) / (east - west) * width).floor();
    final y = ((north - lat) / (north - south) * height).floor();
    if (x < 0 || x >= width || y < 0 || y >= height) return null;
    final value = values[y * width + x];
    if (value == forestNoData || value == forestNoForest) return null;
    return value - 1;
  }

  /// Die Klasse am Punkt — `null` außerhalb oder ohne Daten.
  /// [ForestClass.none] heißt ausdrücklich „hier steht kein Wald";
  /// das ist eine Aussage, kein Fehlen.
  ForestClass? classAt(double lat, double lon) {
    if (lon < west || lon > east || lat > north || lat < south) return null;
    final x = ((lon - west) / (east - west) * width).floor();
    final y = ((north - lat) / (north - south) * height).floor();
    if (x < 0 || x >= width || y < 0 || y >= height) return null;
    final value = values[y * width + x];
    if (value == forestNoData) return null;
    return classOfByte(value);
  }

  /// Der Wert einer Zelle als Klasse — für Zeichner, die über das Gitter
  /// laufen. Ohne Bereichsprüfung, wie [RainGrid.at].
  ForestClass classAtCell(int x, int y) => classOfByte(values[y * width + x]);

  /// Rohwert einer Zelle, für Tests und Werkzeuge.
  int byteAt(int x, int y) => values[y * width + x];

  /// Der Laubfaktor des Waldes im Umkreis (#235): 1 = reiner Laub-,
  /// 0 = reiner Nadelwald. Je Waldzelle zählt ihr ECHTER Nadelanteil —
  /// eine 60/40-Zelle geht mit 0,4 ein statt pauschal als „Misch 0,5";
  /// die Idee des Betreibers (Misch = 50/50) ist damit der Spezialfall.
  ///
  /// [forestShare] ist der Waldanteil an der Umkreisfläche — getrennt
  /// vom Faktor, damit Zusammensetzung und Bedeckung nicht in einer
  /// Zahl verschwimmen (Entscheidung 2026-08-08). `factor` ist `null`,
  /// wenn im Umkreis kein Wald steht; Rückgabe insgesamt `null`, wenn
  /// dort gar keine Daten liegen (außerhalb DACH, Gitterrand).
  ///
  /// Gezählt wird jede Zelle, deren FLÄCHE den Kreis schneidet — nicht
  /// nur die, deren Mittelpunkt hineinfällt: Bei 250-m-Zellen und
  /// 200 m Radius wäre das sonst oft eine einzige Zelle, und der
  /// „Umkreis" stünde nur auf dem Papier. Gerechnet lokal flach in
  /// Metern; auf 200 m ist die Erdkrümmung kein Argument.
  ({double? factor, double forestShare})? broadleafFactorAround(
      double lat, double lon,
      {double radiusMeters = crosshairRadiusMeters}) {
    const metersPerDegree = 111320.0;
    final cellHeightMeters = (north - south) / height * metersPerDegree;
    final cellWidthMeters = (east - west) /
        width *
        metersPerDegree *
        math.cos(lat * math.pi / 180);
    if (cellHeightMeters <= 0 || cellWidthMeters <= 0) return null;

    final centerX = (lon - west) / (east - west) * width;
    final centerY = (north - lat) / (north - south) * height;
    final spanX = (radiusMeters / cellWidthMeters).ceil() + 1;
    final spanY = (radiusMeters / cellHeightMeters).ceil() + 1;

    var counted = 0;
    var forest = 0;
    var broadleafSum = 0.0;
    for (var y = (centerY - spanY).floor();
        y <= (centerY + spanY).floor();
        y++) {
      if (y < 0 || y >= height) continue;
      for (var x = (centerX - spanX).floor();
          x <= (centerX + spanX).floor();
          x++) {
        if (x < 0 || x >= width) continue;
        // Abstand Punkt ↔ Zellrechteck in Metern; 0 heißt „Punkt liegt
        // in der Zelle". Schneidet das Rechteck den Kreis nicht, ist
        // die Zelle draußen.
        final dx = math.max(0.0, ((centerX - (x + 0.5)).abs() - 0.5)) *
            cellWidthMeters;
        final dy = math.max(0.0, ((centerY - (y + 0.5)).abs() - 0.5)) *
            cellHeightMeters;
        if (dx * dx + dy * dy > radiusMeters * radiusMeters) continue;
        final value = values[y * width + x];
        if (value == forestNoData) continue;
        counted++;
        if (value == forestNoForest) continue;
        forest++;
        broadleafSum += 1 - (value - 1) / 100;
      }
    }
    if (counted == 0) return null;
    return (
      factor: forest == 0 ? null : broadleafSum / forest,
      forestShare: forest / counted,
    );
  }
}

/// Der Umkreis der Fadenkreuz-Werte (#235). Fest statt einstellbar —
/// ein Regler kommt erst, wenn das Feld zeigt, dass 200 m nicht passen.
const crosshairRadiusMeters = 200.0;

/// Byte → Klasse, die EINE Stelle für die Schwellen.
ForestClass classOfByte(int value) {
  if (value == forestNoForest || value == forestNoData) {
    return ForestClass.none;
  }
  final share = value - 1;
  if (share > coniferAbove) return ForestClass.conifer;
  if (share < broadleafBelow) return ForestClass.broadleaf;
  return ForestClass.mixed;
}
