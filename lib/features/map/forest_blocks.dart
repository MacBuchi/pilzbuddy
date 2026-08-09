// Die nachladbare feine Waldkarte (#253, Stufe 3): Katalog, Blockverbund
// und die kombinierte Sicht mit dem 250-m-Asset als Rückfalllinie.
//
// CI schneidet das 100-m-Hex-Gitter in ~2°-Blöcke — an GERADEN Hexzeilen
// und ganzen Spalten, damit jeder Block für sich ein gültiges [ForestGrid]
// mit denselben Mittelpunkten ist: Sein Anker ist der globale Anker plus
// Indexversatz, die Formel der App ändert sich nicht. Genau darauf baut
// dieser Verbund: Er rechnet auf dem GLOBALEN Gitter (eine Zuordnung,
// `hexNearestCell` aus `forest_grid.dart`) und schlägt das Byte im
// jeweiligen Block nach — der 1-km-Umkreis an einer Blocknaht zählt damit
// ehrlich beide Seiten, statt am Rand des einen Blocks zu verhungern.
//
// Fehlt ein benötigter Block (nicht geladen, Download gescheitert),
// antwortet der Verbund mit `null`, und [ForestView] fällt still auf das
// eingebaute Asset zurück — die Regel der ganzen Karte: nachgeladene
// Stufen sind eine Zugabe, kein Kernpfad.
//
// Reines Dart ohne Flutter, wie `forest_grid.dart` und aus demselben
// Grund: Die Zuordnung Punkt → Block → Hex soll ohne Karte testbar sein.
import 'forest_fill_window.dart';
import 'forest_grid.dart';

/// Toleranz beim Abdeckungs-Test in Grad (~eine 250-m-Wabe): Grobes und
/// feines Gitter entstehen aus demselben gewarpten Raster, aber beide
/// werfen am Ost-/Südrand einen Rest unter einer Zellbreite weg — um
/// diesen Sliver dürfen sich Fenster und Blockverbund unterscheiden,
/// ohne dass die feine Karte deswegen ganz zurücktritt.
const forestBlockCoverageEps = 0.004;

/// Ein Block aus dem Katalog: Datei, Maße, Bbox, Prüfsumme — plus sein
/// Indexversatz [hx0]/[hy0] im globalen Gitter, den der Katalog aus der
/// Bbox zurückrechnet.
class ForestBlockInfo {
  const ForestBlockInfo({
    required this.file,
    required this.width,
    required this.height,
    required this.west,
    required this.north,
    required this.east,
    required this.south,
    required this.bytes,
    required this.sha256,
    required this.hx0,
    required this.hy0,
  });

  final String file;
  final int width;
  final int height;
  final double west;
  final double north;
  final double east;
  final double south;

  /// Erwartete Dateigröße und Prüfsumme — der Download wird dagegen
  /// verifiziert, BEVOR er auf Platte landet oder dekodiert wird.
  final int bytes;
  final String sha256;

  /// Spalten-/Zeilenversatz im globalen Gitter. [hy0] ist per Bauregel
  /// GERADE (odd-r-Parität!) — der Katalog-Parser prüft das.
  final int hx0;
  final int hy0;
}

/// Der Katalog `forest_blocks.json` vom festen Release-Tag `forest-data`.
class ForestBlockCatalog {
  const ForestBlockCatalog({
    required this.referenceYear,
    required this.hexLonStep,
    required this.hexLatStep,
    required this.west,
    required this.north,
    required this.gridWidth,
    required this.gridHeight,
    required this.blocks,
  });

  final int referenceYear;
  final double hexLonStep;
  final double hexLatStep;

  /// Anker und Maße des GLOBALEN feinen Gitters, aus den Blöcken
  /// zusammengesetzt: Die Blöcke kacheln es lückenlos.
  final double west;
  final double north;
  final int gridWidth;
  final int gridHeight;

  final List<ForestBlockInfo> blocks;

  /// Ostkante/Südkante samt Hex-Überstand — dieselbe Halbspalte/Zeile,
  /// die auch `cut_blocks` den Block-Bboxen zuschlägt.
  double get east => west + (gridWidth + 0.5) * hexLonStep;
  double get south => north - (gridHeight + 1) * hexLatStep;

  /// Wie breit eine feine Wabe im geplanten Bild wäre — in Pixeln.
  double hexPixelsIn(FillWindow window) =>
      hexLonStep / (window.east - window.west) * window.width;

  /// Lohnt die feine Stufe in diesem Ausschnitt überhaupt?
  ///
  /// Erst, wenn eine 100-m-Wabe im Bild mindestens [minHexPixels] breit
  /// ist. Auf einem Hochkant-Schirm ist das etwa ab 4–5 km
  /// Sichtfensterbreite der Fall (Maßstabsleiste um 1 km), quer oder auf
  /// dem Tablet ab ~8 km.
  ///
  /// **Warum das eine Schranke braucht** (Rückfrage des Betreibers am
  /// 2026-08-09): Ohne sie hing das Nachladen allein am Schnitt mit dem
  /// Fenster. Wer mit eingeschalteter Feinstufe auf Deutschland
  /// herauszoomte, holte damit JEDEN Block des Katalogs — 30 Stück,
  /// ~26 MB — für ein Bild, das vom groben nicht zu unterscheiden ist:
  /// Eine feine Wabe misst dort 0,06 px, sie verschwindet also in
  /// derselben Deckung, die das 250-m-Asset ohnehin liefert. Die feinen
  /// Daten sind erst dort eine Information, wo man sie sehen kann.
  bool paysOffIn(FillWindow window) => hexPixelsIn(window) >= minHexPixels;

  /// Die Schwelle aus [paysOffIn], in Bildpixeln je feiner Wabe.
  ///
  /// **10 und nicht knapp über 1** (Betreiber, 2026-08-09: „das kannst
  /// du locker auf 10 Pixel aufweiten"): Sichtbar ist eine Wabe schon ab
  /// zwei, aber sichtbar heißt nicht nützlich. Bei zwei Pixeln steht
  /// neben ihr eine 250-m-Wabe aus dem Asset mit fünf — die feine Stufe
  /// zeigt dort dasselbe Bild und kostet nur Downloads. Bei zehn
  /// Bildpixeln (≈ 20–30 Bildschirmpixel) sieht man tatsächlich, was sie
  /// besser weiß: den Laubstreifen am Bach, den Fichtenriegel im
  /// Buchenhang. Das ist der Zoom, in dem jemand einen Waldrand
  /// absucht — und genau dann darf sie kosten.
  static const minHexPixels = 10.0;

  /// `null` bei allem, was dieser Stand der App nicht versteht — ein
  /// unbekanntes `lattice` heißt, der Katalog ist neuer als die App;
  /// dann lieber keine feine Stufe als eine falsch zugeordnete
  /// (dieselbe Regel wie beim Asset-Manifest).
  static ForestBlockCatalog? tryParse(Map<String, dynamic> json) {
    try {
      if (json['lattice'] != 'hex-odd-r') return null;
      final lonStep = (json['hex_lon_step'] as num).toDouble();
      final latStep = (json['hex_lat_step'] as num).toDouble();
      if (lonStep <= 0 || latStep <= 0) return null;
      final raw = [
        for (final entry in json['blocks'] as List)
          (
            file: (entry as Map)['file'] as String,
            width: entry['width'] as int,
            height: entry['height'] as int,
            west: (entry['west'] as num).toDouble(),
            north: (entry['north'] as num).toDouble(),
            east: (entry['east'] as num).toDouble(),
            south: (entry['south'] as num).toDouble(),
            bytes: entry['bytes'] as int,
            sha256: entry['sha256'] as String,
          ),
      ];
      if (raw.isEmpty) return null;
      var west = raw.first.west;
      var north = raw.first.north;
      for (final block in raw) {
        if (block.west < west) west = block.west;
        if (block.north > north) north = block.north;
      }
      var gridWidth = 0;
      var gridHeight = 0;
      final blocks = <ForestBlockInfo>[];
      for (final block in raw) {
        final hx0 = ((block.west - west) / lonStep).round();
        final hy0 = ((north - block.north) / latStep).round();
        // Die Bauregel aus `cut_blocks`: Schnitt an GERADEN Zeilen. Ein
        // Katalog, der sie bricht, würde die odd-r-Parität kippen und
        // jede zweite Zeile um eine halbe Wabe versetzen — lieber gar
        // keine feine Stufe.
        if (hy0.isOdd || block.width < 1 || block.height < 1) return null;
        blocks.add(ForestBlockInfo(
          file: block.file,
          width: block.width,
          height: block.height,
          west: block.west,
          north: block.north,
          east: block.east,
          south: block.south,
          bytes: block.bytes,
          sha256: block.sha256,
          hx0: hx0,
          hy0: hy0,
        ));
        if (hx0 + block.width > gridWidth) gridWidth = hx0 + block.width;
        if (hy0 + block.height > gridHeight) gridHeight = hy0 + block.height;
      }
      return ForestBlockCatalog(
        referenceYear: json['reference_year'] as int,
        hexLonStep: lonStep,
        hexLatStep: latStep,
        west: west,
        north: north,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        blocks: blocks,
      );
    } catch (_) {
      // Ein Katalog, den wir nicht verstehen, ist kein Grund für eine
      // Fehlermeldung — dann gibt es eben keine feine Stufe.
      return null;
    }
  }

  /// Blöcke, deren INDEX-Fläche die Box schneidet — die Index-Fläche,
  /// nicht die Katalog-Bbox: Letztere trägt den Hex-Überstand und würde
  /// Nachbarn hereinziehen, deren Waben die Box gar nicht berühren.
  List<ForestBlockInfo> blocksIntersecting({
    required double west,
    required double east,
    required double north,
    required double south,
  }) =>
      [
        for (final block in blocks)
          if (this.west + block.hx0 * hexLonStep < east &&
              this.west + (block.hx0 + block.width) * hexLonStep > west &&
              this.north - block.hy0 * hexLatStep > south &&
              this.north - (block.hy0 + block.height) * hexLatStep < north)
            block,
      ];
}

/// Der Verbund aus Katalog und den GELADENEN Blöcken.
class ForestBlockSet {
  const ForestBlockSet({required this.catalog, required this.loaded});

  final ForestBlockCatalog catalog;

  /// Dekodierte Blöcke nach Dateiname. Jeder ist ein [ForestGrid] mit
  /// Block-Anker und den globalen Hex-Schritten.
  final Map<String, ForestGrid> loaded;

  int get referenceYear => catalog.referenceYear;

  ForestBlockInfo? _blockAtCell(int hx, int hy) {
    for (final block in catalog.blocks) {
      if (hx >= block.hx0 &&
          hx < block.hx0 + block.width &&
          hy >= block.hy0 &&
          hy < block.hy0 + block.height) {
        return block;
      }
    }
    return null;
  }

  int? _byteAtCell(int hx, int hy) {
    final block = _blockAtCell(hx, hy);
    if (block == null) return null;
    final grid = loaded[block.file];
    if (grid == null) return null;
    return grid.values[(hy - block.hy0) * block.width + (hx - block.hx0)];
  }

  /// Der Rohwert unterm Punkt — `null` heißt „kann ich nicht
  /// beantworten" (außerhalb des feinen Gitters oder Block nicht
  /// geladen), NICHT „kein Wald": 0 und 255 kommen als Bytes zurück,
  /// die Deutung gehört [ForestView]. Der Unterschied trägt die
  /// Ehrlichkeit des Rückfalls — ein feines „hier steht kein Wald"
  /// darf nicht vom groben Gitter überstimmt werden.
  int? byteAtPoint(double lat, double lon) {
    if (lon < catalog.west ||
        lon > catalog.east ||
        lat > catalog.north ||
        lat < catalog.south) {
      return null;
    }
    final cell = hexNearestCell(
      u: (lon - catalog.west) / catalog.hexLonStep,
      v: (catalog.north - lat) / catalog.hexLatStep,
      width: catalog.gridWidth,
      height: catalog.gridHeight,
    );
    if (cell == null) return null;
    return _byteAtCell(cell.$1, cell.$2);
  }

  /// Der Laubfaktor-Umkreis auf dem feinen Gitter — dieselbe Rechnung
  /// wie [ForestGrid.broadleafFactorAround], über Blockgrenzen hinweg.
  /// `null`, sobald auch nur ein Hex des Umkreises in einem fehlenden
  /// Block läge: Ein halber Umkreis wäre keine kleinere Antwort,
  /// sondern eine andere.
  ({double? factor, double forestShare})? factorAround(double lat, double lon,
      {double radiusMeters = crosshairRadiusMeters}) {
    var missing = false;
    final result = hexFactorAround(
      lat: lat,
      lon: lon,
      radiusMeters: radiusMeters,
      west: catalog.west,
      north: catalog.north,
      lonStep: catalog.hexLonStep,
      latStep: catalog.hexLatStep,
      width: catalog.gridWidth,
      height: catalog.gridHeight,
      byteAt: (hx, hy) {
        final value = _byteAtCell(hx, hy);
        if (value == null) {
          missing = true;
          return forestNoData; // wird übersprungen; unten zählt `missing`
        }
        return value;
      },
    );
    if (missing) return null;
    return result;
  }

  /// Deckt der Verbund diesen Bildausschnitt vollständig ab? Nur dann
  /// malt der Zeichner fein — ein Fenster halb fein, halb grob hätte
  /// eine sichtbare Naht aus zwei Wabengrößen mitten im Bild.
  bool covers(FillWindow window) {
    if (window.west < catalog.west - forestBlockCoverageEps ||
        window.east > catalog.east + forestBlockCoverageEps ||
        window.north > catalog.north + forestBlockCoverageEps ||
        window.south < catalog.south - forestBlockCoverageEps) {
      return false;
    }
    for (final block in catalog.blocksIntersecting(
      west: window.west,
      east: window.east,
      north: window.north,
      south: window.south,
    )) {
      if (!loaded.containsKey(block.file)) return false;
    }
    return true;
  }

  /// Die geladenen Gitter unterm Fenster — die Eingabe des
  /// Mehr-Gitter-Zeichners. Reihenfolge egal: Die Blöcke überlappen
  /// nicht, jedes Hex gehört genau einem.
  List<ForestGrid> gridsFor(FillWindow window) => [
        for (final block in catalog.blocksIntersecting(
          west: window.west,
          east: window.east,
          north: window.north,
          south: window.south,
        ))
          ?loaded[block.file],
      ];
}

/// Die EINE Sicht für alle Punktabfragen (Legende, Spot-Blatt, „Was ist
/// hier?"): erst die feine Stufe, sonst das eingebaute Asset — je
/// Antwort, nicht je App-Lauf. Ein Spot außerhalb der geladenen Blöcke
/// bekommt weiter die 250-m-Antwort, der Punkt im geladenen Block die
/// feine.
class ForestView {
  const ForestView({required this.base, this.fine});

  final ForestGrid base;
  final ForestBlockSet? fine;

  /// Kam die Antwort für diesen Punkt aus der feinen Stufe? Bestimmt
  /// den ehrlichen Text daneben („Wabe ≈ 100 m" statt „≈ 250 m").
  bool usesFineAt(double lat, double lon) =>
      fine?.byteAtPoint(lat, lon) != null;

  /// Das Referenzjahr der Quelle, die HIER geantwortet hat.
  int referenceYearAt(double lat, double lon) =>
      usesFineAt(lat, lon) ? fine!.referenceYear : base.referenceYear;

  int? shareAt(double lat, double lon) {
    final value = fine?.byteAtPoint(lat, lon);
    if (value == null) return base.shareAt(lat, lon);
    if (value == forestNoData || value == forestNoForest) return null;
    return value - 1;
  }

  ForestClass? classAt(double lat, double lon) {
    final value = fine?.byteAtPoint(lat, lon);
    if (value == null) return base.classAt(lat, lon);
    if (value == forestNoData) return null;
    return classOfByte(value);
  }

  ({double? factor, double forestShare})? broadleafFactorAround(
          double lat, double lon,
          {double radiusMeters = crosshairRadiusMeters}) =>
      fine?.factorAround(lat, lon, radiusMeters: radiusMeters) ??
      base.broadleafFactorAround(lat, lon, radiusMeters: radiusMeters);
}
