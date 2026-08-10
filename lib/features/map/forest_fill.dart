// Die Waldtypen-Fläche (#213): das Gitter direkt eingefärbt, als PNG
// durch dieselbe Bild-Overlay-Strecke wie der Regen (MapLibre über eine
// `image`-Source mit `file://`, flutter_map über `OverlayImage`).
//
// Anders als beim Regen wird NICHT geglättet: Der Regen glättet, damit
// Fläche und (frühere) Linien dieselbe Wahrheit zeigen und Sprenkel
// einzelner Zellen verschwinden — Wald hat keine Linien, und eine
// 250-m-Zelle Laubwald im Fichtenhang ist keine Störung, sondern genau
// die Information, nach der jemand sucht. Die Klötzchen sind die Daten.
//
// **Waben tragen DECKUNG bei, statt gefüllt zu werden** (Feldbericht des
// Betreibers 2026-08-09: „relativ weit rausgezoomt entstehen Lücken, dann
// Streifen, in der Deutschland-Gesamtansicht ist gar nichts mehr zu
// erkennen"). Der erste Sechseck-Zeichner (#251) malte VORWÄRTS: Wabe →
// Pixelzeilen. Ist eine Wabe schmaler als ein Pixel, fällt beim Runden
// `von-Zeile > bis-Zeile` heraus — und sie wird gar nicht gemalt. Am
// echten Asset gemessen (Waldanteil des Ausschnitts gegen die gemalte
// Fläche, `docs/map-performance.md`):
//
//   Sichtfenster   Wabe im Bild   Wahrheit   gefüllt   Deckung
//   852 km (DACH)      0,39 px      47,8 %     0,0 %    43,5 %
//   199 km             1,04 px      51,4 %    31,3 %    54,1 %
//   50 km              4,15 px      53,4 %    51,9 %    53,6 %
//
// Seither trägt jede Wabe ihren FLÄCHENANTEIL zu den Pixeln bei, die sie
// berührt; die Farbe eines Pixels ist die deckungsstärkste Klasse, seine
// Deckkraft die Gesamtdeckung. Das ist Kantenglättung, keine
// Datenerfindung: dieselbe Mittelung, die `tool/forest_grid.py` beim Bau
// eines gröberen Gitters macht — nur auf die Auflösung, die der
// Bildschirm gerade zeigt. Zwei Nebenwirkungen mit Absicht: Wabenränder
// laufen weich aus statt zu treppen, und aneinander grenzende Waben
// derselben Klasse haben KEINE Naht mehr (ihre Anteile addieren sich zu
// einem vollen Pixel).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;

import '../../core/app_colors.dart';
import '../ampel/ampel_fill.dart' show AmpelLevelGrid;
import '../ampel/ampel_model.dart' show AmpelLevel;
import 'forest_fill_window.dart';
import 'forest_grid.dart';
import 'overlay_png.dart';
import 'rain_grid.dart' show latFromMercatorY, mercatorY;

/// Deckkraft der Waldfläche, 0–255. Startwert = die 55 % des Regen-Fills
/// (`rainFillAlpha`), am Gerät gegenzuprüfen — der Regen brauchte dafür
/// drei Anläufe, und die Obergrenze ist dieselbe: Die Karte darunter
/// (Wege! Ortsnamen!) muss lesbar bleiben.
const forestFillAlpha = 140;

/// Alle drei Waldklassen — der Standard der Ebene und zugleich die
/// Schreibweise für „nichts abgewählt".
const allForestClasses = {
  ForestClass.broadleaf,
  ForestClass.mixed,
  ForestClass.conifer,
};

/// Färbt das Waldgitter ein und gibt ein PNG zurück.
///
/// „Kein Wald" bleibt durchsichtig — die Ebene sagt, wo Wald steht,
/// nicht, wo keiner steht. „Keine Daten" ist ebenfalls durchsichtig;
/// den Unterschied erklärt das Blatt (Abdeckung: DACH).
///
/// [classes] sind die eingeblendeten Teil-Ebenen (#231): Abgewählte
/// Klassen werden durchsichtig wie „kein Wald". So bleibt neben der
/// Regenfläche (#232) genau die Klasse stehen, die einen interessiert,
/// statt dass die ganze Karte unter zwei Schleiern abstumpft.
///
/// **Die Zeilen des PNGs sind MERCATOR-verteilt, nicht grad-verteilt**
/// (#247, seit 1.68.1): Beide Engines spannen ein Bild linear in
/// Web-Mercator zwischen seine Eckpunkte — ein grad-lineares Bild stimmt
/// dann nur am Nord- und Südrand und liegt in der Mitte der Box um bis zu
/// ~26 km daneben. Genau davor warnt der Kopfkommentar in
/// `forest_grid.dart` („linear in Breite UND Länge, anders als der
/// Regen"); dieser Maler hat es ignoriert, und am Brocken zeigte die
/// Fläche das Buchenland des Südharzes (Feldbericht 2026-08-09, mit
/// Pixelfarben nachgemessen). Der Regen-Fill braucht keine Umrechnung,
/// weil sein Gitter SELBST Mercator-Zeilen hat.
///
/// Je Ausgabepixel wird die Zelle unter seinem Mittelpunkt gewählt
/// (nearest) — die Werte sind Klassen, Mitteln wäre Datenerfindung.
///
/// [window] ist der zu malende AUSSCHNITT samt Pixelmaßen (#249) — der
/// Planer (`forest_fill_window.dart`) hält ihn im Budget. Ohne Angabe
/// wird das ganze Gitter gemalt, ein Pixel je Spalte und Zeile — der Weg
/// der Bestandstests, und mit dem 250-m-Asset noch tragbar (52 MB
/// Puffer); die Karte selbst geht seit #249 immer über ein Fenster.
Uint8List forestFillPng(ForestGrid grid,
    {int alpha = forestFillAlpha,
    Set<ForestClass> classes = allForestClasses,
    FillWindow? window}) {
  window ??= FillWindow(
    west: grid.west,
    east: grid.east,
    north: grid.north,
    south: grid.south,
    width: grid.width,
    height: grid.height,
  );
  final width = window.width;
  final rows = window.height;

  if (grid.isHex) {
    final coverage = _HexCoverage(window)..add(grid, classes);
    return overlayPng(width, rows,
        coverage.resolve(_forestBandColours, List.filled(3, alpha)));
  }

  // Ab hier das QUADRAT-Gitter: je Ausgabepixel die Zelle unter seinem
  // Mittelpunkt. Das Asset und die Blöcke sind seit #251 Waben, dieser
  // Weg trägt nur noch Gitter ohne `lattice` im Manifest — er kann nicht
  // leer laufen (jedes Pixel bekommt eine Zelle) und braucht die
  // Deckungsrechnung deshalb nicht.
  final palette = _paletteFor(alpha, classes);
  final mercNorth = mercatorY(window.north);
  final mercSpan = mercatorY(window.south) - mercNorth;

  // Spalte -> Gitterspalte, einmal statt je Zeile: Die Länge ist in
  // beiden Abbildungen linear, nur der Ausschnitt verschiebt sie.
  final columnMap = Int32List(width);
  for (var x = 0; x < width; x++) {
    final lon =
        window.west + (x + 0.5) / width * (window.east - window.west);
    final gridX = ((lon - grid.west) / (grid.east - grid.west) * grid.width)
        .floor()
        .clamp(0, grid.width - 1);
    columnMap[x] = gridX;
  }

  final raw = Uint8List(rows * (width * 4 + 1));
  var cursor = 0;
  for (var y = 0; y < rows; y++) {
    raw[cursor++] = 0; // Filter „None"
    // Zeilenmitte in Mercator -> Breite -> Gitterzeile (nearest).
    final lat = latFromMercatorY(mercNorth + (y + 0.5) / rows * mercSpan);
    final gridY = ((grid.north - lat) /
            (grid.north - grid.south) *
            grid.height)
        .floor()
        .clamp(0, grid.height - 1);
    final row = gridY * grid.width;
    for (var x = 0; x < width; x++) {
      final offset = grid.values[row + columnMap[x]] * 4;
      raw[cursor++] = palette[offset];
      raw[cursor++] = palette[offset + 1];
      raw[cursor++] = palette[offset + 2];
      raw[cursor++] = palette[offset + 3];
    }
  }

  return overlayPng(width, rows, raw);
}

/// Nachschlagetabelle wie beim Regen: Millionen Zellen, 256 Einträge.
/// Abgewählte Klassen und „kein Wald" bleiben durchsichtig (Alpha 0).
Uint8List _paletteFor(int alpha, Set<ForestClass> classes) {
  final palette = Uint8List(256 * 4);
  for (var value = 0; value < 256; value++) {
    final forestClass = classOfByte(value);
    if (forestClass == ForestClass.none || !classes.contains(forestClass)) {
      continue; // durchsichtig
    }
    final Color colour;
    switch (forestClass) {
      case ForestClass.none:
        continue; // oben schon behandelt — der Vollständigkeit halber
      case ForestClass.broadleaf:
        colour = AppColors.forestBroadleaf;
      case ForestClass.mixed:
        colour = AppColors.forestMixed;
      case ForestClass.conifer:
        colour = AppColors.forestConifer;
    }
    final offset = value * 4;
    palette[offset] = (colour.r * 255).round();
    palette[offset + 1] = (colour.g * 255).round();
    palette[offset + 2] = (colour.b * 255).round();
    palette[offset + 3] = alpha;
  }
  return palette;
}

/// Die feine Stufe (#253): mehrere Blockgitter in EIN Fensterbild. Die
/// Blöcke kacheln das globale Gitter ohne Überlappung, jeder trägt seine
/// Waben mit seinem eigenen Anker bei — die Naht zwischen zwei Blöcken
/// ist damit dieselbe Wabenkante wie mitten im Block, und
/// `test/forest_fill_test.dart` hält fest, dass das Ergebnis pixelgleich
/// zum Ganzgitter ist. Dass Deckung ADDIERT wird, macht das robuster als
/// vorher: An der Naht zählen beide Seiten mit, statt dass der spätere
/// Block den früheren überschreibt.
Uint8List forestFillPngMulti(List<ForestGrid> grids,
    {int alpha = forestFillAlpha,
    Set<ForestClass> classes = allForestClasses,
    required FillWindow window}) {
  final coverage = _HexCoverage(window);
  for (final grid in grids) {
    coverage.add(grid, classes);
  }
  return overlayPng(window.width, window.height,
      coverage.resolve(_forestBandColours, List.filled(3, alpha)));
}

/// Die Kombi-Ebene „Wald + Pilzwetter" (Betreiber-Wunsch 2026-08-09):
/// dieselben Waben, aber die mit gutem Wetter LEUCHTEN.
///
/// Warum als ein Bild und nicht als zwei Ebenen übereinander: Zwei
/// Schleier ergeben Matsch, und die Frage lautet nicht „wo ist Wald und
/// wo ist Wetter", sondern „wo ist beides". Genau das kann nur ein
/// Zeichner beantworten, der beim Malen jeder Wabe ihr Wetter kennt.
///
/// **Die leuchtende Wabe behält ihre Waldklasse** (seit 1.80.0): Sie
/// bekommt den gesetzten Ton aus [AppColors.ampelCombined] für ihr Paar
/// (Klasse, Stufe) — Laub violett, Nadel königsblau, Misch dazwischen.
/// Bis 1.79.0 trug jede leuchtende Wabe denselben Ton, die Waldklasse
/// war also genau dort weg, wo man sie wissen will. Warum eine Tabelle
/// und keine Mischung, steht bei den Farben selbst.
///
/// Der Wald bleibt sichtbar (schwächer, [forestCombinedAlpha]) — sonst
/// stünden die Leuchtpunkte ohne den Zusammenhang da, in dem man sie
/// liest. Wo [levels] nichts sagt (außerhalb Deutschlands, Radarrand),
/// bleibt die Wabe schlicht Wald; „leuchtet nicht" heißt dort also
/// weder schlecht noch unbekannt, und deshalb nennt das Blatt die
/// Abdeckung.
Uint8List forestAmpelFillPng(List<ForestGrid> grids,
    {required FillWindow window,
    required AmpelLevelGrid levels,
    Set<ForestClass> classes = allForestClasses}) {
  final coverage = _HexCoverage(window, bandCount: 5);
  for (final grid in grids) {
    coverage.add(grid, classes, highlight: levels);
  }
  return overlayPng(
      window.width, window.height, coverage.resolveCombined());
}

/// Deckung als Festkomma: [_coverageUnit] Einheiten sind ein GANZES
/// Pixel. `Uint16` statt `Float32` halbiert den Puffer (14 statt 28 MB
/// beim größten Fenster, siehe `docs/map-performance.md`), und die
/// Auflösung reicht mit Abstand: Selbst im Übersichtszoom, wo sieben
/// Waben in einem Pixel liegen, bringt jede noch ~130 Einheiten mit.
/// Überlaufen kann der Wert nicht — die Waben kacheln, die Summe je
/// Pixel liegt also bei ~1024 und nicht bei 65535.
const _coverageUnit = 1024;

/// Die Bänder des Zeichners. Die ersten drei sind die Waldklassen in der
/// Reihenfolge von [ForestClass] (ohne `none`); die beiden letzten
/// kommen nur in der Kombi-Ebene vor und zählen, wie viel der Fläche
/// eines Pixels LEUCHTET — sie treten nicht an die Stelle des
/// Klassenbands, sondern kommen hinzu.
const _bandVerhalten = 3;
const _bandGuenstig = 4;

/// Deckkraft der Waldwaben in der KOMBI-Ebene — schwächer als die 140
/// der reinen Waldfläche: Dort ist der Wald die Aussage, hier ist er der
/// Zusammenhang, in dem die leuchtenden Waben stehen.
const forestCombinedAlpha = 95;

/// Und die beiden Leuchtstufen.
///
/// **Die Stufe steckt in der DECKKRAFT, die Waldklasse im FARBTON**
/// (Betreiber, 2026-08-10). Beide Achsen brauchen eine eigene
/// Ausdrucksweise, sonst überschreiben sie sich: Bis 1.79.0 trug der
/// Farbton beides, und weil er nur einer sein kann, gewann das Wetter
/// und der Wald verschwand. Innerhalb einer Spalte von
/// [AppColors.ampelCombined] bleibt der Ton deshalb derselbe, nur
/// heller/dichter — die Bedeutung bleibt geordnet, weil das
/// KRÄFTIGERE „besser" heißt.
///
/// Beide Werte liegen unter den 170/235 von vorher: „verhalten" soll
/// den Blick nicht so führen wie „günstig" (Betreiber: „der Wert für
/// Verhalten kann etwas weniger kräftig sein"), und 235 deckte auch
/// Wege und Ortsnamen zu — die Obergrenze ist dieselbe wie bei allen
/// Flächen der Karte: Was darunter liegt, muss lesbar bleiben.
const ampelVerhaltenAlpha = 150;
const ampelGuenstigAlpha = 215;

/// Der Wabenzeichner: sammelt je Ausgabepixel, wie viel Fläche jedes
/// BAND dort bedeckt. Bänder sind normalerweise die drei Waldklassen
/// (Laub, Misch, Nadel); die Kombi-Ebene „Wald + Pilzwetter" hängt zwei
/// Leucht-Bänder an (verhalten, günstig), in die eine Wabe wandert,
/// wenn an ihrem Mittelpunkt das Wetter stimmt.
///
/// Die vier Höhenlinien eines Sechsecks werden EINZELN durch die
/// Mercator-Abbildung geschickt (innerhalb eines ~250-m-Hexes ist die
/// Krümmung belanglos, aber die LAGE muss stimmen — die Lehre aus #247).
///
/// Zwei Wege, ein Ergebnis: Waben ab Pixelgröße laufen über Zeilen
/// (Scanline) mit anteiligen Rand-Pixeln, kleinere werfen ihre ganze
/// Fläche bilinear auf die vier Nachbarpixel ihres Mittelpunkts. Der
/// zweite Weg ist der, den es vorher nicht gab — und ohne ihn
/// verschwindet die Karte beim Rauszoomen (Kopfkommentar).
class _HexCoverage {
  _HexCoverage(this.window, {this.bandCount = 3})
      : _bands = Uint16List(window.width * window.height * bandCount),
        _mercNorth = mercatorY(window.north),
        _mercSpan = mercatorY(window.south) - mercatorY(window.north);

  final FillWindow window;

  /// Wie viele Bänder je Pixel: 3 für die reine Waldfläche, 5 mit den
  /// beiden Leucht-Bändern der Kombi-Ebene. Jedes Band kostet 2 Bytes
  /// je Pixel (14 bzw. 23 MB beim größten Fenster).
  final int bandCount;

  /// [bandCount] Werte je Pixel: erst die Klassen in der Reihenfolge von
  /// [ForestClass] ohne `none` (Laub, Misch, Nadel), dann die
  /// Leucht-Bänder (verhalten, günstig).
  final Uint16List _bands;
  final double _mercNorth;
  final double _mercSpan;

  /// Trägt alle Waben von [grid] bei, die das Fenster berühren.
  ///
  /// [highlight] schaltet die Kombi-Ebene ein: Jede Wabe fragt an ihrem
  /// MITTELPUNKT die Ampel-Stufe ab und zahlt bei „verhalten"/„günstig"
  /// ZUSÄTZLICH in Band 3 bzw. 4 ein — ihr Klassenband behält sie.
  /// Deshalb kann [resolveCombined] hinterher beides beantworten: „in
  /// welchem Wald" und „wie das Wetter". Die Gitterzeile wird je
  /// WABENZEILE gerechnet, nicht je Wabe — die Breite ist dort
  /// konstant, und zwei Logarithmen je Wabe wären bei Millionen Waben
  /// der Unterschied zwischen läuft und ruckelt.
  void add(ForestGrid grid, Set<ForestClass> classes,
      {AmpelLevelGrid? highlight}) {
    final width = window.width;
    final rows = window.height;
    final lonStep = grid.hexLonStep!;
    final latStep = grid.hexLatStep!;
    final rDeg = latStep / 1.5; // Umkreisradius in Grad Breite
    final lonSpan = window.east - window.west;
    final wPx = lonStep / lonSpan * width;

    // Byte -> Band (0 Laub, 1 Misch, 2 Nadel) oder -1 für „trägt nichts
    // bei": kein Wald, keine Daten, abgewählte Klasse (#231). Einmal
    // statt je Zelle — im Übersichtszoom läuft die Schleife über 13,6
    // Millionen Waben, da zählt jeder Aufruf.
    final bandOf = Int8List(256);
    for (var value = 0; value < 256; value++) {
      final forestClass = classOfByte(value);
      bandOf[value] =
          forestClass == ForestClass.none || !classes.contains(forestClass)
              ? -1
              : forestClass.index - 1;
    }

    double xOf(double lon) => (lon - window.west) / lonSpan * width;
    double yOf(double lat) =>
        (mercatorY(lat) - _mercNorth) / _mercSpan * rows;

    // Hex-Zeilen/-Spalten, die das Fenster berühren (plus Rand).
    final hy0 =
        math.max(0, (((grid.north - window.north) / latStep) - 2).floor());
    final hy1 = math.min(
        grid.height - 1, (((grid.north - window.south) / latStep) + 2).ceil());
    final hx0 =
        math.max(0, (((window.west - grid.west) / lonStep) - 2).floor());
    final hx1 = math.min(
        grid.width - 1, (((window.east - grid.west) / lonStep) + 2).ceil());

    for (var hy = hy0; hy <= hy1; hy++) {
      final odd = hy.isOdd ? 0.5 : 0.0;
      final latC = grid.north - latStep * (hy + 2 / 3);
      // Die Ampel-Gitterzeile dieser Wabenzeile — einmal, nicht je Wabe.
      final ampelRow = highlight?.rowAt(latC);
      final yTop = yOf(latC + rDeg);
      final yUp = yOf(latC + rDeg / 2);
      final yLow = yOf(latC - rDeg / 2);
      final yBot = yOf(latC - rDeg);
      if (yBot < 0 || yTop >= rows) continue;
      final rowBase = hy * grid.width;
      final cxFirst = xOf(grid.west + lonStep * (hx0 + 0.5 + odd));

      final lonFirst = grid.west + lonStep * (hx0 + 0.5 + odd);
      if (wPx < 1.0 || yBot - yTop < 1.0) {
        _addSmallRow(grid, bandOf, rowBase, hx0, hx1,
            cxFirst: cxFirst,
            wPx: wPx,
            // Sechseckfläche = 0,75 · Breite · Höhe.
            area: 0.75 * wPx * (yBot - yTop),
            yMid: (yTop + yBot) / 2,
            highlight: highlight,
            ampelRow: ampelRow,
            lonFirst: lonFirst,
            lonStep: lonStep);
        continue;
      }

      var cx = cxFirst;
      var lonC = lonFirst;
      for (var hx = hx0; hx <= hx1; hx++, cx += wPx, lonC += lonStep) {
        final band = bandOf[grid.values[rowBase + hx]];
        if (band < 0) continue;
        if (cx + wPx / 2 <= 0 || cx - wPx / 2 >= width) continue;
        final lit = _litBand(highlight, ampelRow, lonC);
        final py0 = math.max(0, yTop.floor());
        final py1 = math.min(rows - 1, yBot.floor());
        for (var py = py0; py <= py1; py++) {
          // Anteil DIESER Pixelzeile, den die Wabe überdeckt.
          final top = math.max(yTop, py.toDouble());
          final bottom = math.min(yBot, py + 1.0);
          final vertical = bottom - top;
          if (vertical <= 0) continue;
          // Halbbreite auf halber Höhe des überdeckten Streifens: oben
          // und unten verjüngt sich das Sechseck linear zur Spitze.
          final yc = (top + bottom) / 2;
          final double half;
          if (yc <= yUp) {
            half = wPx / 2 * ((yc - yTop) / (yUp - yTop));
          } else if (yc >= yLow) {
            half = wPx / 2 * ((yBot - yc) / (yBot - yLow));
          } else {
            half = wPx / 2;
          }
          if (half <= 0) continue;
          final x0 = cx - half;
          final x1 = cx + half;
          final px0 = math.max(0, x0.floor());
          final px1 = math.min(width - 1, x1.floor());
          final rowOffset = py * width;
          for (var px = px0; px <= px1; px++) {
            final left = math.max(x0, px.toDouble());
            final right = math.min(x1, px + 1.0);
            if (right <= left) continue;
            final share =
                (vertical * (right - left) * _coverageUnit).round();
            final offset = (rowOffset + px) * bandCount;
            _bands[offset + band] += share;
            // Leuchtende Waben zählen DOPPELT: einmal für ihre Klasse,
            // einmal für ihre Stufe. Derselbe gerundete Betrag, damit
            // die Leuchtdeckung nie größer wird als die Klassendeckung.
            if (lit >= 0) _bands[offset + lit] += share;
          }
        }
      }
    }
  }

  /// Eine Wabenzeile, die kleiner als ein Pixel ist: Jede Wabe wirft
  /// ihre ganze Fläche bilinear auf die vier Pixel um ihren Mittelpunkt.
  /// Bilinear und nicht in EIN Pixel, weil die Waben sonst je nach
  /// Rundung mal zusammenklumpen und mal nicht — die Deckung fleckte
  /// dann sichtbar (gemessen: 42,3 % statt 43,5 % bei 47,8 % Wahrheit).
  ///
  /// Alles, was für die ganze Zeile gilt, ist hier schon ausgerechnet;
  /// die Spaltenschleife ist der heiße Pfad des Übersichtszooms.
  void _addSmallRow(
    ForestGrid grid,
    Int8List bandOf,
    int rowBase,
    int hx0,
    int hx1, {
    required double cxFirst,
    required double wPx,
    required double area,
    required double yMid,
    required AmpelLevelGrid? highlight,
    required int? ampelRow,
    required double lonFirst,
    required double lonStep,
  }) {
    final width = window.width;
    final rows = window.height;
    final fy = yMid - 0.5;
    final rowA = fy.floor();
    final ty = fy - rowA;
    final weightA = (1 - ty) * area * _coverageUnit;
    final weightB = ty * area * _coverageUnit;
    final hasA = rowA >= 0 && rowA < rows;
    final hasB = rowA + 1 >= 0 && rowA + 1 < rows;
    if (!hasA && !hasB) return;
    final offsetA = rowA * width;
    final offsetB = (rowA + 1) * width;

    var cx = cxFirst - 0.5; // Pixelmitten-Koordinaten
    var lonC = lonFirst;
    for (var hx = hx0; hx <= hx1; hx++, cx += wPx, lonC += lonStep) {
      final band = bandOf[grid.values[rowBase + hx]];
      if (band < 0) continue;
      final lit = _litBand(highlight, ampelRow, lonC);
      final px = cx.floor();
      if (px < -1 || px >= width) continue;
      final tx = cx - px;
      // Vier Ecken, und bei leuchtenden Waben jede davon zweimal:
      // Klassenband und Stufenband, mit demselben gerundeten Betrag.
      void put(int offset, double weight) {
        final share = weight.round();
        _bands[offset + band] += share;
        if (lit >= 0) _bands[offset + lit] += share;
      }

      if (hasA) {
        if (px >= 0) put((offsetA + px) * bandCount, weightA * (1 - tx));
        if (px + 1 < width) {
          put((offsetA + px + 1) * bandCount, weightA * tx);
        }
      }
      if (hasB) {
        if (px >= 0) put((offsetB + px) * bandCount, weightB * (1 - tx));
        if (px + 1 < width) {
          put((offsetB + px + 1) * bandCount, weightB * tx);
        }
      }
    }
  }

  /// Das LEUCHT-Band einer Wabe, oder -1 für „leuchtet nicht": Wo das
  /// Wetter mindestens „verhalten" ist, zahlt die Wabe zusätzlich zu
  /// ihrem Klassenband in Band 3 bzw. 4 ein. Ohne [highlight] leuchtet
  /// nichts.
  int _litBand(AmpelLevelGrid? highlight, int? ampelRow, double lon) {
    if (highlight == null || ampelRow == null) return -1;
    final column = highlight.columnAt(lon);
    if (column == null) return -1;
    return switch (highlight.levelAtCell(ampelRow, column)) {
      AmpelLevel.verhalten => _bandVerhalten,
      AmpelLevel.guenstig => _bandGuenstig,
      // „ungünstig" und „keine Aussage" sind hier dasselbe: Die Wabe
      // bleibt Wald. Auf der Karte heißt Nicht-Leuchten also weder
      // „schlecht" noch „unbekannt" — genau deshalb steht die
      // Abdeckungsgrenze (nur Deutschland) im Blatt.
      _ => -1,
    };
  }

  /// Deckung → Bild: Farbe des deckungsstärksten Bandes, Deckkraft nach
  /// Gesamtdeckung.
  ///
  /// Die Farbe eines gemischten Pixels ist das MEHRHEITSBAND, nicht ein
  /// gemittelter Farbton: Ein Mischton stünde in keiner Legende, und
  /// eine abgewählte Klasse (#231) darf nicht durch die Hintertür wieder
  /// auftauchen. Bei Gleichstand gewinnt das frühere Band (Laub vor
  /// Misch vor Nadel vor den Leuchtbändern) — irgendeine feste
  /// Reihenfolge braucht es, damit dasselbe Gitter dasselbe Bild ergibt.
  ///
  /// [colours] und [alphas] haben je [bandCount] Einträge: Die
  /// Kombi-Ebene malt ihre Waldbänder schwächer als ihre Leuchtbänder,
  /// also gehört die Deckkraft ans Band und nicht ans Bild.
  Uint8List resolve(List<Color> colours, List<int> alphas) {
    final width = window.width;
    final rows = window.height;
    final red = Uint8List(bandCount);
    final green = Uint8List(bandCount);
    final blue = Uint8List(bandCount);
    for (var i = 0; i < bandCount; i++) {
      red[i] = (colours[i].r * 255).round();
      green[i] = (colours[i].g * 255).round();
      blue[i] = (colours[i].b * 255).round();
    }

    final raw = Uint8List(rows * (width * 4 + 1));
    var cursor = 0;
    var offset = 0;
    for (var y = 0; y < rows; y++) {
      raw[cursor++] = 0; // Filter „None"
      for (var x = 0; x < width; x++) {
        var total = 0;
        var best = 0;
        var bestValue = 0;
        for (var band = 0; band < bandCount; band++) {
          final value = _bands[offset + band];
          total += value;
          if (value > bestValue) {
            bestValue = value;
            best = band;
          }
        }
        offset += bandCount;
        if (total == 0) {
          cursor += 4; // durchsichtig: kein Wald, keine Daten, abgewählt
          continue;
        }
        final alpha = alphas[best];
        raw[cursor++] = red[best];
        raw[cursor++] = green[best];
        raw[cursor++] = blue[best];
        raw[cursor++] = total >= _coverageUnit
            ? alpha
            : (alpha * total / _coverageUnit).round();
      }
    }
    return raw;
  }

  /// Dasselbe für die Kombi-Ebene, aber mit ZWEI Gewinnern je Pixel:
  /// der deckungsstärksten Waldklasse (Bänder 0–2) und der
  /// deckungsstärksten Wetterstufe (Bänder 3–4 gegen den nicht
  /// leuchtenden Rest). Erst das Paar ergibt die Farbe — nachgeschlagen
  /// in [AppColors.ampelCombined], nicht gemischt.
  ///
  /// Warum nicht neun Bänder für die neun Zustände: Klasse und Stufe
  /// sind unabhängig, also reichen 3 + 2. Neun kosteten beim größten
  /// Fenster 41 statt 23 MB Puffer, und die Genauigkeit wäre dieselbe.
  ///
  /// Bei Gleichstand gewinnt der RUHIGERE Zustand (kein Leuchten vor
  /// „verhalten" vor „günstig"), wie bei den Klassen das frühere Band:
  /// Irgendeine feste Ordnung braucht es, damit dasselbe Gitter dasselbe
  /// Bild ergibt — und ein halb leuchtendes Pixel soll eher zu wenig
  /// versprechen als zu viel.
  Uint8List resolveCombined() {
    final width = window.width;
    final rows = window.height;

    // Neun Farben (3 Klassen × [Wald, verhalten, günstig]) und ihre
    // Deckkraft, einmal als Bytes: Millionen Pixel, neun Einträge.
    final red = Uint8List(9);
    final green = Uint8List(9);
    final blue = Uint8List(9);
    final alphas = Uint8List(9);
    for (var band = 0; band < 3; band++) {
      final (mild, strong) = AppColors.ampelCombined[band];
      final colours = [_forestBandColours[band], mild, strong];
      const levelAlphas = [
        forestCombinedAlpha,
        ampelVerhaltenAlpha,
        ampelGuenstigAlpha,
      ];
      for (var level = 0; level < 3; level++) {
        final i = band * 3 + level;
        red[i] = (colours[level].r * 255).round();
        green[i] = (colours[level].g * 255).round();
        blue[i] = (colours[level].b * 255).round();
        alphas[i] = levelAlphas[level];
      }
    }

    final raw = Uint8List(rows * (width * 4 + 1));
    var cursor = 0;
    var offset = 0;
    for (var y = 0; y < rows; y++) {
      raw[cursor++] = 0; // Filter „None"
      for (var x = 0; x < width; x++) {
        var total = 0;
        var best = 0;
        var bestValue = 0;
        for (var band = 0; band < 3; band++) {
          final value = _bands[offset + band];
          total += value;
          if (value > bestValue) {
            bestValue = value;
            best = band;
          }
        }
        final verhalten = _bands[offset + _bandVerhalten];
        final guenstig = _bands[offset + _bandGuenstig];
        offset += bandCount;
        if (total == 0) {
          cursor += 4; // durchsichtig: kein Wald, keine Daten, abgewählt
          continue;
        }
        // Was NICHT leuchtet, ist der Rest der Klassendeckung — die
        // Leuchtbänder sind eine Teilmenge, kein Ersatz.
        final plain = total - verhalten - guenstig;
        final level = (plain >= verhalten && plain >= guenstig)
            ? 0
            : (verhalten >= guenstig ? 1 : 2);
        final i = best * 3 + level;
        raw[cursor++] = red[i];
        raw[cursor++] = green[i];
        raw[cursor++] = blue[i];
        raw[cursor++] = total >= _coverageUnit
            ? alphas[i]
            : (alphas[i] * total / _coverageUnit).round();
      }
    }
    return raw;
  }
}

/// Die drei Klassenfarben in Bandreihenfolge.
const _forestBandColours = [
  AppColors.forestBroadleaf,
  AppColors.forestMixed,
  AppColors.forestConifer,
];
