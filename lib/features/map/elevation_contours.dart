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

import 'package:latlong2/latlong.dart';

import 'contours.dart';
import 'elevation_grid.dart';
import 'forest_fill_window.dart';
import 'forest_grid.dart' show hexNearestCell;
import 'map_view/marker_culling.dart' show MapViewBounds;

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
/// Kilometer: Aus der Bodenauflösung folgt die Pixelgröße einer
/// Abtastzelle direkt.
///
/// **Sie bringt weniger, als man denkt, und das ist die Messung wert:**
/// In den Alpen bei z11 fielen damit 77 von 916 Linien weg (2026-08-20).
/// Der Grund ist, dass [contourLines] mit `minChainCells` die kleinsten
/// Fetzen schon vorher wegwirft und eine Abtastzelle dort ohnehin rund
/// 5,5 px groß ist. Die Schranke steht trotzdem hier, weil sie in
/// BILDSCHIRMPIXELN formuliert ist: Ändert sich die Abtastung — anderes
/// Budget, anderes Gitter —, hält sie weiter, während eine Zahl in
/// Zellen still ihre Bedeutung wechselte.
const contourMinLinePixels = 40.0;

/// Sind nach dem Ziehen mehr Punkte als das übrig, wird die Äquidistanz
/// EINMAL vergröbert und neu gezogen.
///
/// **Seit 1.99.0 nur noch ein Netz.** Bis dahin war es die einzige
/// Bremse gegen zu dichte Linien im Steilgelände, weil
/// [contourEquidistanceM] einen Hang von 10 % ANNAHM. Jetzt misst
/// [reliefPerPixel] das Gefälle im Fenster, und die Äquidistanz folgt
/// ihm — die Schranke greift dadurch nur noch in Fenstern, die
/// ungewöhnlich viel Struktur auf einmal zeigen.
const contourPointBudget = 60000;

/// Wie weit die Vereinfachung eine Linie von ihrem Verlauf abbringen
/// darf — in BILDSCHIRMPIXELN.
///
/// **Die Zahl, die 1.99.0 die Linien kreuzen ließ**, stand als
/// „2 Gitterzellen" in [contourLines]. Eine Zelle ist beim Herauszoomen
/// ein Pixel und beim Hineinzoomen ein halber Schirm: Am Gerät
/// gemessen (2026-08-21, Alpen bei 300 m Maßstab) war eine Wabe 55 px,
/// die Toleranz also 110 px — während zwei Nachbarlinien dort 20 bis
/// 35 px auseinanderlagen. Eine Linie durfte sich um ein Vielfaches
/// ihres Abstands zur Nachbarin verschieben; dass sie sich kreuzten,
/// war keine Panne, sondern die Rechnung. Aus derselben Toleranz kam
/// die zweite Beschwerde: Was Chaikin danach rundete, waren zwei oder
/// drei Stützpunkte.
///
/// 1,5 px ist mehr als eine Größenordnung unter den 20 px, die
/// [contourMinLineSpacingPixels] zwischen zwei Linien garantiert.
/// Kreuzen können sie sich damit nicht mehr — und genau das prüft
/// `test/elevation_contours_test.dart`.
const contourSimplifyPixels = 1.5;

/// Ab wie vielen Bildschirmpixeln Abstand zwei Nachbarlinien noch als
/// zwei Linien lesbar sind.
///
/// **Das ist die eine Stellschraube der Dichte** — die Äquidistanz
/// fällt daraus, siehe [contourEquidistanceM]. 20 statt der 12 von
/// 1.98.0: Am Emulator waren die Linien in den Alpen eine Schraffur
/// (Rückmeldung Betreiber, 2026-08-21). Gemessen in
/// `docs/map-performance.md`.
const contourMinLineSpacingPixels = 20.0;

/// Meter Gelände je logischem Bildschirmpixel — der Maßstab, in dem
/// alle Regeln dieser Datei rechnen.
///
/// Zwei Zutaten, beide eindeutig: das Sichtfenster in Grad und die
/// Breite des Kartenfensters in Pixeln. Eine Zoomstufe kommt bewusst
/// nicht vor, sie bedeutet in den beiden Engines Verschiedenes (siehe
/// `mapIdleGroundResolutionProvider`).
///
/// Gerechnet wird über die BREITE, weil Längengrade in Mercator linear
/// abgebildet werden; die Höhe eines Fensters ist es nicht.
double groundResolution(MapViewBounds bounds, double widthPixels) {
  if (widthPixels <= 0) return double.infinity;
  final lat = (bounds.north + bounds.south) / 2;
  final meters =
      (bounds.east - bounds.west) * 111320 * math.cos(lat * math.pi / 180);
  return meters / widthPixels;
}

/// Gröber als das je Bildschirmpixel, und die Ebene bleibt leer.
///
/// **Eine Aussage über die DATEN, keine über den Geschmack:** Eine Wabe
/// des Höhengitters ist rund 270 m breit. Deckt ein einziges Pixel mehr
/// Boden ab als eine Wabe, zeichnete die Linie eine Genauigkeit vor,
/// die im Gitter gar nicht steht. Die Legende sagt dann „erst näher
/// dran" — sie schweigt nicht.
///
/// Die Bremse greift in der Praxis selten, weil [contourEquidistanceM]
/// im bewegten Gelände schon vorher aufgibt. Sie steht hier für den
/// Fall Flachland-Übersicht, wo das Gefälle klein und die Fläche riesig
/// ist.
const contourMaxMetersPerPixel = 270.0;

/// Das Abtastraster eines Fensters: Ursprung, Schrittweite, Maße.
///
/// Der Ursprung ist die NORDWEST-Ecke der ersten Abtastzelle; die Probe
/// selbst sitzt in deren Mitte, also bei `+0,5` — dieselbe Verabredung,
/// die [contourLines] beim Umrechnen in Grad trifft.
typedef ContourLattice = ({
  double west,
  double north,
  double lonStep,
  double latStep,
  int cols,
  int rows,
  int factor,
});

/// Wie viele Abtastpunkte das Fenster bekommt — und in welchem Raster.
///
/// **Höchstens einer je Wabe.** Feiner wüssten wir es nicht — eine
/// höhere Abtastung bläst jede Wabe zu einem Block gleicher Werte auf,
/// und Marching Squares zeichnet daraufhin die Wabenkanten als Terrassen
/// in die Linie. Das sähe nach einem Fehler aus und wäre einer.
///
/// **Und das Raster hängt am GITTER, nicht am Fenster** (seit 1.99.1).
/// Bis dahin wurde die Fensterspanne in `cols` gleiche Teile geteilt:
/// Beim Schieben plante `planFillWindow` ein neues Fenster, das Raster
/// lag woanders, jeder Punkt traf über `hexNearestCell` eine andere
/// Wabe — und die Linien würfelten sich neu (Befund des Betreibers am
/// Gerät, 2026-08-21: „sie bewegen/verändern sich auch wenn man
/// verschiebt"). Der Schritt ist deshalb ein Vielfaches der Wabenweite,
/// und der Ursprung liegt auf dem Gitter, siehe [resampleElevation].
/// Dieselbe Geografie liefert damit immer dieselben Proben.
ContourLattice contourSampleLattice({
  required FillWindow window,
  required double gridWest,
  required double gridNorth,
  required double hexLonStep,
  required double hexLatStep,
  int budget = contourSampleBudget,
}) {
  final factor = _sampleFactor(
    window: window,
    hexLonStep: hexLonStep,
    hexLatStep: hexLatStep,
    budget: budget,
  );
  final lonStep = hexLonStep * factor;
  final latStep = hexLatStep * factor;
  // Der Ursprung rastet auf dem Gitter ein — DAS ist der ganze Trick:
  // Er hängt nur an `gridWest`/`gridNorth` und der Schrittweite, nicht
  // am Fenster. Zwei Fenster über derselben Gegend tasten deshalb
  // dieselben Punkte ab.
  final west = gridWest +
      (((window.west - gridWest) / lonStep).floor() - _hexSampleOffset) *
          lonStep;
  final north =
      gridNorth - ((gridNorth - window.north) / latStep).floor() * latStep;
  // Das Epsilon fängt die Fließkomma-Kante: Liegt der Fensterrand
  // GENAU auf einer Rasterlinie, kommt aus der Division schon mal
  // 3,0000000000000004 heraus, und `ceil` hängt eine ganze Zeile
  // Nichtdaten an. Ein Milliardstel einer Wabe sind 0,27 µm.
  final cols = math.max(2, ((window.east - west) / lonStep - 1e-9).ceil());
  final rows = math.max(2, ((north - window.south) / latStep - 1e-9).ceil());
  return (
    west: west,
    north: north,
    lonStep: lonStep,
    latStep: latStep,
    cols: cols,
    rows: rows,
    factor: factor,
  );
}

/// Der Viertelschritt, um den das Raster gegen das Hexgitter versetzt
/// liegt — und ohne den die Linien beim Schieben zittern.
///
/// **Warum es ihn braucht:** Ein Hexgitter in odd-r-Anordnung hat seine
/// Mittelpunkte in GERADEN Zeilen bei `hx + 0,5` und in UNGERADEN bei
/// `hx + 1,0` (`hexNearestCell`). Eine Probe in der Zellmitte liegt bei
/// `i + 0,5` — in geraden Zeilen also genau auf einem Mittelpunkt, in
/// ungeraden aber genau ZWISCHEN zweien. Dort entscheidet das letzte
/// Bit der Fließkommarechnung, welche Wabe gewinnt, und dasselbe
/// Fenster einen Meter weiter westlich entscheidet anders: 69 von 495
/// Proben wichen so voneinander ab, mit bis zu 180 m Höhenunterschied
/// (nachgemessen 2026-08-21).
///
/// Ein Viertelschritt Versatz nimmt beiden Zeilensorten die
/// Zweideutigkeit: Der Abstand zur zweitnächsten Wabe beträgt dann in
/// jeder Zeile ein halbes Raster — rund 135 m statt eines Ulps.
const _hexSampleOffset = 0.25;

/// Um wie viele Waben das Abtastraster weiterrückt — normalerweise 1.
///
/// Ein GANZZAHLIGER Faktor, damit das gröbere Raster ein Teilraster des
/// feinen bleibt: Sonst verschöbe sich beim Wechsel alles, statt nur
/// dünner zu werden. Nachgerechnet am echten Gitter: Bis etwa 120 m je
/// Pixel ist er 1, am Riegel [contourMaxMetersPerPixel] braucht die
/// Höhe rund 1700 Proben und das Budget gibt 768 — dort also 3.
///
/// Er hängt an der Fensterspanne und damit am Zoom, nicht am Schieben.
/// **Eine Ecke bleibt:** Am Rand von DACH beschneidet `planFillWindow`
/// das Fenster, die Spanne wird kleiner, und der Faktor kann dort um
/// eins fallen — dann rechnen sich die Linien beim Schieben über diese
/// Kante einmal neu. Das ist ein Sonderfall am Datenrand und keine
/// Sonderbehandlung wert.
int _sampleFactor({
  required FillWindow window,
  required double hexLonStep,
  required double hexLatStep,
  required int budget,
}) {
  final cols = ((window.east - window.west) / hexLonStep).ceil() + 1;
  final rows = ((window.north - window.south) / hexLatStep).ceil() + 1;
  // Das +1 oben ist der schlimmste Fall: Ein Fenster, das nirgends auf
  // dem Raster einrastet, braucht eine Probe mehr als seine Spanne.
  return math.max(
    1,
    math.max((cols / budget).ceil(), (rows / budget).ceil()),
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
    required this.north,
    required this.lonStep,
    required this.latStep,
  });

  /// `cols * rows` Höhen in Metern, zeilenweise von Nord nach Süd;
  /// [contourNoData] wo das Gitter nichts sagt.
  final Int32List values;
  final int cols;
  final int rows;

  /// Die NORDWEST-Ecke der ersten Abtastzelle.
  final double west;
  final double north;

  /// Der Abstand zweier Proben in Grad — ein Vielfaches der Wabenweite
  /// des Höhengitters, siehe [contourSampleLattice].
  ///
  /// **Als Schrittweite gespeichert und nicht als Ostkante**, damit
  /// [lonAtColumn] Bit für Bit dieselbe Rechnung macht wie die
  /// Abtastung selbst. Über eine Spanne geteilt durch `cols` kamen
  /// Bruchteile eines Ulps Unterschied heraus — genug, damit ein Punkt
  /// genau auf einer Wabengrenze mal in die eine und mal in die andere
  /// Wabe fällt.
  final double lonStep;
  final double latStep;

  double get east => west + lonStep * cols;
  double get south => north - latStep * rows;

  /// Breite einer Gitterzeile — Zellmitte bei `row + 0,5`, genau die
  /// Rechnung, die [contourLines] selbst dazutut.
  double latAtRow(double row) => north - latStep * row;

  /// Länge einer Gitterspalte, dieselbe Verabredung.
  double lonAtColumn(double column) => west + lonStep * column;

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
  final lattice = contourSampleLattice(
    window: window,
    gridWest: grid.west,
    gridNorth: grid.north,
    hexLonStep: grid.hexLonStep,
    hexLatStep: grid.hexLatStep,
    budget: budget,
  );
  final cols = lattice.cols;
  final rows = lattice.rows;
  final raw = Int32List(cols * rows);
  // Die Abtastpunkte kommen aus DEMSELBEN Ausdruck, den `ContourField`
  // später für seine Koordinaten benutzt — sonst fällt ein Punkt auf
  // einer Wabengrenze beim Abtasten in die eine und beim Nachrechnen in
  // die andere Wabe.
  final field = ContourField(
    values: raw,
    cols: cols,
    rows: rows,
    west: lattice.west,
    north: lattice.north,
    lonStep: lattice.lonStep,
    latStep: lattice.latStep,
  );
  for (var y = 0; y < rows; y++) {
    final lat = field.latAtRow(y + 0.5);
    final v = (grid.north - lat) / grid.hexLatStep;
    final row = y * cols;
    for (var x = 0; x < cols; x++) {
      final lon = field.lonAtColumn(x + 0.5);
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
  if (!smooth) return field;
  return ContourField(
    values: smooth3x3(raw, width: cols, height: rows, noData: contourNoData),
    cols: cols,
    rows: rows,
    west: lattice.west,
    north: lattice.north,
    lonStep: lattice.lonStep,
    latStep: lattice.latStep,
  );
}

/// Wie viele HÖHENMETER ein Bildschirmpixel typischerweise überwindet.
///
/// **Das ist die Zahl, aus der die Äquidistanz fällt** — und sie kommt
/// aus dem Gelände selbst, nicht aus einer Annahme. Bis 1.98.0 stand
/// dort ein unterstellter Hang von 10 %; in den Alpen ist er drei- bis
/// fünfmal so steil, und dieselbe Äquidistanz wurde dort zur Schraffur
/// (am Emulator gesehen, 2026-08-21).
///
/// Genommen wird das **75. Perzentil** der Höhenunterschiede zwischen
/// Nachbarzellen, nicht der Median: Ein Fenster mit Talboden UND
/// Steilhang hat einen niedrigen Median, und die Linien wären genau
/// dort zu dicht, wo man sie lesen will. Das Perzentil richtet sich
/// nach dem bewegteren Viertel.
///
/// `null`, wenn zu wenige Nachbarpaare Daten haben.
double? reliefPerPixel(ContourField field, {required double pixelsPerCell}) {
  final steps = <int>[];
  for (var y = 0; y < field.rows; y++) {
    final row = y * field.cols;
    for (var x = 0; x < field.cols; x++) {
      final here = field.values[row + x];
      if (here == contourNoData) continue;
      if (x + 1 < field.cols) {
        final right = field.values[row + x + 1];
        if (right != contourNoData) steps.add((here - right).abs());
      }
      if (y + 1 < field.rows) {
        final below = field.values[row + field.cols + x];
        if (below != contourNoData) steps.add((here - below).abs());
      }
    }
  }
  if (steps.length < 8) return null;
  steps.sort();
  final perCell = steps[(steps.length * 3) ~/ 4].toDouble();
  return perCell / pixelsPerCell;
}

/// Die Äquidistanz in Metern, die auf DIESEM Gelände bei DIESER
/// Auflösung noch etwas aussagt — `null` heißt: gar nicht zeichnen.
///
/// Die Regel ist ein Satz, keine Zoomtabelle: **Zwei Nachbarlinien, die
/// auf dem Schirm näher als [contourMinLineSpacingPixels]
/// beieinanderliegen, sind eine Schraffur.** Steigt ein Pixel um
/// [reliefPerPixel] Höhenmeter, folgt daraus unmittelbar
/// `Äquidistanz ≥ Abstand · Relief-je-Pixel`.
///
/// Was das im Gelände heißt (nachgerechnet in
/// `docs/map-performance.md`): im Mittelgebirge 20 m nah dran und
/// 200 m in der Landschaftsübersicht — in den Alpen bei derselben
/// Zoomstufe je eine Stufe gröber, und weit draußen gar nichts mehr.
/// Dieselbe Regel, zwei Antworten, weil das Gelände zwei verschiedene
/// ist.
///
/// **20 m ist der Boden**, weil die Rohdaten in 20-m-Stufen quantisiert
/// sind. Feiner wäre erfunden.
int? contourEquidistanceM({
  required double reliefPerPixel,
  double minSpacingPixels = contourMinLineSpacingPixels,
}) {
  final needed = minSpacingPixels * reliefPerPixel;
  for (final step in contourSteps) {
    if (step >= needed) return step;
  }
  return null;
}

/// Die erlaubten Äquidistanzen, aufsteigend. 20 m ist die Quantisierung
/// der Rohdaten, 200 m die gröbste Stufe, die noch Gelände beschreibt.
const contourSteps = [20, 50, 100, 200];

/// Höhenabstand, in dem eine HAUPTLINIE kommen soll — die kräftige mit
/// der Zahl daran.
///
/// **Nicht „jede fünfte", und der Unterschied ist der Sinn der Zahlen:**
/// Bei 20 m Äquidistanz ist jede fünfte genau das (100 m). Bei 100 m
/// wäre jede fünfte alle 500 Höhenmeter — in einem Talkessel steht dann
/// keine einzige Zahl auf dem Schirm, und die Ebene ist wieder so
/// stumm wie vor der Beschriftung.
const contourIndexEveryM = 100;

/// Der Höhenabstand der Hauptlinien bei dieser Äquidistanz — immer ein
/// Vielfaches von [equidistanceM], mindestens [contourIndexEveryM].
int contourIndexStepM(int equidistanceM) =>
    equidistanceM * math.max(1, (contourIndexEveryM / equidistanceM).ceil());

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

/// Ein Platz für eine Zahl an einer Hauptlinie.
///
/// **Warum es das von Hand gibt:** MapLibre kann Beschriftung entlang
/// einer Linie (`symbol-placement: line`), flutter_map kann es nicht —
/// dort ist eine Beschriftung ein Marker, also ein Punkt mit einem
/// Winkel. Beide Engines sollen dasselbe sagen, deshalb rechnet diese
/// Funktion für die zweite nach, was die erste selbst erledigt.
class ContourLabel {
  const ContourLabel({
    required this.point,
    required this.angleRadians,
    required this.level,
  });

  final LatLng point;

  /// Drehung im Uhrzeigersinn für `Transform.rotate`, so gewählt, dass
  /// die Zahl nie auf dem Kopf steht.
  final double angleRadians;

  /// Die Höhe in Metern — das, was dort geschrieben wird.
  final int level;
}

/// Verteilt Zahlen auf die Hauptlinien, etwa alle [spacingPixels].
///
/// Kurze Linien bekommen keine: Eine Zahl auf einem 30-Pixel-Stummel
/// überdeckt ihn ganz. Gerechnet wird in Bildschirmpixeln, damit der
/// Abstand beim Herauszoomen nicht mitwächst.
List<ContourLabel> contourLabels(
  List<ContourLine> lines, {
  required double metersPerPixel,
  double spacingPixels = 420,
  double minLinePixels = 140,
}) {
  final spacing = spacingPixels * metersPerPixel;
  final minLength = minLinePixels * metersPerPixel;
  final labels = <ContourLabel>[];
  for (final line in lines) {
    if (!line.index || line.points.length < 2) continue;
    // Erst die Länge, dann die Plätze: Ohne Länge wüsste man nicht, ob
    // überhaupt eine Zahl hineinpasst, und wo die erste sitzen soll,
    // damit sie mittig steht statt am Anfang zu kleben.
    final segments = <double>[];
    var total = 0.0;
    for (var i = 1; i < line.points.length; i++) {
      final metres = _metersBetween(line.points[i - 1], line.points[i]);
      segments.add(metres);
      total += metres;
    }
    if (total < minLength) continue;
    final count = math.max(1, (total / spacing).floor());
    final step = total / (count + 1);
    // Die Plätze VORHER festlegen, nicht im Gehen hochzählen: Sonst
    // rutscht der letzte durch Rundung auf die Gesamtlänge und die Zahl
    // sitzt auf dem Linienende statt zwischen den Enden.
    final targets = [for (var k = 1; k <= count; k++) k * step];
    var placed = 0;
    var walked = 0.0;
    for (var i = 0; i < segments.length && placed < targets.length; i++) {
      final next = walked + segments[i];
      while (placed < targets.length && targets[placed] <= next) {
        final from = line.points[i];
        final to = line.points[i + 1];
        final t =
            segments[i] == 0 ? 0.0 : (targets[placed] - walked) / segments[i];
        labels.add(ContourLabel(
          point: LatLng(
            from.latitude + (to.latitude - from.latitude) * t,
            from.longitude + (to.longitude - from.longitude) * t,
          ),
          angleRadians: _uprightAngle(from, to),
          level: line.level,
        ));
        placed++;
      }
      walked = next;
    }
  }
  return labels;
}

double _metersBetween(LatLng a, LatLng b) {
  final midLat = (a.latitude + b.latitude) / 2 * math.pi / 180;
  final dx = (b.longitude - a.longitude) * 111320 * math.cos(midLat);
  final dy = (b.latitude - a.latitude) * 110574;
  return math.sqrt(dx * dx + dy * dy);
}

/// Der Winkel der Strecke auf dem Schirm — bei Bedarf um 180° gedreht,
/// damit die Zahl lesbar bleibt statt kopfzustehen.
double _uprightAngle(LatLng from, LatLng to) {
  final midLat = (from.latitude + to.latitude) / 2 * math.pi / 180;
  final dx = (to.longitude - from.longitude) * math.cos(midLat);
  // Bildschirm-y wächst nach unten, Breitengrade nach oben.
  final dy = -(to.latitude - from.latitude);
  var angle = math.atan2(dy, dx);
  if (angle > math.pi / 2) angle -= math.pi;
  if (angle < -math.pi / 2) angle += math.pi;
  return angle;
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
///
/// [metersPerPixel] ist die Bodenauflösung am Bildschirm — Meter
/// Gelände je logischem Pixel. **Bewusst das und keine Zoomstufe:** Die
/// beiden Engines zählen Zoom verschieden (MapLibre in 512er-Kacheln,
/// flutter_map in 256ern), dieselbe Zahl bedeutete auf Android und Web
/// also zwei verschiedene Maßstäbe. Bis 1.98.0 rechneten die Regeln
/// hier in der 256er-Zählung — auf Android damit durchweg eine Stufe
/// daneben (am 2026-08-21 am Gerät nachgemessen: Karte auf 12,0, Regel
/// rechnete mit 11). Meter je Pixel hat diese Zweideutigkeit nicht.
ElevationContours? contourLinesFor(
  ElevationGrid grid, {
  required FillWindow window,
  required double metersPerPixel,
  int sampleBudget = contourSampleBudget,
  int pointBudget = contourPointBudget,
  double minLinePixels = contourMinLinePixels,
  double minSpacingPixels = contourMinLineSpacingPixels,
  double maxMetersPerPixel = contourMaxMetersPerPixel,
  double simplifyPixels = contourSimplifyPixels,
}) {
  if (metersPerPixel > maxMetersPerPixel) return null;
  final field =
      resampleElevation(grid, window: window, budget: sampleBudget);

  // Pixel je Abtastzelle — die Umrechnung, an der ALLE Schwellen dieser
  // Funktion hängen. Gerechnet wird auf dem Feld, nicht auf dem
  // Fenster: Seit die Abtastung aufs Gitter gerastert ist, decken sich
  // beide nicht mehr genau.
  final metersPerCell = (field.east - field.west) *
      111320 *
      math.cos((field.north + field.south) / 2 * math.pi / 180) /
      field.cols;
  final pixelsPerCell = metersPerCell / metersPerPixel;

  final relief = reliefPerPixel(field, pixelsPerCell: pixelsPerCell);
  if (relief == null) return null;
  var equidistance = contourEquidistanceM(
      reliefPerPixel: relief, minSpacingPixels: minSpacingPixels);
  if (equidistance == null) return null;

  // **Die beiden Schwellen der Maschine, in Pixeln gerechnet.** Sie
  // sind dort in Gitterzellen formuliert, und eine Zelle ist beim
  // Herauszoomen ein Pixel und beim Hineinzoomen ein halber Schirm —
  // eine feste Zahl in Zellen ist damit dort am schärfsten, wo sie am
  // wenigsten darf.
  final tolerance = simplifyPixels / pixelsPerCell;
  // Die Längenregel läuft VOR der Vereinfachung, wo sie billiger ist —
  // und sie ist damit die EINZIGE: Bis 1.99.0 filterte hier zusätzlich
  // `line.cells >= minLinePixels / pixelsPerCell` dasselbe noch einmal
  // nach, während die Maschine mit ihren festen 6 Zellen nah dran jeden
  // Ring unter 320 px wegwarf — also genau die Kuppen und Mulden, für
  // die man hineinzoomt.
  final minChain = math.max(2, (minLinePixels / pixelsPerCell).round());

  List<ContourLine> draw(int step) => contourLines(
        values: field.values,
        width: field.cols,
        height: field.rows,
        noData: contourNoData,
        levels: levelsIn(field, step),
        latAtRow: field.latAtRow,
        lonAtColumn: field.lonAtColumn,
        toleranceCells: tolerance,
        minChainCells: minChain,
        isIndex: (level) => level % contourIndexStepM(step) == 0,
      );

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
