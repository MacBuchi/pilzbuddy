// Das Baumarten-Gitter (#227): ein Byte je Zelle, wie es
// `tool/forest_species.py` aus der DLR-Karte „Tree Species Germany"
// (2022, CC BY 4.0) baut. Nur Deutschland — die Nennung der Quelle und
// der Abdeckung steht im Wald-Blatt.
//
// Reines Dart ohne Flutter, wie `forest_grid.dart` und aus demselben
// Grund: Ein falsch ausgepacktes Gitter fällt sonst erst als
// merkwürdiger Text auf dem Gerät auf.
//
// **Dasselbe Hex-Gitter wie [ForestGrid].** Gleiche Bounding Box,
// gleiche Maße, gleiche Schrittweiten — deshalb rechnet dieses Modul
// die Zuordnung Punkt → Zelle NICHT selbst, sondern ruft
// `hexNearestCell` aus `forest_grid.dart`. Zwei Wege zur Zelle wären
// zwei Wege, die auseinanderlaufen können; das Werkzeug hält die
// Gleichheit der Maße auf seiner Seite fest.
//
// **Kein Zeilen-Delta**, anders als bei Wald und Regen: An Klassen ohne
// Gefälle verschlechtert das Delta die Kompression (gemessen 1,98 gegen
// 2,42 MB, #227). Das Manifest sagt `"encoding": "gzip"`, und dieser
// Leser prüft das — ein Gitter mit anderer Kodierung wird abgelehnt
// statt still falsch ausgepackt.
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'forest_grid.dart' show hexNearestCell;

/// Laubarten in der Reihenfolge ihrer Halbbyte-Werte (1..4).
enum Broadleaf { beech, oak, birch, alder }

/// Nadelarten in der Reihenfolge ihrer Halbbyte-Werte (1..5).
enum Conifer { spruce, pine, fir, douglas, larch }

extension BroadleafName on Broadleaf {
  String get label => switch (this) {
        Broadleaf.beech => 'Buche',
        Broadleaf.oak => 'Eiche',
        Broadleaf.birch => 'Birke',
        Broadleaf.alder => 'Erle',
      };
}

extension ConiferName on Conifer {
  String get label => switch (this) {
        Conifer.spruce => 'Fichte',
        Conifer.pine => 'Kiefer',
        Conifer.fir => 'Tanne',
        Conifer.douglas => 'Douglasie',
        Conifer.larch => 'Lärche',
      };
}

/// Was an einem Punkt benennbar ist. Mindestens eines der beiden ist
/// gesetzt — sonst gibt [ForestSpeciesGrid.at] `null` zurück.
typedef ForestSpeciesNames = ({Broadleaf? broadleaf, Conifer? conifer});

/// Zelle trägt nur Kronenverlust. **Reserviert, noch nicht angezeigt**
/// (#227): Wo der Kahlschlag anhält, sagt das neuere Waldgitter von 2024
/// ohnehin „kein Wald"; ein Verlust von 2022, der heute eine junge Kultur
/// ist, wäre ein Fehlalarm. Der Code steht im Vertrag, damit die Auskunft
/// später ohne neues Gitterformat dazukommen kann.
const speciesCanopyLoss = 0xFE;

/// „Hier wissen wir nichts" — außerhalb Deutschlands, oder zu wenig Baum
/// in der Zelle (die Schwelle sitzt im Werkzeug, siehe `min_tree_share`).
const speciesNoData = 0xFF;

class ForestSpeciesGrid {
  const ForestSpeciesGrid({
    required this.values,
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.referenceYear,
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

  /// Bezugsjahr der Quelle, für das „Stand" in der Zeile.
  final int referenceYear;

  /// Hexbreite in Grad Länge und Zeilenschritt in Grad Breite —
  /// identisch mit denen des Waldgitters.
  final double hexLonStep;
  final double hexLatStep;

  /// Packt aus, was `tool/forest_species.py` geschrieben hat: schlicht
  /// gzip, ohne Zeilen-Delta.
  factory ForestSpeciesGrid.decode(
    List<int> gzipped, {
    required int width,
    required int height,
    required double west,
    required double east,
    required double north,
    required double south,
    required int referenceYear,
    required double hexLonStep,
    required double hexLatStep,
  }) {
    final flat = GZipDecoder().decodeBytes(gzipped);
    if (flat.length != width * height) {
      throw FormatException(
          'Artengitter hat ${flat.length} Bytes, erwartet ${width * height}');
    }
    return ForestSpeciesGrid(
      values: Uint8List.fromList(flat),
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

  /// Das rohe Byte an einem Punkt, oder `null` außerhalb des Gitters.
  int? byteAt(double lat, double lon) {
    if (lat > north || lat < south || lon < west || lon > east) return null;
    final cell = hexNearestCell(
      u: (lon - west) / hexLonStep,
      v: (north - lat) / hexLatStep,
      width: width,
      height: height,
    );
    if (cell == null) return null;
    return values[cell.$2 * width + cell.$1];
  }

  /// Die benennbaren Arten an einem Punkt — `null`, wenn es nichts zu
  /// benennen gibt (außerhalb, keine Daten, nur Kronenverlust, oder
  /// Bäume ohne bestimmbare Art).
  ForestSpeciesNames? at(double lat, double lon) {
    final byte = byteAt(lat, lon);
    // Die beiden Sonderwerte werden HEUTE schon von der
    // Halbbyte-Prüfung weiter unten verworfen (0xFE und 0xFF haben
    // Halbbytes 14/15, die es nicht gibt) — die Gegenprobe hat das
    // gezeigt. Sie stehen trotzdem hier: Sie sind der Vertrag mit
    // `tool/forest_species.py`, und dass sie mit keiner echten
    // Kombination kollidieren, ist eine Zusicherung mit eigenem Test —
    // auf beiden Seiten.
    if (byte == null || byte == speciesNoData || byte == speciesCanopyLoss) {
      return null;
    }
    final high = byte >> 4;
    final low = byte & 0x0F;
    final broadleaf =
        high >= 1 && high <= Broadleaf.values.length
            ? Broadleaf.values[high - 1]
            : null;
    final conifer = low >= 1 && low <= Conifer.values.length
        ? Conifer.values[low - 1]
        : null;
    if (broadleaf == null && conifer == null) return null;
    return (broadleaf: broadleaf, conifer: conifer);
  }
}

/// Die Aufzählung für die Zeile — „Fichte und Buche", „Kiefer".
///
/// Die REIHENFOLGE richtet sich nach dem Nadelanteil aus dem Waldgitter,
/// der in derselben Kachel schon dasteht: Im überwiegenden Nadelwald
/// zuerst der Nadelbaum, sonst zuerst der Laubbaum. Eine feste
/// Reihenfolge läse sich in der einen Hälfte der Fälle verkehrt herum
/// („Fichte und Buche" für einen Buchenwald mit ein paar Fichten).
String speciesPhrase(ForestSpeciesNames names, {int? coniferPercent}) {
  final parts = (coniferPercent ?? 0) >= 50
      ? [names.conifer?.label, names.broadleaf?.label]
      : [names.broadleaf?.label, names.conifer?.label];
  final named = parts.whereType<String>().toList();
  return named.join(' und ');
}

/// Die Gattungen, die das Rückfall-Gitter (#624, ForestPaths) nennen
/// DARF — gemessen gegen die DLR-Karte: Fichte 76 % (bayerische Alpen
/// 97 %), Buche 91 % (97 %), Kiefer 76 %. Lärche erkennt die Karte
/// praktisch nie, Eiche kaum; beide kommen nie aus diesem Gitter.
///
/// Das Werkzeug schreibt ohnehin nichts anderes hinein. Die Liste steht
/// trotzdem hier und wird beim Lesen angewandt: Ein Asset, das diese
/// Zusage bricht, sähe sonst wie eine Messung aus.
const estimatedBroadleaves = {Broadleaf.beech};
const estimatedConifers = {Conifer.spruce, Conifer.pine};

/// Was an einem Punkt über die Bäume gesagt werden kann — und woher.
///
/// [estimated] heißt: aus dem Rückfall-Gitter. Die Zeile sagt dann, dass
/// es eine Satellitenschätzung ist und Lärche darin nicht vorkommen
/// kann; ohne den Zusatz läse sich „Fichte" als „hier keine Lärche".
typedef ForestSpeciesReading = ({
  ForestSpeciesNames names,
  bool estimated,
  int referenceYear,
});

/// Die EINE Vorrangregel zwischen den beiden Gittern.
///
/// Das DLR-Gitter gewinnt, sobald es an dem Punkt IRGENDETWAS sagt —
/// auch „Bäume ohne nennbare Art" (0x00) und „nur Kronenverlust"
/// (0xFE). Dort springt das Rückfall-Gitter NICHT ein: Die bessere
/// Quelle hat gesprochen, und eine Schätzung von 2020 über einer
/// Kahlfläche von 2022 wäre ein Rückschritt. Nur wo es schweigt (0xFF
/// oder außerhalb), fragt die Zeile das Rückfall-Gitter — beschränkt
/// auf [estimatedBroadleaves] und [estimatedConifers].
ForestSpeciesReading? forestSpeciesReadingAt(
  ForestSpeciesGrid? measured,
  ForestSpeciesGrid? fallback,
  double lat,
  double lon,
) {
  final byte = measured?.byteAt(lat, lon);
  if (measured != null && byte != null && byte != speciesNoData) {
    final names = measured.at(lat, lon);
    return names == null
        ? null
        : (
            names: names,
            estimated: false,
            referenceYear: measured.referenceYear,
          );
  }
  final raw = fallback?.at(lat, lon);
  if (fallback == null || raw == null) return null;
  final broadleaf = estimatedBroadleaves.contains(raw.broadleaf)
      ? raw.broadleaf
      : null;
  final conifer =
      estimatedConifers.contains(raw.conifer) ? raw.conifer : null;
  if (broadleaf == null && conifer == null) return null;
  return (
    names: (broadleaf: broadleaf, conifer: conifer),
    estimated: true,
    referenceYear: fallback.referenceYear,
  );
}
