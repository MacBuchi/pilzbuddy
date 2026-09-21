// Gemeldete Fundorte aus GBIF (#467): das Asset, das
// `tool/gbif_finds.py` aus dem lokalen GBIF-Download baut — je Zeile ein
// ORT, an dem eine unserer Arten gemeldet wurde, mit der Unschärfe, die
// der Melder selbst angegeben hat.
//
// Reines Dart ohne Flutter, wie `forest_grid.dart` und aus demselben
// Grund: Ein falsch ausgepacktes Asset soll im Test auffallen, nicht als
// Scheibe am falschen Ort auf dem Gerät.
//
// **Was eine Zeile sagt — und was nicht.** „Hier hat jemand diese Art
// gemeldet", mit einer Unschärfe von 4 m bis 10 km. Kein Fundort im Sinn
// eines Spots (`kNearbySpotMeters` sind 20 m). Die drei Länder melden
// grundverschieden (gemessen 2026-09-21, siehe Werkzeug): Deutschland
// scharfe Punkte, die Schweiz Kilometerquadrate (3535 m, die halbe
// Diagonale von 5 km), Österreich Rasterpunkte OHNE Angabe. Deshalb
// trägt jede Zeile ihre Unschärfe mit, und die Karte zeichnet Scheiben
// in genau dieser Größe — eine unbekannte Unschärfe wird wie ein
// Quadrat gezeichnet ([unknownUncertaintyM]), weil die größere Scheibe
// die harmlose Fehlerrichtung ist.
//
// **Gruppiert, nicht einzeln.** Elf Meldungen auf einem Rasterpunkt sind
// EINE Zeile mit `count` 11 — sonst malte die Karte elf deckungsgleiche
// Scheiben. Und **keine Meldernamen**: `recordedBy` ist eine Person, das
// Asset liegt in jedem APK.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Eine Art im Asset — der deutsche Name ist der aus `kBekannteArten`,
/// so lässt sich die Zeile ohne Nachschlagen dem Filter und der
/// Ampel-Klasse zuordnen.
typedef GbifSpecies = ({String name, String sci, int observations});

/// Ein Quell-Datensatz — die CC-BY-Namensnennung.
typedef GbifDataset = ({String key, String title, int observations});

/// Was im Umkreis eines Punkts gemeldet ist: eine Zeile je Art.
typedef GbifAround = ({
  String species,
  int observations,
  int places,
  int? newestYear,
});

/// Was über EINE Art im ganzen Bestand steht — die Zeile der
/// Detailseite (#511). Dieselben drei Zahlen wie in [GbifAround], nur
/// ohne Umkreis.
typedef GbifSpeciesTotals = ({
  int observations,
  int places,
  int? newestYear,
});

/// Meter je Grad Breite — grob, wie überall auf der Karte.
const _metersPerDegree = 111320.0;

class GbifFinds {
  const GbifFinds({
    required this.speciesIndex,
    required this.latQ,
    required this.lonQ,
    required this.uncertaintyM,
    required this.count,
    required this.yearOffset,
    required this.species,
    required this.datasets,
    required this.countries,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.observations,
    required this.unknownUncertaintyM,
    required this.doi,
    required this.fetchedOn,
  });

  /// Die Spalten, je [length] Einträge — genau die Reihenfolge des
  /// Werkzeugs: Art, Breite, Länge, Unschärfe, Zähler, Jahr.
  final Uint8List speciesIndex;
  final Uint16List latQ;
  final Uint16List lonQ;

  /// In Metern; 0 heißt „nicht angegeben" — siehe [uncertaintyAt].
  final Uint16List uncertaintyM;
  final Uint8List count;

  /// Jüngstes Jahr minus 1900; 0 heißt unbekannt.
  final Uint8List yearOffset;

  final List<GbifSpecies> species;
  final List<GbifDataset> datasets;
  final Map<String, int> countries;

  /// Die Quantisierungs-Box in Grad (die des Waldgitters).
  final double west;
  final double east;
  final double north;
  final double south;

  /// Meldungen insgesamt (vor dem Gruppieren).
  final int observations;

  /// So groß zeichnet die Karte eine Zeile ohne Unschärfe-Angabe.
  final int unknownUncertaintyM;

  final String? doi;
  final String? fetchedOn;

  int get length => speciesIndex.length;

  double latAt(int i) => north - latQ[i] / 65535 * (north - south);
  double lonAt(int i) => west + lonQ[i] / 65535 * (east - west);

  /// Die Unschärfe, mit der die Zeile GEZEICHNET wird — unbekannt zählt
  /// wie ein Quadrat.
  int uncertaintyAt(int i) =>
      uncertaintyM[i] == 0 ? unknownUncertaintyM : uncertaintyM[i];

  bool uncertaintyKnownAt(int i) => uncertaintyM[i] != 0;

  int? yearAt(int i) => yearOffset[i] == 0 ? null : 1900 + yearOffset[i];

  /// Packt aus, was `tool/gbif_finds.py` geschrieben hat.
  ///
  /// Lehnt jedes andere Format ab: Ein Asset, das neuer ist als die App,
  /// wird nicht gelesen statt falsch gelesen — bei Spalten fester Breite
  /// sähe ein verschobenes Byte überall plausibel aus.
  factory GbifFinds.decode(List<int> gzipped, String manifestJson) {
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
    if (manifest['encoding'] != 'gzip-columns') {
      throw FormatException('Unbekannte Kodierung ${manifest['encoding']}');
    }
    const expectedColumns = ['species', 'lat', 'lon', 'unc', 'count', 'year'];
    final columns = (manifest['columns'] as List).cast<String>();
    if (columns.join(',') != expectedColumns.join(',')) {
      throw FormatException('Unerwartete Spalten $columns');
    }
    final n = manifest['records'] as int;
    final flat = Uint8List.fromList(GZipDecoder().decodeBytes(gzipped));
    if (flat.length != n * 9) {
      throw FormatException(
          'Fundorte haben ${flat.length} Bytes, erwartet ${n * 9}');
    }
    // Die u16-Spalten liegen NICHT ausgerichtet (die u8-Spalte davor
    // hat ungerade Länge, wenn n ungerade ist) — deshalb kopieren statt
    // `buffer.asUint16List` mit Versatz, das würfe auf manchen
    // Plattformen.
    final view = ByteData.view(flat.buffer);
    Uint16List u16(int offset) {
      final out = Uint16List(n);
      for (var i = 0; i < n; i++) {
        out[i] = view.getUint16(offset + 2 * i, Endian.little);
      }
      return out;
    }

    final speciesIndex = flat.sublist(0, n);
    final latQ = u16(n);
    final lonQ = u16(3 * n);
    final unc = u16(5 * n);
    final count = flat.sublist(7 * n, 8 * n);
    final year = flat.sublist(8 * n, 9 * n);

    final speciesTable = [
      for (final s in (manifest['species'] as List).cast<Map<String, dynamic>>())
        (
          name: s['name'] as String,
          sci: s['sci'] as String,
          observations: s['observations'] as int,
        ),
    ];
    for (final idx in speciesIndex) {
      if (idx >= speciesTable.length) {
        throw FormatException('Artindex $idx ohne Eintrag im Manifest');
      }
    }
    return GbifFinds(
      speciesIndex: speciesIndex,
      latQ: latQ,
      lonQ: lonQ,
      uncertaintyM: unc,
      count: count,
      yearOffset: year,
      species: speciesTable,
      datasets: [
        for (final d in (manifest['datasets'] as List? ?? const []).cast<Map<String, dynamic>>())
          (
            key: d['key'] as String,
            title: d['title'] as String,
            observations: d['observations'] as int,
          ),
      ],
      countries: {
        for (final e in (manifest['countries'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: e.value as int,
      },
      west: (manifest['west'] as num).toDouble(),
      east: (manifest['east'] as num).toDouble(),
      north: (manifest['north'] as num).toDouble(),
      south: (manifest['south'] as num).toDouble(),
      observations: manifest['observations'] as int,
      unknownUncertaintyM:
          manifest['unknown_uncertainty_drawn_as_m'] as int? ?? 3535,
      doi: manifest['doi'] as String?,
      fetchedOn: manifest['fetched_on'] as String?,
    );
  }

  /// Was im Umkreis von [radiusM] um einen Punkt gemeldet ist — eine
  /// Zeile je Art, die häufigste zuerst.
  ///
  /// **Eine Meldung zählt, wenn ihre FLÄCHE in den Umkreis reicht**
  /// (Abstand ≤ Radius + Unschärfe), nicht nur ihr Mittelpunkt: Ein
  /// Schweizer Quadrat mit Mittelpunkt 4 km entfernt kann den Punkt
  /// enthalten. Das ist die weite Lesart, und sie ist hier die richtige —
  /// die Liste sagt „in dieser Gegend gemeldet", nicht „an dieser
  /// Stelle", und der Text des Blatts sagt das mit.
  List<GbifAround> around(double lat, double lon, {required double radiusM}) {
    final cosLat = math.cos(lat * math.pi / 180);
    final observations = <int, int>{};
    final places = <int, int>{};
    final newest = <int, int?>{};
    for (var i = 0; i < length; i++) {
      final dLat = (latAt(i) - lat) * _metersPerDegree;
      final dLon = (lonAt(i) - lon) * _metersPerDegree * cosLat;
      final reach = radiusM + uncertaintyAt(i);
      if (dLat * dLat + dLon * dLon > reach * reach) continue;
      final s = speciesIndex[i];
      observations[s] = (observations[s] ?? 0) + count[i];
      places[s] = (places[s] ?? 0) + 1;
      final year = yearAt(i);
      if (year != null && (newest[s] == null || year > newest[s]!)) {
        newest[s] = year;
      }
    }
    final rows = [
      for (final e in observations.entries)
        (
          species: species[e.key].name,
          observations: e.value,
          places: places[e.key]!,
          newestYear: newest[e.key],
        ),
    ]..sort((a, b) {
        final byCount = b.observations.compareTo(a.observations);
        return byCount != 0 ? byCount : a.species.compareTo(b.species);
      });
    return rows;
  }

  /// Was zu [species] im ganzen Bestand gemeldet ist — `null`, wenn die
  /// Art im Asset gar nicht vorkommt.
  ///
  /// **`null` und „0 Meldungen" sind zwei verschiedene Auskünfte**, und
  /// beide kommen vor: Das Asset trägt nur Arten mit wissenschaftlichem
  /// Namen, eine Art ohne zweifelsfreie GBIF-Zuordnung steht dort nie. Die
  /// Seite muss das anders sagen als „hier hat niemand gemeldet" —
  /// sonst liest sich eine fehlende Zuordnung als Aussage über den Pilz.
  ///
  /// Die Meldungen SELBST kommen aus der Spalte, nicht aus dem
  /// Manifest-Zähler: Der zählt vor dem Zuschnitt auf die Box und wäre
  /// damit eine andere Zahl als die, die die Karte zeichnet.
  GbifSpeciesTotals? totalsFor(String species) {
    final index = this.species.indexWhere((s) => s.name == species);
    if (index < 0) return null;
    var observations = 0;
    var places = 0;
    int? newest;
    for (var i = 0; i < length; i++) {
      if (speciesIndex[i] != index) continue;
      observations += count[i];
      places++;
      final year = yearAt(i);
      if (year != null && (newest == null || year > newest)) newest = year;
    }
    return (observations: observations, places: places, newestYear: newest);
  }
}
