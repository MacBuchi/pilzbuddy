// Schutzgebiete, in denen Pilze sammeln verboten ist (#580).
//
// Gebaut von `tool/protected_areas.py` aus OpenStreetMap (ODbL), auf
// DEMSELBEN Hex-Raster wie das Waldgitter. Zwei Abnehmer, eine Quelle:
// die Schraffur in Wald- und Ampelfläche (`forest_fill.dart`) und der
// Hinweis beim Eintragen. Kämen sie aus zwei Quellen, widersprächen sich
// Karte und Hinweis an genau den Stellen, an denen es darauf ankommt
// (#279).
//
// **Was darin steht, hat der Betreiber entschieden** (2026-09-23):
// Naturschutzgebiete, Nationalparks und Kernzonen — auch Flächen, die in
// OSM nur als Naturschutzgebiet markiert sind. NICHT
// Landschaftsschutzgebiete, Naturparks oder Natura 2000. Die Regel und
// ihre Messung stehen im Werkzeug.
//
// **Keine Bevormundung** (Betreiber): Das ist eine Auskunft, keine
// Sperre. Nichts hier verhindert einen Eintrag, und das Ampel-Banner
// bleibt, wie es ist.
//
// **Läufe statt eines Werts je Zelle.** Das volle Gitter wären 27 MB im
// Arbeitsspeicher — neben den 13 MB des Waldgitters, für eine Auskunft
// an 5,5 % der Zellen. Als Läufe je Zeile sind es 0,6 MB, und das volle
// Gitter wird nie ausgepackt, auch nicht kurz.
//
// Reines Dart ohne Flutter, wie `forest_grid.dart`: läuft im Isolate.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'forest_grid.dart' show hexNearestCell;

/// Welche Sorte Schutzgebiet.
enum ProtectedKind {
  nationalPark('Nationalpark'),
  coreZone('Kernzone'),
  natureReserve('Naturschutzgebiet');

  const ProtectedKind(this.word);

  /// Das Wort, das in der App steht — und im Manifest (`kind`).
  final String word;

  static ProtectedKind? fromWord(String word) {
    for (final kind in values) {
      if (kind.word == word) return kind;
    }
    return null;
  }
}

/// Ein Gebiet: Art und Name aus OSM (Name darf leer sein).
class ProtectedArea {
  const ProtectedArea({required this.kind, required this.name});

  final ProtectedKind kind;
  final String name;

  /// Was die App schreibt — OHNE die Art zu verdoppeln. OSM-Namen tragen
  /// sie oft schon („Naturschutzgebiet Ruggeller Riet", „Kernzone
  /// Nationalpark Schwarzwald"); „Naturschutzgebiet „Naturschutzgebiet
  /// Ruggeller Riet"" stand im ersten Entwurf genau so da.
  String get label {
    if (name.isEmpty) return kind.word;
    if (_carriesKind.hasMatch(name)) return name;
    return '${kind.word} „$name“';
  }

  /// Namen, die ihre Art schon selbst sagen — auch auf Französisch,
  /// Italienisch und Ungarisch, weil Grenzgebiete so heißen.
  static final _carriesKind = RegExp(
      r'naturschutzgebiet|nationalpark|kernzone|schutzzone|naturreservat'
      r'|r[ée]serve naturelle|riserva naturale|parco nazionale|nemzeti park'
      r'|národní park',
      caseSensitive: false);
}

/// Das Gitter der Schutzgebiete.
class ProtectedAreas {
  ProtectedAreas({
    required this.width,
    required this.height,
    required this.west,
    required this.north,
    required this.lonStep,
    required this.latStep,
    required this.rows,
    required this.areas,
    this.extract,
  });

  final int width;
  final int height;
  final double west;
  final double north;
  final double lonStep;
  final double latStep;

  /// Je Zeile die Läufe als Tripel (x0, Länge, Index) hintereinander.
  final List<Uint16List> rows;

  /// 1-basiert adressiert: Index 1 ist `areas[0]`.
  final List<ProtectedArea> areas;

  /// Stand der OSM-Auszüge (ein Datum), für die Lizenzseite.
  final String? extract;

  /// Die Wabe unter einem Punkt — dieselbe Zuordnung wie das Waldgitter.
  (int, int)? cellAt(double lat, double lon) => hexNearestCell(
        u: (lon - west) / lonStep,
        v: (north - lat) / latStep,
        width: width,
        height: height,
      );

  /// Der 1-basierte Gebietsindex einer Wabe, 0 = keins.
  int indexAtCell(int hx, int hy) {
    if (hy < 0 || hy >= height) return 0;
    final runs = rows[hy];
    for (var i = 0; i < runs.length; i += 3) {
      final x0 = runs[i];
      if (hx < x0) return 0; // Läufe sind nach x sortiert
      if (hx < x0 + runs[i + 1]) return runs[i + 2];
    }
    return 0;
  }

  /// Das Gebiet an einem Punkt, oder `null`.
  ProtectedArea? areaAt(double lat, double lon) {
    final cell = cellAt(lat, lon);
    if (cell == null) return null;
    final index = indexAtCell(cell.$1, cell.$2);
    return index == 0 ? null : areas[index - 1];
  }

  bool isProtectedAt(double lat, double lon) => areaAt(lat, lon) != null;

  /// Packt aus, was `tool/protected_areas.py` geschrieben hat. Wirft
  /// [FormatException], wenn Manifest und Daten nicht zusammenpassen —
  /// der Lader macht daraus „keine Schutzgebiete", nicht „falsche".
  factory ProtectedAreas.decode(List<int> gzipped, String manifestJson) {
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
    if (manifest['lattice'] != 'hex-odd-r' ||
        manifest['encoding'] != 'gzip-runs-u16le') {
      throw const FormatException('unbekanntes Schutzgebiets-Format');
    }
    final width = manifest['width'] as int;
    final height = manifest['height'] as int;
    final raw = GZipDecoder().decodeBytes(gzipped);
    final data = ByteData.sublistView(Uint8List.fromList(raw));
    final rows = <Uint16List>[];
    var o = 0;
    for (var y = 0; y < height; y++) {
      final n = data.getUint16(o, Endian.little);
      o += 2;
      final row = Uint16List(n * 3);
      for (var k = 0; k < n * 3; k++) {
        row[k] = data.getUint16(o, Endian.little);
        o += 2;
      }
      rows.add(row);
    }
    if (o != raw.length) {
      throw FormatException('${raw.length - o} Byte hinter der letzten Zeile');
    }
    final areas = [
      for (final entry in manifest['areas'] as List)
        ProtectedArea(
          kind: ProtectedKind.fromWord((entry as Map)['kind'] as String) ??
              ProtectedKind.natureReserve,
          name: entry['name'] as String? ?? '',
        ),
    ];
    final extracts = (manifest['extracts'] as Map?)?.values.cast<String>();
    return ProtectedAreas(
      width: width,
      height: height,
      west: (manifest['west'] as num).toDouble(),
      north: (manifest['north'] as num).toDouble(),
      lonStep: (manifest['hex_lon_step'] as num).toDouble(),
      latStep: (manifest['hex_lat_step'] as num).toDouble(),
      rows: rows,
      areas: areas,
      extract: extracts == null || extracts.isEmpty
          ? null
          : (extracts.toList()..sort()).first.split('T').first,
    );
  }
}
