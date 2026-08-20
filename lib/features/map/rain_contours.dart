// Die Regen-Seite der Isolinien: welche Stufen, wie geglättet, welche
// Linie bei welchem Zoom noch etwas sagt.
//
// Die Rechnung selbst steht seit 1.98.0 in `contours.dart` und wird von
// den Höhenlinien mitbenutzt — an Marching Squares ist nichts regenhaft,
// und zwei Fassungen mit je eigener Sattelpunkt-Auflösung wären zwei
// Antworten auf dieselbe Frage.
import 'dart:math' as math;

import 'contours.dart';
import 'rain_grid.dart';

export 'contours.dart' show ContourLine;

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
  final pixelsPerKm = 256 * math.pow(2, zoom) / germanyCircumferenceKm;
  final minCells = minPixels / pixelsPerKm;
  final shown = rainLevelsAtZoom(levels, zoom).toSet();
  return [
    for (final line in lines)
      if (line.cells >= minCells && shown.contains(line.level)) line,
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
  final kmAcross = kmAcrossAtZoom(zoom);
  final step = kmAcross > 600
      ? 4
      : kmAcross > 150
          ? 2
          : 1;
  return [
    for (var i = 0; i < levels.length; i += step) levels[i],
  ];
}

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

/// Zieht die Höhenlinien durch das Regengitter.
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
  int roundingPasses = 2,
}) {
  final source = smooth ? grid.smoothed() : grid;
  return contourLines(
    values: source.values,
    width: source.width,
    height: source.height,
    noData: rainNoData,
    levels: levels,
    latAtRow: source.latAtRow,
    lonAtColumn: source.lonAtColumn,
    toleranceCells: toleranceCells,
    minChainCells: minChainCells,
    roundingPasses: roundingPasses,
  );
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
  return contourStats(
    values: source.values,
    width: source.width,
    height: source.height,
    noData: rainNoData,
    levels: levels,
    toleranceCells: toleranceCells,
    minChainCells: minChainCells,
  );
}
