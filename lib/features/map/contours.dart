// Isolinien aus einem Wertegitter — Marching Squares plus
// Douglas-Peucker plus Chaikin, rein und ohne Flutter, damit
// `flutter test` sie deckt.
//
// **Warum das eine Maschine für zwei Ebenen ist:** Bis 1.96.0 stand
// diese Rechnung als `rain_contours.dart` nur dem Regen zur Verfügung,
// obwohl an ihr nichts regenhaft ist — ein Gitter, eine Schwelle, eine
// Linie. Für die Höhenlinien (#…, 1.98.0) wäre die zweite Kopie der
// teure Fehler gewesen: Marching Squares hat mit den Sattelpunkten und
// der Verkettung über Kantenkennungen genau zwei Stellen, an denen zwei
// Fassungen still auseinanderlaufen und niemand es merkt.
//
// **Warum Linien und nicht gefüllte Flächen** (entschieden am
// 2026-08-04, gemessen an Deutschland): Flächen brauchen 40–70 Tsd.
// Füllsegmente, Linien nach der Vereinfachung unter 10 Tsd. Punkte — in
// einer App mit ANR-Geschichte aus Renderer-Last (#142/#151) ist das der
// Unterschied, auf den es ankommt. Vor allem aber DECKEN LINIEN DIE
// KARTE NICHT ZU: Die Deckkraft der gefüllten DWD-Ebenen musste auf 0,4
// herunter, damit Wege und Beschriftung beim Hineinzoomen lesbar
// blieben. Mit Linien stellt sich die Frage nicht.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Eine Isolinie: alle Punkte liegen auf demselben Wert.
class ContourLine {
  const ContourLine({
    required this.level,
    required this.points,
    required this.cells,
  });

  /// Der Wert, auf dem diese Linie liegt — Millimeter beim Regen, Meter
  /// beim Gelände. Die Einheit kennt nur der Aufrufer.
  final int level;

  final List<LatLng> points;

  /// Wie viele Gitterzellen die Linie VOR der Vereinfachung lang war.
  /// Nach der Vereinfachung ist die Länge nicht mehr an der Punktzahl
  /// abzulesen (eine Gerade quer durch Deutschland hat zwei Punkte), und
  /// genau die braucht die Auswahl „welche Linie sagt bei diesem Zoom
  /// noch etwas".
  final int cells;
}

/// Erdumfang auf Breite 51°, in Kilometern.
///
/// Die Umrechnung Zoom → Kilometer nimmt diese Breite an: Die Daten sind
/// DACH, und über dessen Nord-Süd-Ausdehnung schwankt der Faktor um
/// weniger als ein Fünftel.
const germanyCircumferenceKm = 25220.0;

/// Wie viele Kilometer bei dieser Zoomstufe quer über den Schirm passen.
///
/// Der Faktor 4 ist die angenommene Schirmbreite in Kacheln — bewusst
/// eine Konstante und keine Messung am Gerät: Beide Ebenen, die das
/// benutzen, wählen damit nur ihre Stufenmenge, und die soll auf einem
/// Tablet dieselbe sein wie auf einem Telefon.
double kmAcrossAtZoom(double zoom) =>
    germanyCircumferenceKm / math.pow(2, zoom).toDouble() * 4;

/// Zieht die Isolinien durch ein Gitter.
///
/// [values] ist zeilenweise von Nord nach Süd, `width * height` Einträge;
/// [noData] markiert Zellen ohne Aussage. [latAtRow] und [lonAtColumn]
/// bekommen GLEITKOMMA-Gitterkoordinaten und liefern Grad — die
/// Zellmitte liegt dabei bei `index + 0,5`, und genau diese halbe Zelle
/// rechnet diese Funktion selbst dazu.
///
/// [toleranceCells] ist die Vereinfachung in Gitterzellen. Der
/// Vorgabewert 2 ist kein Schönheitswert, sondern eine
/// Ehrlichkeitsgrenze: Feiner als das Datengitter wissen wir es nicht,
/// eine Linie mit mehr Stützpunkten behauptet also Genauigkeit, die es
/// nicht gibt. Gemessen kostet die Vereinfachung 81 % der Punkte
/// (101 027 → 19 512).
///
/// [minChainCells] wirft Fragmente weg — beim Regen die Ränder einzelner
/// Konvektionsstreifen, die als Sprenkel über der Karte lägen. Gezählt
/// wird die Länge VOR der Vereinfachung, und das ist der ganze Punkt:
/// Danach hat eine schnurgerade Linie quer durch Deutschland zwei Punkte
/// und ein Zwei-Zellen-Fetzen auch. Eine Schranke auf das Ergebnis würde
/// die längste Linie mit dem kürzesten Fetzen verwechseln.
///
/// Die Kürzung ist eine Kürzung und steht deshalb im Rückgabewert von
/// [contourStats], nicht nur in diesem Kommentar.
List<ContourLine> contourLines({
  required List<int> values,
  required int width,
  required int height,
  required int noData,
  required List<int> levels,
  required double Function(double row) latAtRow,
  required double Function(double column) lonAtColumn,
  double toleranceCells = 2,
  int minChainCells = 6,
  int roundingPasses = 2,
}) {
  final lines = <ContourLine>[];
  for (final level in levels) {
    for (final chain
        in _chainsAt(values, width, height, noData, level)) {
      if (chain.length < minChainCells) continue;
      final simplified = _simplify(chain, toleranceCells);
      if (simplified.length < 2) continue;
      final rounded = _round(simplified, roundingPasses);
      lines.add(ContourLine(
        level: level,
        cells: chain.length,
        points: [
          for (final point in rounded)
            LatLng(latAtRow(point.dy + 0.5), lonAtColumn(point.dx + 0.5)),
        ],
      ));
    }
  }
  return lines;
}

/// Was beim Ziehen weggefallen ist — für die Run-Summary und für Tests,
/// die belegen wollen, dass nicht still gekürzt wird.
({int lines, int points, int dropped, int rawPoints}) contourStats({
  required List<int> values,
  required int width,
  required int height,
  required int noData,
  required List<int> levels,
  double toleranceCells = 2,
  int minChainCells = 6,
}) {
  var lines = 0, points = 0, dropped = 0, rawPoints = 0;
  for (final level in levels) {
    for (final chain
        in _chainsAt(values, width, height, noData, level)) {
      rawPoints += chain.length;
      if (chain.length < minChainCells) {
        dropped++;
        continue;
      }
      final simplified = _simplify(chain, toleranceCells);
      if (simplified.length < 2) {
        dropped++;
        continue;
      }
      lines++;
      points += simplified.length;
    }
  }
  return (lines: lines, points: points, dropped: dropped, rawPoints: rawPoints);
}

/// Marching Squares auf einer Höhe, verkettet zu Linienzügen.
///
/// Verkettet wird über **Kantenkennungen, nicht über Koordinaten**: Zwei
/// benachbarte Zellen berechnen den Schnittpunkt auf ihrer gemeinsamen
/// Kante aus denselben zwei Werten, aber in umgekehrter Richtung. Das ist
/// algebraisch dasselbe Ergebnis und in Fließkomma nicht zwingend
/// dieselbe Zahl. Eine Verkettung über Koordinatengleichheit würde daran
/// gelegentlich zerfallen — sichtbar als zerhackte Linien, unauffällig
/// genug, um lange unbemerkt zu bleiben.
List<List<_Point>> _chainsAt(
    List<int> values, int width, int height, int noData, int level) {
  final stride = width + 1;

  // Kantenkennung: gerade = waagerechte Kante links von (x,y),
  // ungerade = senkrechte Kante oberhalb von (x,y).
  int horizontal(int x, int y) => 2 * (x + stride * y);
  int vertical(int x, int y) => 2 * (x + stride * y) + 1;

  final neighbours = <int, List<int>>{};
  void connect(int a, int b) {
    (neighbours[a] ??= <int>[]).add(b);
    (neighbours[b] ??= <int>[]).add(a);
  }

  for (var y = 0; y < height - 1; y++) {
    final row = y * width;
    final next = row + width;
    for (var x = 0; x < width - 1; x++) {
      final ul = values[row + x];
      final ur = values[row + x + 1];
      final lr = values[next + x + 1];
      final ll = values[next + x];
      // Eine Zelle mit einer unbekannten Ecke wird übersprungen, nicht
      // geraten. Am Rand der Daten hören die Linien deshalb auf.
      if (ul == noData || ur == noData || lr == noData || ll == noData) {
        continue;
      }
      var index = 0;
      if (ul >= level) index |= 1;
      if (ur >= level) index |= 2;
      if (lr >= level) index |= 4;
      if (ll >= level) index |= 8;
      if (index == 0 || index == 15) continue;

      final top = horizontal(x, y);
      final right = vertical(x + 1, y);
      final bottom = horizontal(x, y + 1);
      final left = vertical(x, y);
      switch (index) {
        case 1:
        case 14:
          connect(left, top);
        case 2:
        case 13:
          connect(top, right);
        case 3:
        case 12:
          connect(left, right);
        case 4:
        case 11:
          connect(right, bottom);
        case 6:
        case 9:
          connect(top, bottom);
        case 7:
        case 8:
          connect(left, bottom);
        // Sattelpunkte: Die Zelle allein sagt nicht, welche der beiden
        // Ecken zusammengehören. Immer dieselbe Auflösung wählen — eine
        // wechselnde erzeugt an jedem Sattel eine andere Linie und macht
        // Tests unreproduzierbar.
        case 5:
          connect(left, top);
          connect(right, bottom);
        case 10:
          connect(top, right);
          connect(bottom, left);
      }
    }
  }

  // Wert an einer Kante zu Gitterkoordinaten interpolieren. Genau
  // einmal je Kante, damit beide anliegenden Zellen denselben Punkt
  // bekommen.
  _Point pointAt(int key) {
    final isVertical = key.isOdd;
    final cell = key >> 1;
    final x = cell % stride;
    final y = cell ~/ stride;
    if (isVertical) {
      final a = values[y * width + x];
      final b = values[(y + 1) * width + x];
      return _Point(x.toDouble(), y + _fraction(a, b, level));
    }
    final a = values[y * width + x];
    final b = values[y * width + x + 1];
    return _Point(x + _fraction(a, b, level), y.toDouble());
  }

  final used = <int>{};
  final chains = <List<_Point>>[];

  List<_Point> walk(int start, int first) {
    final keys = <int>[start, first];
    used.add(_edge(start, first));
    var current = first;
    var previous = start;
    while (true) {
      final options = neighbours[current];
      if (options == null) break;
      int? step;
      for (final candidate in options) {
        if (candidate == previous && options.length > 1) continue;
        if (used.contains(_edge(current, candidate))) continue;
        step = candidate;
        break;
      }
      if (step == null) break;
      used.add(_edge(current, step));
      keys.add(step);
      previous = current;
      current = step;
    }
    return [for (final key in keys) pointAt(key)];
  }

  // Erst von den Enden her laufen, dann erst die Ringe. Andersherum
  // zerfiele jeder offene Zug, der mitten in der Abtastreihenfolge
  // beginnt, in zwei Stücke — nicht falsch, aber doppelt so viele
  // Linien und eine schlechtere Vereinfachung.
  for (final entry in neighbours.entries) {
    if (entry.value.length != 1) continue;
    if (used.contains(_edge(entry.key, entry.value.first))) continue;
    chains.add(walk(entry.key, entry.value.first));
  }
  for (final entry in neighbours.entries) {
    for (final other in entry.value) {
      if (used.contains(_edge(entry.key, other))) continue;
      chains.add(walk(entry.key, other));
    }
  }
  return chains;
}

/// Ein ungerichteter Kantenschlüssel. `2^21` reicht für jedes Gitter, das
/// hier vorkommt (Deutschland-Regen: 713×891 ⇒ Kennungen unter 1,3 Mio.;
/// das Höhenfenster ist auf 512×512 gedeckelt), und das Produkt bleibt
/// unter 2^53 — also auch im Web exakt, wo `int` ein `double` ist.
int _edge(int a, int b) => a < b ? a * 2097152 + b : b * 2097152 + a;

double _fraction(int a, int b, int level) {
  if (a == b) return 0.5;
  final t = (level - a) / (b - a);
  return t.clamp(0.0, 1.0);
}

/// Douglas-Peucker, iterativ (ein Linienzug quer durch Deutschland hat
/// vierstellig viele Punkte — rekursiv wäre das ein Stapelrisiko auf
/// einem Gerät, das ohnehin schon einmal an Speicher gestorben ist).
List<_Point> _simplify(List<_Point> points, double tolerance) {
  if (points.length < 3 || tolerance <= 0) return points;
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  final stack = <List<int>>[
    [0, points.length - 1]
  ];
  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final from = range[0];
    final to = range[1];
    if (to <= from + 1) continue;
    final ax = points[from].dx;
    final ay = points[from].dy;
    final bx = points[to].dx;
    final by = points[to].dy;
    final dx = bx - ax;
    final dy = by - ay;
    final length = math.sqrt(dx * dx + dy * dy);
    var worst = -1.0;
    var worstAt = from;
    for (var i = from + 1; i < to; i++) {
      final px = points[i].dx;
      final py = points[i].dy;
      final distance = length > 0
          ? (dy * px - dx * py + bx * ay - by * ax).abs() / length
          : math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
      if (distance > worst) {
        worst = distance;
        worstAt = i;
      }
    }
    if (worst > tolerance) {
      keep[worstAt] = true;
      stack.add([from, worstAt]);
      stack.add([worstAt, to]);
    }
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

/// Rundet die Ecken, die die Vereinfachung hinterlässt — Chaikin.
///
/// **Warum überhaupt:** Douglas-Peucker macht aus vierzig Punkten zwei
/// und hinterlässt Polygonzüge mit sichtbaren Knicken. Die sehen nach
/// Konstruktion aus, nicht nach Höhenlinie (Befund des Betreibers,
/// 2026-08-04, an gerenderten Ausschnitten verglichen).
///
/// **Und warum das ehrlich bleibt:** Chaikin schneidet Ecken ab, es
/// erfindet keine neuen Züge — jeder erzeugte Punkt liegt auf der
/// Verbindung zweier vorhandener. Die Kurve bleibt innerhalb der
/// konvexen Hülle des Polygonzugs und weicht nie weiter ab als dessen
/// eigene Vereinfachungstoleranz. Sie ist damit glatter als das Gitter,
/// aber nicht falscher als die Vereinfachung, die ohnehin davor liegt.
/// Bei der Rasterdarstellung ist das anders entschieden
/// (`raster-resampling: nearest`): Dort tut Weichzeichnen so, als
/// stünden zwischen den Zellen Messwerte. Eine Isolinie ist von Haus aus
/// eine Interpolation, ein Klötzchen nicht.
///
/// Zwei Durchgänge vervierfachen die Punktzahl (an echten Daten
/// 10 238 → 40 952). Das ist Renderlast, keine Übertragung: Geglättet
/// wird, was auf dem Gerät entsteht.
List<_Point> _round(List<_Point> points, int passes) {
  var current = points;
  for (var pass = 0; pass < passes; pass++) {
    if (current.length < 3) break;
    final next = <_Point>[current.first];
    for (var i = 0; i < current.length - 1; i++) {
      final a = current[i];
      final b = current[i + 1];
      next.add(_Point(a.dx * 0.75 + b.dx * 0.25, a.dy * 0.75 + b.dy * 0.25));
      next.add(_Point(a.dx * 0.25 + b.dx * 0.75, a.dy * 0.25 + b.dy * 0.75));
    }
    next.add(current.last);
    current = next;
  }
  return current;
}

/// Ein Punkt in Gitterkoordinaten (Spalte, Zeile) — bewusst nicht
/// `Offset`, damit diese Datei ohne Flutter auskommt.
class _Point {
  const _Point(this.dx, this.dy);
  final double dx;
  final double dy;
}
