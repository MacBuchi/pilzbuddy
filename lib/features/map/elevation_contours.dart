// Höhenlinien aus dem Höhengitter, das ohnehin auf dem Gerät liegt.
//
// **Warum überhaupt eigene Linien und keine fertige Karte:** Höhendaten
// sind kein OSM-Inhalt, eine topografische Kachelquelle wäre also ein
// neues Netzziel — und ausgerechnet dort tot, wo diese App gebraucht
// wird: im Wald ohne Empfang. `assets/elevation/elevation.bin.gz` liegt
// seit 1.93.0 für die Temperaturkorrektur im Binary; daraus Linien zu
// ziehen kostet keine Verbindung, keine Datenschutzerklärung und keinen
// fremden Server.
//
// **Und was es dafür nicht kann:** Das Gitter hat ~270 m Wabenweite und
// 20-m-Höhenstufen. Zwei Nachbarwaben unterscheiden sich erst ab etwa
// 7,4 % Steigung um eine Stufe — im Flachland zeichnet diese Ebene zu
// Recht fast nichts. Sie zeigt Hang, Mulde und Kuppe, nicht die einzelne
// Geländekante. Genau das sagt das Blatt dem Benutzer, statt es ihn
// raten zu lassen.
//
// Reines Dart ohne Flutter, wie `forest_grid.dart` und aus demselben
// Grund: Die Rechnung soll ohne Karte prüfbar sein.
import 'dart:math' as math;
import 'dart:typed_data';

import 'contours.dart';
import 'elevation_grid.dart';
import 'forest_fill_window.dart';
import 'forest_grid.dart' show hexNearestCell;

/// „Hier wissen wir nichts" im abgetasteten Feld.
///
/// **Bewusst nicht 255 wie beim Regen:** Hier stehen Meter, keine
/// Byte-Stufen, und das Gitter reicht bis 4740 m. Eine 255 wäre eine
/// gültige Höhe im Schwarzwald.
const contourNoData = -1;

/// Höchste Zahl an Abtastpunkten je Kante.
///
/// Der Deckel greift erst weit draußen (ab etwa z11); näher dran
/// bestimmt die Wabenweite die Abtastung. NOCH NICHT GEMESSEN — der
/// Wert stammt aus der Hochrechnung gegen die eine gemessene Zahl, die
/// es gibt (Regen: 5,1 Mio. Zellprüfungen = 45 ms). Vor dem
/// Festschreiben läuft `test/perf_elevation_contours_measure.dart`.
const contourSampleBudget = 768;

/// Kürzer als das auf dem Schirm, und die Linie sagt nichts.
///
/// Wörtlich die Regel aus `rainContoursAtZoom`, hier ohne Umweg über
/// Kilometer: Fenstergeometrie und Zoomstufe geben Pixel je Abtastzelle
/// direkt her.
///
/// **Sie bringt weniger, als man denkt, und das ist die Messung wert:**
/// In den Alpen bei z11 fallen damit 77 von 916 Linien weg (2026-08-20).
/// Der Grund ist, dass [contourLines] mit `minChainCells` die kleinsten
/// Fetzen schon vorher wegwirft und eine Abtastzelle dort ohnehin rund
/// 5,5 px groß ist. Die Schranke steht trotzdem hier, weil sie in
/// BILDSCHIRMPIXELN formuliert ist: Ändert sich die Abtastung — anderes
/// Budget, anderes Gitter —, hält sie weiter, während eine Zahl in
/// Zellen still ihre Bedeutung wechselte.
const contourMinLinePixels = 40.0;

/// Sind nach dem Ziehen mehr Punkte als das übrig, wird die Äquidistanz
/// EINMAL verdoppelt und neu gezogen.
///
/// **Warum es das zusätzlich zur Zoomregel braucht:** Die
/// [contourEquidistanceM] rechnet mit einem angenommenen Hang von 10 %.
/// In den Alpen ist der drei- bis fünfmal so steil, und dieselbe
/// Äquidistanz ergibt dort ein schwarzes Gewimmel. Diese Schranke lässt
/// das Gelände vor dem Benutzer entscheiden statt meiner Annahme.
const contourPointBudget = 60000;

/// Wie viele Abtastpunkte das Fenster bekommt.
///
/// **Höchstens einer je Wabe.** Feiner wüssten wir es nicht — eine
/// höhere Abtastung bläst jede Wabe zu einem Block gleicher Werte auf,
/// und Marching Squares zeichnet daraufhin die Wabenkanten als Terrassen
/// in die Linie. Das sähe nach einem Fehler aus und wäre einer.
({int cols, int rows}) contourSampleCounts({
  required FillWindow window,
  required double hexLonStep,
  required double hexLatStep,
  int budget = contourSampleBudget,
}) {
  final cols = ((window.east - window.west) / hexLonStep).round();
  final rows = ((window.north - window.south) / hexLatStep).round();
  return (
    cols: cols.clamp(2, budget),
    rows: rows.clamp(2, budget),
  );
}

/// Das Fenster als regelmäßiges Gitter in Grad, Höhe in Metern.
///
/// Grad-linear und nicht Mercator: Das Hexgitter selbst ist in Grad
/// aufgespannt (`hexLonStep`/`hexLatStep`), eine Mercator-Verteilung
/// würde die Zeilen gegen die Waben verschieben.
class ContourField {
  const ContourField({
    required this.values,
    required this.cols,
    required this.rows,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
  });

  /// `cols * rows` Höhen in Metern, zeilenweise von Nord nach Süd;
  /// [contourNoData] wo das Gitter nichts sagt.
  final Int32List values;
  final int cols;
  final int rows;
  final double west;
  final double east;
  final double north;
  final double south;

  /// Breite einer Gitterzeile — Zellmitte bei `row + 0,5`, genau die
  /// Rechnung, die [contourLines] selbst dazutut.
  double latAtRow(double row) => north - (north - south) * row / rows;

  /// Länge einer Gitterspalte, dieselbe Verabredung.
  double lonAtColumn(double column) => west + (east - west) * column / cols;

  /// Die kleinste und größte Höhe im Feld — `null`, wenn es nur
  /// Nichtdaten enthält.
  ({int min, int max})? get range {
    int? low, high;
    for (final value in values) {
      if (value == contourNoData) continue;
      if (low == null || value < low) low = value;
      if (high == null || value > high) high = value;
    }
    return low == null ? null : (min: low, max: high!);
  }
}

/// Tastet das Höhengitter im Fenster ab und mittelt über 3×3.
///
/// Punkt → Wabe läuft ausschließlich über [hexNearestCell] — dieselbe
/// Zuordnung, die `ElevationGrid.heightMetersAt` benutzt. Eine zweite
/// Geometrie verbietet CLAUDE.md, und zwar mit Grund: Zwei Rechnungen,
/// die auseinanderlaufen, hießen hier „die Linie liegt woanders als die
/// Zahl im Blatt".
///
/// Das Glätten steht nicht zur Wahl: Ohne es entartet jede Stufe auf
/// einem 20-Meter-Vielfachen, und der Paritätsversatz des Hexgitters
/// wird als Sägezahn sichtbar (siehe [smooth3x3]).
ContourField resampleElevation(
  ElevationGrid grid, {
  required FillWindow window,
  int budget = contourSampleBudget,
  bool smooth = true,
}) {
  final counts = contourSampleCounts(
    window: window,
    hexLonStep: grid.hexLonStep,
    hexLatStep: grid.hexLatStep,
    budget: budget,
  );
  final cols = counts.cols;
  final rows = counts.rows;
  final raw = Int32List(cols * rows);
  final lonSpan = window.east - window.west;
  final latSpan = window.north - window.south;
  for (var y = 0; y < rows; y++) {
    final lat = window.north - latSpan * (y + 0.5) / rows;
    final v = (grid.north - lat) / grid.hexLatStep;
    final row = y * cols;
    for (var x = 0; x < cols; x++) {
      final lon = window.west + lonSpan * (x + 0.5) / cols;
      if (lat > grid.north ||
          lat < grid.south ||
          lon < grid.west ||
          lon > grid.east) {
        raw[row + x] = contourNoData;
        continue;
      }
      final cell = hexNearestCell(
        u: (lon - grid.west) / grid.hexLonStep,
        v: v,
        width: grid.width,
        height: grid.height,
      );
      if (cell == null) {
        raw[row + x] = contourNoData;
        continue;
      }
      final byte = grid.values[cell.$2 * grid.width + cell.$1];
      raw[row + x] =
          byte == elevationNoData ? contourNoData : byte * elevationQuantM;
    }
  }
  return ContourField(
    values: smooth
        ? smooth3x3(raw, width: cols, height: rows, noData: contourNoData)
        : raw,
    cols: cols,
    rows: rows,
    west: window.west,
    east: window.east,
    north: window.north,
    south: window.south,
  );
}

/// Die Äquidistanz in Metern, die bei dieser Zoomstufe noch etwas
/// aussagt — `null` heißt: gar nicht zeichnen.
///
/// Die Regel ist wieder ein Satz statt einer Zoomtabelle, wie bei
/// [rainLevelsAtZoom]: **Zwei Nachbarlinien, die auf dem Schirm näher
/// als [minPixels] beieinanderliegen, sind ein Schmierstreifen.** Auf
/// einem Hang von [slope] heißt das: Äquidistanz ≥ minPixels · slope ·
/// Meter-je-Pixel.
///
/// Daraus fällt, nicht geraten: 20 m ab z13, 50 m bei z12, 100 m bei
/// z11, 200 m bei z10, darunter nichts.
///
/// **Warum unter z10 gar nichts:** Nicht wegen der Zahl der Stufen,
/// sondern weil das Fenster dort das halbe Gitter umfasst und der
/// Abtast-Deckel jede vierte bis fünfte Wabe nähme. Eine 1,3-km-Linie
/// aus 270-m-Daten ist eine Karikatur. Die Legende sagt in dem Fall
/// „erst näher dran" — eine Ebene, die still nichts zeigt, ist der
/// Fehler, gegen den dieses Repo laufend Tests schreibt.
///
/// **Und 20 m ist der Boden**, weil die Rohdaten in 20-m-Stufen
/// quantisiert sind. Feiner wäre erfunden.
int? contourEquidistanceM(
  double zoom, {
  double lat = 51,
  double slope = 0.10,
  double minPixels = 12,
}) {
  final metersPerPixel =
      156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);
  final needed = minPixels * slope * metersPerPixel;
  for (final step in contourSteps) {
    if (step >= needed) return step;
  }
  return null;
}

/// Die erlaubten Äquidistanzen, aufsteigend. 20 m ist die Quantisierung
/// der Rohdaten, 200 m die gröbste Stufe, die noch Gelände beschreibt.
const contourSteps = [20, 50, 100, 200];

/// Die Stufen, die im Feld überhaupt vorkommen.
///
/// Ohne diese Einschränkung liefe Marching Squares über 0…4740 m, also
/// 237 Stufen — für ein Fenster, das oft 60 Höhenmeter umfasst.
List<int> levelsIn(ContourField field, int equidistanceM) {
  final range = field.range;
  if (range == null) return const [];
  final first = (range.min ~/ equidistanceM + 1) * equidistanceM;
  return [
    for (var level = first; level <= range.max; level += equidistanceM) level,
  ];
}

/// Das Ergebnis eines Laufs: die Linien und das, womit sie gezogen
/// wurden.
class ElevationContours {
  const ElevationContours({
    required this.lines,
    required this.equidistanceM,
    required this.key,
  });

  final List<ContourLine> lines;

  /// Was am Ende WIRKLICH gezeichnet wurde — nach der Punktschranke
  /// kann das gröber sein als die Zoomregel wollte. Die Legende zeigt
  /// diese Zahl, nicht die gewünschte.
  final int equidistanceM;

  /// Fenster plus Äquidistanz — die Kennung, auf der die MapLibre-Seite
  /// idempotent ist.
  final String key;
}

/// Zieht die Höhenlinien für ein Fenster. Das ist die Funktion, die im
/// Isolate läuft.
ElevationContours? contourLinesFor(
  ElevationGrid grid, {
  required FillWindow window,
  required double zoom,
  int sampleBudget = contourSampleBudget,
  int pointBudget = contourPointBudget,
  double minLinePixels = contourMinLinePixels,
}) {
  var equidistance = contourEquidistanceM(zoom);
  if (equidistance == null) return null;
  final field =
      resampleElevation(grid, window: window, budget: sampleBudget);

  // Pixel je Abtastzelle — daraus die Mindestlänge einer Linie.
  final degreesPerPixel = 360 / (256 * math.pow(2, zoom));
  final pixelsPerCell =
      ((window.east - window.west) / field.cols) / degreesPerPixel;
  final minCells = minLinePixels / pixelsPerCell;

  List<ContourLine> draw(int step) => [
        for (final line in contourLines(
          values: field.values,
          width: field.cols,
          height: field.rows,
          noData: contourNoData,
          levels: levelsIn(field, step),
          latAtRow: field.latAtRow,
          lonAtColumn: field.lonAtColumn,
          isIndex: (level) => level % (step * 5) == 0,
        ))
          if (line.cells >= minCells) line,
      ];

  var lines = draw(equidistance);
  var points = 0;
  for (final line in lines) {
    points += line.points.length;
  }
  if (points > pointBudget) {
    // Genau EINMAL vergröbern, nicht in einer Schleife: Ein zweiter
    // Durchgang kostet so viel wie der erste, und die nächste Stufe
    // halbiert die Linienzahl bereits.
    final coarser = contourSteps.firstWhere(
      (step) => step > equidistance!,
      orElse: () => equidistance!,
    );
    if (coarser != equidistance) {
      equidistance = coarser;
      lines = draw(coarser);
    }
  }
  return ElevationContours(
    lines: lines,
    equidistanceM: equidistance,
    key: '${window.key}_$equidistance',
  );
}

/// Die Linien als GeoJSON-FeatureCollection, für die MapLibre-Seite.
///
/// [index] wählt aus: `true` nur die Hauptlinien, `false` nur die
/// übrigen. Zwei Quellen statt einer Ebene mit Ausdruck im `paint`, weil
/// `maplibre` 0.3.5 Paint-Werte durch `toJObject()` schickt — ein
/// Ausdruck käme dort als `Object[]` an und nicht als Ausdruck. Skalare
/// kommen an, und mehr braucht es nicht.
///
/// Koordinaten auf fünf Nachkommastellen (~1 m). Das Gitter hat 270 m
/// Wabenweite; mehr Stellen wären erfundene Genauigkeit und kosten bei
/// 40 000 Punkten ein Vielfaches an Zeichen.
String contourGeoJson(List<ContourLine> lines, {required bool index}) {
  final buffer = StringBuffer('{"type":"FeatureCollection","features":[');
  var first = true;
  for (final line in lines) {
    if (line.index != index) continue;
    if (!first) buffer.write(',');
    first = false;
    buffer
      ..write('{"type":"Feature","properties":{"m":')
      ..write(line.level)
      ..write('},"geometry":{"type":"LineString","coordinates":[');
    for (var i = 0; i < line.points.length; i++) {
      if (i > 0) buffer.write(',');
      final point = line.points[i];
      buffer
        ..write('[')
        ..write(point.longitude.toStringAsFixed(5))
        ..write(',')
        ..write(point.latitude.toStringAsFixed(5))
        ..write(']');
    }
    buffer.write(']}}');
  }
  buffer.write(']}');
  return buffer.toString();
}
