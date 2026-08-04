// Höhenlinien aus dem Regen-Wertegitter — Marching Squares plus
// Douglas-Peucker, rein und ohne Flutter, damit `flutter test` sie deckt.
//
// **Warum Linien und nicht gefüllte Flächen** (entschieden am 2026-08-04,
// gemessen an Deutschland): Flächen brauchen 40–70 Tsd. Füllsegmente,
// Linien nach der Vereinfachung unter 10 Tsd. Punkte — in einer App mit
// ANR-Geschichte aus Renderer-Last (#142/#151) ist das der Unterschied,
// auf den es ankommt. Vor allem aber DECKEN LINIEN DIE KARTE NICHT ZU:
// Die Deckkraft der gefüllten DWD-Ebenen musste auf 0,4 herunter, damit
// Wege und Beschriftung beim Hineinzoomen lesbar blieben. Mit Linien
// stellt sich die Frage nicht.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'rain_grid.dart';

/// Eine Höhenlinie: alle Punkte liegen auf derselben Niederschlagsmenge.
class ContourLine {
  const ContourLine({
    required this.mm,
    required this.points,
    required this.cells,
  });

  /// Die Niederschlagsmenge, auf der diese Linie liegt.
  final int mm;

  final List<LatLng> points;

  /// Wie viele Gitterzellen die Linie VOR der Vereinfachung lang war —
  /// eine Zelle ist ungefähr ein Kilometer. Nach der Vereinfachung ist
  /// die Länge nicht mehr an der Punktzahl abzulesen (eine Gerade quer
  /// durch Deutschland hat zwei Punkte), und genau die braucht
  /// [rainContoursAtZoom].
  final int cells;
}

/// Die Linien, die bei dieser Zoomstufe überhaupt etwas aussagen.
///
/// **Warum es das braucht** (am Pixel 7 gesehen, 2026-08-04): In der
/// Deutschlandübersicht zeichnen alle Linien zusammen ein Geflecht statt
/// Höhenlinien — nicht weil es zu viele Stufen sind, sondern weil
/// hunderte kurze Ringe je wenige Pixel groß sind. Eingezoomt, wo die
/// Fläche versagt hat, sind dieselben Daten sparsam und klar.
///
/// Die Regel ist deshalb keine Zoomstufen-Tabelle, sondern ein Satz:
/// **Eine Linie, die auf dem Schirm kürzer als [minPixels] ist, sagt
/// nichts.** Das ist dieselbe Größe bei jedem Maßstab und braucht keine
/// Schwellenwerte, die jemand später raten muss.
///
/// Die Umrechnung nimmt Breite 51° an — die Daten sind Deutschland, und
/// über dessen Nord-Süd-Ausdehnung schwankt der Faktor um weniger als
/// ein Fünftel.
List<ContourLine> rainContoursAtZoom(
  List<ContourLine> lines,
  double zoom, {
  required List<int> levels,
  double minPixels = 40,
}) {
  final pixelsPerKm = 256 * math.pow(2, zoom) / _germanyCircumferenceKm;
  final minCells = minPixels / pixelsPerKm;
  final shown = rainLevelsAtZoom(levels, zoom).toSet();
  return [
    for (final line in lines)
      if (line.cells >= minCells && shown.contains(line.mm)) line,
  ];
}

/// Welche Höhenstufen bei dieser Zoomstufe gezeichnet werden.
///
/// **Der zweite Befund vom Pixel 7:** Die kurzen Ringe wegzulassen reicht
/// nicht. In der Übersicht ist die Dichte kein Rauschen, sondern echte
/// Struktur — acht Stufen über einem Feld, das zwischen 8 und 112 mm
/// liegt, laufen dort streckenweise parallel und zeichnen ein Geflecht.
///
/// Das ist derselbe Fall, den jede topografische Karte kennt, und die
/// Antwort ist dieselbe: **Die Äquidistanz wächst mit dem Maßstab.** Aus
/// der Ferne jede vierte Linie, dann jede zweite, aus der Nähe alle. Der
/// Schwellenwert ist bewusst an die Bildschirmbreite gekoppelt und nicht
/// an geratene Zoomstufen: Unter ~150 km Breite sind alle Stufen
/// lesbar, über ~600 km nur noch jede vierte.
List<int> rainLevelsAtZoom(List<int> levels, double zoom) {
  final kmAcross = _germanyCircumferenceKm / math.pow(2, zoom) * 4;
  final step = kmAcross > 600
      ? 4
      : kmAcross > 150
          ? 2
          : 1;
  return [
    for (var i = 0; i < levels.length; i += step) levels[i],
  ];
}

/// Erdumfang auf Breite 51°, in Kilometern.
const _germanyCircumferenceKm = 25220.0;

/// Die Höhenstufen der 30-Tage-Summe in Millimetern.
///
/// **Eigene Wahl, und das ist kein Versehen:** `dwd:RADOLAN-W4` hat gar
/// keine Klassen — dessen Legende ist ein stufenloser Verlauf von 0,1 bis
/// 300 mm mit Marken alle 30 mm. Diese Marken sind für einen normalen
/// Sommer zu grob: Am 2026-08-03 lag der deutsche Median bei 37 mm und
/// 99 % der Fläche unter 112 mm — zwei DWD-Stufen hätten fast das ganze
/// Land eingefärbt.
///
/// Deshalb runde Zahlen mit wachsendem Abstand, dem Wertebereich
/// nachgebildet. Bewusst NEUTRAL: keine Stufe heißt „genug" oder
/// „zu wenig". Die Faustregel der Sammler (ab etwa 100 mm in 30 Tagen)
/// gehört als Zahl ins Spot-Blatt, nicht als Bewertung in eine
/// Messwertebene — das verlangen die Anzeigeregeln dieser Planung.
const rainLevels30d = [10, 20, 30, 40, 50, 75, 100, 150];

/// Dieselben Stufen für die 24-Stunden-Summe. Anderer Wertebereich:
/// Ein Landregen bringt 10–20 mm am Tag, ein Gewitter 40.
const rainLevels24h = [1, 2, 5, 10, 20, 30, 50];

/// Zieht die Höhenlinien.
///
/// [toleranceCells] ist die Vereinfachung in Gitterzellen (eine Zelle ≈
/// 1 km). Der Vorgabewert 2 ist kein Schönheitswert, sondern eine
/// Ehrlichkeitsgrenze: Feiner als das Datengitter wissen wir es nicht,
/// eine Linie mit mehr Stützpunkten behauptet also Genauigkeit, die es
/// nicht gibt. Gemessen kostet die Vereinfachung 81 % der Punkte
/// (101 027 → 19 512) und die Datei sinkt von 422 auf 292 KB.
///
/// [minChainCells] wirft Fragmente weg — die Ränder einzelner
/// Konvektionsstreifen, die als Sprenkel über der Karte lägen. Gezählt
/// wird die Länge VOR der Vereinfachung, und das ist der ganze Punkt:
/// Nach der Vereinfachung hat eine schnurgerade Linie quer durch
/// Deutschland zwei Punkte und ein Zwei-Zellen-Fragment auch. Eine
/// Schranke auf das Ergebnis würde die längste Linie mit dem kürzesten
/// Fetzen verwechseln. Ein Punkt der Rohkette entspricht ungefähr einem
/// Kilometer, die Schranke ist also eine Mindestlänge in Kilometern.
///
/// Die Kürzung ist eine Kürzung und steht deshalb im Rückgabewert von
/// [rainContourStats], nicht nur in diesem Kommentar.
///
/// [smooth] mittelt vorher über 3×3 — siehe [RainGrid.smoothed]. Der
/// Vorgabewert ist an, weil es an echten Daten 78 % der Ketten spart und
/// dabei schneller ist. Er bleibt ein Schalter, damit Tests die rohe
/// Rechnung prüfen können, und weil das Glätten eine ANSICHTSSACHE ist:
/// Die Zahl am Spot kommt aus `RainGrid.mmAt` und läuft hier nie durch.
List<ContourLine> rainContours(
  RainGrid grid, {
  required List<int> levels,
  double toleranceCells = 2,
  int minChainCells = 6,
  bool smooth = true,
}) {
  final source = smooth ? grid.smoothed() : grid;
  final lines = <ContourLine>[];
  for (final level in levels) {
    for (final chain in _chainsAt(source, level)) {
      if (chain.length < minChainCells) continue;
      final simplified = _simplify(chain, toleranceCells);
      if (simplified.length < 2) continue;
      lines.add(ContourLine(
        mm: level,
        cells: chain.length,
        points: [
          for (final point in simplified)
            LatLng(source.latAtRow(point.dy + 0.5),
                source.lonAtColumn(point.dx + 0.5)),
        ],
      ));
    }
  }
  return lines;
}

/// Was beim Ziehen weggefallen ist — für die Run-Summary und für Tests,
/// die belegen wollen, dass nicht still gekürzt wird.
({int lines, int points, int dropped, int rawPoints}) rainContourStats(
  RainGrid grid, {
  required List<int> levels,
  double toleranceCells = 2,
  int minChainCells = 6,
  bool smooth = true,
}) {
  final source = smooth ? grid.smoothed() : grid;
  var lines = 0, points = 0, dropped = 0, rawPoints = 0;
  for (final level in levels) {
    for (final chain in _chainsAt(source, level)) {
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
List<List<_Point>> _chainsAt(RainGrid grid, int level) {
  final width = grid.width;
  final height = grid.height;
  final values = grid.values;
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
      // geraten. Am Rand des Radarverbunds hören die Linien deshalb auf.
      if (ul == rainNoData ||
          ur == rainNoData ||
          lr == rainNoData ||
          ll == rainNoData) {
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
/// hier vorkommt (Deutschland: 713×891 ⇒ Kennungen unter 1,3 Mio.), und
/// das Produkt bleibt unter 2^53 — also auch im Web exakt, wo `int` ein
/// `double` ist.
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

/// Ein Punkt in Gitterkoordinaten (Spalte, Zeile) — bewusst nicht
/// `Offset`, damit diese Datei ohne Flutter auskommt.
class _Point {
  const _Point(this.dx, this.dy);
  final double dx;
  final double dy;
}
