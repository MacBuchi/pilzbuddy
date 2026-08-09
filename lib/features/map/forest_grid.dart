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
///
/// Seit #251 wahlweise als HEX-Gitter (Spitze oben, odd-r): Das Manifest
/// trägt dann `lattice: "hex-odd-r"` samt [hexLonStep] (Hexbreite in
/// Grad Länge) und [hexLatStep] (Zeilenschritt in Grad Breite). Der
/// Mittelpunkt von Hex (hx, hy):
///   lon = west + hexLonStep · (hx + 0,5 + 0,5·(hy ungerade))
///   lat = north − hexLatStep · (hy + 2/3)
/// (2/3, weil der Umkreisradius R = Zeilenschritt/1,5 ist.) Die Bytes
/// bleiben dieselben; nur die Zuordnung Punkt → Zelle ändert sich.
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
    this.hexLonStep,
    this.hexLatStep,
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

  /// Hex-Geometrie (#251) — beide `null` beim Quadratgitter.
  final double? hexLonStep;
  final double? hexLatStep;

  bool get isHex => hexLonStep != null && hexLatStep != null;

  /// Das Hex unter einem Punkt: der NÄCHSTE Mittelpunkt, gemessen im
  /// Raum, in dem die Hexe regelmäßig sind (Breite w, Zeilenschritt
  /// 1,5·R — Verhältnis w : 1,5R = √3 : 1,5). Kandidaten sind die
  /// Nachbarzeilen und -spalten der groben Schätzung, wie `hex_at` im
  /// Werkzeug — die App MUSS dieselbe Zuordnung treffen wie der Bau,
  /// sonst nennt „Wald hier" ein anderes Hex, als die Karte einfärbt.
  (int, int)? hexCellAt(double lat, double lon) {
    final lonStep = hexLonStep;
    final latStep = hexLatStep;
    if (lonStep == null || latStep == null) return null;
    if (lon < west || lon > east || lat > north || lat < south) return null;
    // In Hex-Einheiten: u in Breiten (Spalten), v in Zeilenschritten.
    final u = (lon - west) / lonStep;
    final v = (north - lat) / latStep;
    // Rückverhältnis der Achsen im regelmäßigen Raum: eine Breite w
    // entspricht √3·R, ein Zeilenschritt 1,5·R.
    const uScale = 1.7320508075688772; // √3
    const vScale = 1.5;
    (int, int)? best;
    double? bestD;
    final hy0 = (v - 2 / 3).round();
    for (var hy = hy0 - 1; hy <= hy0 + 1; hy++) {
      if (hy < 0 || hy >= height) continue;
      final odd = hy.isOdd ? 0.5 : 0.0;
      final hx0 = (u - 0.5 - odd).round();
      for (var hx = hx0 - 1; hx <= hx0 + 1; hx++) {
        if (hx < 0 || hx >= width) continue;
        final du = (u - (hx + 0.5 + odd)) * uScale;
        final dv = (v - (hy + 2 / 3)) * vScale;
        final d = du * du + dv * dv;
        if (bestD == null || d < bestD) {
          bestD = d;
          best = (hx, hy);
        }
      }
    }
    return best;
  }

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
    double? hexLonStep,
    double? hexLatStep,
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
      hexLonStep: hexLonStep,
      hexLatStep: hexLatStep,
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
    final value = _byteAtPoint(lat, lon);
    if (value == null || value == forestNoData || value == forestNoForest) {
      return null;
    }
    return value - 1;
  }

  /// Der Rohwert unter einem Punkt — Quadrat- oder Hex-Zuordnung, je
  /// nach Gitter. Die EINE Stelle, durch die alle Punktabfragen gehen.
  int? _byteAtPoint(double lat, double lon) {
    if (isHex) {
      final cell = hexCellAt(lat, lon);
      if (cell == null) return null;
      return values[cell.$2 * width + cell.$1];
    }
    if (lon < west || lon > east || lat > north || lat < south) return null;
    final x = ((lon - west) / (east - west) * width).floor();
    final y = ((north - lat) / (north - south) * height).floor();
    if (x < 0 || x >= width || y < 0 || y >= height) return null;
    return values[y * width + x];
  }

  /// Die Klasse am Punkt — `null` außerhalb oder ohne Daten.
  /// [ForestClass.none] heißt ausdrücklich „hier steht kein Wald";
  /// das ist eine Aussage, kein Fehlen.
  ForestClass? classAt(double lat, double lon) {
    final value = _byteAtPoint(lat, lon);
    if (value == null || value == forestNoData) return null;
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
  /// nur die, deren Mittelpunkt hineinfällt: Bei 250-m-Zellen und einem
  /// kleinen Radius wäre das sonst eine einzige Zelle, und der „Umkreis"
  /// stünde nur auf dem Papier. Gerechnet lokal flach in Metern; auf dem
  /// Kilometer, um den es geht, ist die Erdkrümmung kein Argument.
  ({double? factor, double forestShare})? broadleafFactorAround(
      double lat, double lon,
      {double radiusMeters = crosshairRadiusMeters}) {
    if (isHex) {
      return _broadleafFactorAroundHex(lat, lon, radiusMeters);
    }
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

/// Hex-Fassung des Umkreises (#251): gezählt wird jedes Hex, dessen
/// Mittelpunkt näher als Radius + Umkreisradius liegt — eine leichte
/// Übernäherung an den Ecken statt exakter Sechseck-Kreis-Schnitt; sie
/// ist monoton, symmetrisch und bei ~70 Hexen im Kilometer belanglos.
extension on ForestGrid {
  ({double? factor, double forestShare})? _broadleafFactorAroundHex(
      double lat, double lon, double radiusMeters) {
    final lonStep = hexLonStep!;
    final latStep = hexLatStep!;
    const metersPerDegree = 111320.0;
    final rowMeters = latStep * metersPerDegree;
    final colMeters =
        lonStep * metersPerDegree * math.cos(lat * math.pi / 180);
    if (rowMeters <= 0 || colMeters <= 0) return null;
    // Umkreisradius R in Metern: Zeilenschritt = 1,5·R.
    final hexR = rowMeters / 1.5;
    final reach = radiusMeters + hexR;

    final u = (lon - west) / lonStep;
    final v = (north - lat) / latStep;
    final spanRows = (reach / rowMeters).ceil() + 1;
    final spanCols = (reach / colMeters).ceil() + 1;
    var counted = 0;
    var forest = 0;
    var broadleafSum = 0.0;
    for (var hy = (v - spanRows).floor(); hy <= (v + spanRows).ceil(); hy++) {
      if (hy < 0 || hy >= height) continue;
      final odd = hy.isOdd ? 0.5 : 0.0;
      for (var hx = (u - spanCols).floor();
          hx <= (u + spanCols).ceil();
          hx++) {
        if (hx < 0 || hx >= width) continue;
        final dx = (u - (hx + 0.5 + odd)) * colMeters;
        final dy = (v - (hy + 2 / 3)) * rowMeters;
        if (dx * dx + dy * dy > reach * reach) continue;
        final value = values[hy * width + hx];
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
/// ein Regler kommt erst, wenn das Feld zeigt, dass dieser Wert nicht
/// passt.
///
/// **1 km, seit 1.67.0 — die ersten 200 m waren zu klein für dieses
/// Gitter.** Eine Zelle ist ~250 m breit (nachgemessen am echten Asset:
/// 225 m bei 55°N, 272 m bei 46°N, 251 m hoch überall), der Radius war
/// also KLEINER als die Zelle, auf der er stand. Gezählt wurden dadurch
/// vier bis sechs Zellen — ein „Umkreis", der zu drei Vierteln aus der
/// eigenen Zelle und einer Handvoll Nachbarn bestand und beim Schieben
/// der Karte sprang. Gemessen am selben Punkt im Spessart: 0,72 auf
/// 200 m, 0,43 auf 1 km; der Waldanteil an der Kartenmitte fiel von
/// „50 %" (2 von 4 Zellen) auf ehrliche 16 %.
///
/// 1 km fasst 64–72 Zellen (~4 km²) und ist damit groß gegen die Zelle,
/// statt von ihr beherrscht zu werden. Das ist auch die Größenordnung,
/// in der sich ein Sammler bewegt, wenn er „hier ist Laubwald" sagt.
const crosshairRadiusMeters = 1000.0;

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
