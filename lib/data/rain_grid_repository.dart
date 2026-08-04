// Holt das Regen-Wertegitter aus dem Release `rain-data` und legt es auf
// Platte. Muster wie `offline_map_repository.dart` und `spot_cache.dart`:
// laden, speichern, Alter mitführen — und **still degradieren**.
//
// Still degradieren heißt hier: Kommt nichts an, bleibt die DWD-Bildebene
// aus 1.45.0 stehen. Die Regenkarte ist eine Zugabe, kein Kernpfad; im
// Wald ohne Empfang darf sie nichts kaputt machen, und eine Fehlermeldung
// über etwas, das man nicht angefordert hat, ist eine Störung.
//
// Kein neues Netzziel: GitHub-Releases stehen seit den Offline-Karten in
// der Datenschutzerklärung.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../features/map/rain_grid.dart';

/// Woher die Gitter kommen. Fester Tag, keine Version — die Daten ändern
/// sich mehrmals täglich, die App nicht.
const rainDataBaseUrl =
    'https://github.com/MacBuchi/pilzbuddy/releases/download/rain-data';

/// Was das Manifest über eine Ebene sagt.
class RainGridInfo {
  const RainGridInfo({
    required this.layer,
    required this.file,
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.measured,
  });

  final String layer;
  final String file;
  final int width;
  final int height;
  final double west;
  final double east;
  final double north;
  final double south;
  final DateTime measured;

  static RainGridInfo? tryParse(Map<String, dynamic> json) {
    try {
      return RainGridInfo(
        layer: json['layer'] as String,
        file: json['file'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
        west: (json['west'] as num).toDouble(),
        east: (json['east'] as num).toDouble(),
        north: (json['north'] as num).toDouble(),
        south: (json['south'] as num).toDouble(),
        measured: DateTime.parse(json['measured'] as String),
      );
    } catch (_) {
      // Ein Manifest, das wir nicht verstehen, ist kein Grund für eine
      // Fehlermeldung — dann gibt es eben keine Höhenlinien.
      return null;
    }
  }

  /// Der Dateiname des zwischengespeicherten Gitters. Der Messzeitpunkt
  /// steckt darin, damit ein neuer Stand nicht denselben Namen bekommt
  /// und eine halb geschriebene Datei nie als vollständig gilt.
  String get cacheName =>
      '${layer}_${measured.toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.bin.gz';
}

/// Was das Manifest über den Tagesstapel sagt.
///
/// Alle Tage teilen sich eine Geometrie — das Werkzeug schneidet sie
/// deshalb nicht zu. Stünde sie je Tag im Manifest, wäre der erste Tag
/// mit abweichender Größe ein Verlauf, der stillschweigend den falschen
/// Punkt liest.
class RainStackInfo {
  const RainStackInfo({
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.days,
  });

  final int width;
  final int height;
  final double west;
  final double east;
  final double north;
  final double south;
  final List<({DateTime date, String file})> days;

  static RainStackInfo? tryParse(Map<String, dynamic> json) {
    try {
      final days = [
        for (final day in json['days'] as List)
          (
            date: DateTime.parse((day as Map)['date'] as String),
            file: day['file'] as String,
          ),
      ]..sort((a, b) => a.date.compareTo(b.date));
      if (days.isEmpty) return null;
      return RainStackInfo(
        width: json['width'] as int,
        height: json['height'] as int,
        west: (json['west'] as num).toDouble(),
        east: (json['east'] as num).toDouble(),
        north: (json['north'] as num).toDouble(),
        south: (json['south'] as num).toDouble(),
        days: days,
      );
    } catch (_) {
      // Ein Manifest, das wir nicht verstehen, ist kein Grund für eine
      // Fehlermeldung — dann gibt es eben keinen Verlauf.
      return null;
    }
  }
}

/// Der geladene Stapel: die Geometrie und je Tag die **gepackten** Bytes.
///
/// Gepackt mit Absicht. Entpackt wären es 14 × 752 000 Zellen, also gut
/// zehn Megabyte, die dauerhaft im Speicher lägen — in einer App, die
/// schon einmal an Speicherdruck gestorben ist (#142/#151), ist das kein
/// vertretbarer Preis für vierzehn Zahlen. Gepackt sind es 646 KB, und
/// ausgepackt wird im Isolate, ein Tag nach dem anderen.
class RainStackData {
  const RainStackData({required this.info, required this.days});

  final RainStackInfo info;
  final List<({DateTime date, List<int> gzipped})> days;
}

class RainGridRepository {
  RainGridRepository({http.Client? client, Directory? baseDirOverride})
      : _client = client ?? http.Client(),
        _baseDirOverride = baseDirOverride;

  final http.Client _client;
  final Directory? _baseDirOverride;

  Future<Directory> _dir() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/rain');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Das Gitter einer Ebene — `null`, wenn weder Netz noch Platte etwas
  /// hergeben.
  ///
  /// Reihenfolge mit Absicht: erst das Manifest (rund ein Kilobyte), dann
  /// nur laden, was noch nicht liegt. Wer die Ebene zweimal am Tag
  /// einschaltet, lädt die 216 KB einmal.
  Future<RainGrid?> load(String layer) async {
    RainGridInfo? info;
    try {
      info = await _fetchInfo(layer);
    } catch (_) {
      // Still: Kein Empfang, GitHub weg oder Manifest kaputt — gleich
      // darunter wird es mit dem versucht, was auf Platte liegt. Kein
      // `logError`, denn das landet in `error_reports`, und ein Abruf im
      // Wald ohne Netz ist ein normaler Vorgang. Genau solche Zeilen
      // haben in #124/#136 den Wochendigest zugeschüttet.
    }

    if (info != null) {
      // Merken, bevor irgendetwas schiefgehen kann: Ohne das Manifest
      // lässt sich ein Gitter auf Platte später nicht mehr verorten.
      await rememberInfo(info);
      final cached = File('${(await _dir()).path}/${info.cacheName}');
      if (await cached.exists()) {
        final grid = await _read(cached, info);
        if (grid != null) return grid;
      }
      try {
        final bytes = await _download('$rainDataBaseUrl/${info.file}');
        // Erst vollständig schreiben, dann prüfen: Ein Gitter, das sich
        // nicht auspacken lässt, darf nicht als Zwischenspeicher liegen
        // bleiben und jeden weiteren Versuch vergiften.
        final grid = _decode(bytes, info);
        if (grid != null) {
          await cached.writeAsBytes(bytes, flush: true);
          await _pruneOthers(cached.path, prefix: '${info.layer}_');
          return grid;
        }
      } catch (_) {
        // Still, aus demselben Grund: Die Regenkarte ist eine Zugabe.
        // Unten folgt der Weg über die Platte.
      }
    }

    return _newestOnDisk(layer);
  }

  /// Der Tagesstapel — `null`, wenn weder Netz noch Platte etwas hergeben.
  ///
  /// Lädt **inkrementell**: Was schon auf Platte liegt, wird nicht erneut
  /// geholt. Beim ersten Mal sind das bis zu vierzehn Dateien (~646 KB),
  /// danach eine am Tag (~50 KB im Mittel). [onProgress] meldet den
  /// Fortschritt, damit das Blatt nicht stumm dasteht.
  ///
  /// Ohne Empfang wird genommen, was da ist: Ein Verlauf aus zwölf
  /// gespeicherten Tagen ist im Wald mehr wert als gar keiner. Fehlende
  /// Tage fehlen dann eben — [RainCourse.sumOfLast] gibt für ein
  /// unvollständiges Fenster ohnehin keine Zahl aus.
  Future<RainStackData?> loadDailyStack({
    void Function(int done, int total)? onProgress,
  }) async {
    RainStackInfo? info;
    try {
      info = await _fetchStackInfo();
    } catch (_) {
      // Still: kein Empfang oder GitHub weg. Unten wird versucht, was auf
      // Platte liegt. Kein `logError` — ein Abruf im Wald ohne Netz ist
      // ein normaler Vorgang (#124/#136).
    }
    if (info != null) {
      await _rememberStackInfo(info);
    } else {
      info = await _lastStackInfo();
    }
    if (info == null) return null;

    final dir = await _dir();
    final days = <({DateTime date, List<int> gzipped})>[];
    for (final (index, day) in info.days.indexed) {
      onProgress?.call(index, info.days.length);
      final file = File('${dir.path}/${day.file}');
      List<int>? bytes;
      if (await file.exists()) {
        try {
          bytes = await file.readAsBytes();
        } catch (_) {
          // Datei verschwunden oder unlesbar — behandeln wie „nicht da".
        }
      }
      if (bytes == null) {
        try {
          bytes = await _download('$rainDataBaseUrl/${day.file}');
          await file.writeAsBytes(bytes, flush: true);
        } catch (_) {
          // Dieser Tag fehlt eben. Weitermachen: Ein Verlauf mit einer
          // Lücke ist brauchbar, ein Abbruch nicht.
          continue;
        }
      }
      days.add((date: day.date, gzipped: bytes));
    }
    onProgress?.call(info.days.length, info.days.length);
    await _pruneStack(dir, {for (final day in info.days) day.file});
    if (days.isEmpty) return null;
    return RainStackData(info: info, days: days);
  }

  /// Die Stationstabelle (Temperatur) — als **gepackte** Bytes, `null`,
  /// wenn weder Netz noch Platte etwas hergeben. Ausgepackt wird im
  /// Isolate des Aufrufers (`weatherTableFrom`), nicht hier.
  ///
  /// Der Zwischenspeichername trägt den jüngsten Tag der Tabelle
  /// (`weather_2026-08-03.json.gz`): Das Release-Asset heißt jeden Tag
  /// gleich, und unter einem gleichbleibenden Namen wäre ein alter Stand
  /// nicht von einem neuen zu unterscheiden. Ohne Empfang wird der
  /// jüngste Stand von Platte genommen — zwölf Tage alte Temperaturen
  /// sind im Wald mehr wert als keine, und das Datum steht im Diagramm.
  Future<List<int>?> loadWeatherTable() async {
    String? newestDay;
    try {
      final response = await _client
          .get(Uri.parse('$rainDataBaseUrl/rain_manifest.json'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw HttpException('Manifest: HTTP ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final days = (json['weather'] as Map<String, dynamic>?)?['days'];
      if (days is List && days.isNotEmpty) newestDay = days.last as String;
    } catch (_) {
      // Still: kein Empfang oder GitHub weg — unten liegt vielleicht
      // noch ein Stand auf Platte. Kein `logError` (#124/#136).
    }

    final dir = await _dir();
    if (newestDay != null) {
      final cached = File('${dir.path}/weather_$newestDay.json.gz');
      if (await cached.exists()) {
        try {
          return await cached.readAsBytes();
        } catch (_) {
          // Unlesbar — behandeln wie „nicht da" und neu laden.
        }
      }
      try {
        final bytes = await _download('$rainDataBaseUrl/weather_stations.json.gz');
        // Erst prüfen, dann schreiben — ein abgebrochener Download, der
        // sich nicht auspacken lässt, darf nicht als Zwischenspeicher
        // liegen bleiben und jeden weiteren Versuch vergiften (dasselbe
        // Muster wie beim Gitter). Die inhaltliche Prüfung macht der
        // Parser im Isolate des Aufrufers.
        GZipDecoder().decodeBytes(bytes);
        await cached.writeAsBytes(bytes, flush: true);
        await _pruneOthers(cached.path, prefix: 'weather_');
        return bytes;
      } catch (_) {
        // Still, wie beim Gitter: unten der Weg über die Platte.
      }
    }

    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.split('/').last.startsWith('weather_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      if (files.isEmpty) return null;
      return await files.first.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<RainStackInfo?> _fetchStackInfo() async {
    final response = await _client
        .get(Uri.parse('$rainDataBaseUrl/rain_manifest.json'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('Manifest: HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>?;
    return daily == null ? null : RainStackInfo.tryParse(daily);
  }

  /// Tagesdateien wegräumen, die der Stapel nicht mehr führt. Ohne das
  /// wächst das App-Verzeichnis um eine Datei am Tag, für immer.
  Future<void> _pruneStack(Directory dir, Set<String> keep) async {
    try {
      for (final entry in dir.listSync().whereType<File>()) {
        final name = entry.path.split('/').last;
        if (!name.startsWith('rain_day_')) continue;
        if (keep.contains(name)) continue;
        await entry.delete();
      }
    } catch (_) {
      // Aufräumen ist Kür.
    }
  }

  Future<File> _stackInfoFile() async =>
      File('${(await _dir()).path}/stack.json');

  Future<void> _rememberStackInfo(RainStackInfo info) async {
    try {
      await (await _stackInfoFile()).writeAsString(jsonEncode({
        'width': info.width,
        'height': info.height,
        'west': info.west,
        'east': info.east,
        'north': info.north,
        'south': info.south,
        'days': [
          for (final day in info.days)
            {'date': day.date.toIso8601String(), 'file': day.file},
        ],
      }));
    } catch (_) {
      // Ohne gemerktes Manifest fehlt nur der Weg ohne Empfang.
    }
  }

  Future<RainStackInfo?> _lastStackInfo() async {
    try {
      final file = await _stackInfoFile();
      if (!await file.exists()) return null;
      return RainStackInfo.tryParse(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<RainGridInfo?> _fetchInfo(String layer) async {
    final response = await _client
        .get(Uri.parse('$rainDataBaseUrl/rain_manifest.json'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('Manifest: HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final layers = json['layers'] as Map<String, dynamic>?;
    final entry = layers?[layer] as Map<String, dynamic>?;
    return entry == null ? null : RainGridInfo.tryParse(entry);
  }

  Future<List<int>> _download(String url) async {
    final response =
        await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw HttpException('Gitter: HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  RainGrid? _decode(List<int> bytes, RainGridInfo info) {
    try {
      return RainGrid.decode(
        bytes,
        width: info.width,
        height: info.height,
        west: info.west,
        east: info.east,
        north: info.north,
        south: info.south,
        measured: info.measured,
      );
    } catch (_) {
      // Ein Gitter, das sich nicht auspacken lässt, ist eine kaputte
      // Datei — die Ebene bleibt aus, die App läuft weiter.
      return null;
    }
  }

  Future<RainGrid?> _read(File file, RainGridInfo info) async {
    try {
      return _decode(await file.readAsBytes(), info);
    } catch (_) {
      // Datei verschwunden oder unlesbar — behandeln wie „nicht da".
      return null;
    }
  }

  /// Alles außer dem gerade geschriebenen Stand derselben Ebene weg. Ohne
  /// das sammelt sich je Messzeitpunkt eine Datei an — bei der
  /// 24-Stunden-Summe achtmal am Tag.
  ///
  /// Der Namensanfang kommt von außen und wird nicht aus [keep] geraten:
  /// Gitter (`w4_…`) und Flächen (`fill_w4_…`) liegen im selben Ordner,
  /// und ein geratener Anfang würde die jeweils andere Sorte mitreißen.
  Future<void> _pruneOthers(String keep, {required String prefix}) async {
    try {
      final dir = await _dir();
      for (final entry in dir.listSync().whereType<File>()) {
        if (entry.path == keep) continue;
        if (!entry.path.split('/').last.startsWith(prefix)) continue;
        await entry.delete();
      }
    } catch (_) {
      // Aufräumen ist Kür. Ein paar Kilobyte zu viel sind kein Fehler,
      // den jemand sehen muss.
    }
  }

  /// Der jüngste Stand, der auf Platte liegt — der Weg ohne Empfang.
  ///
  /// Die Ausdehnung steht nicht in der Datei, also braucht dieser Weg das
  /// zuletzt gesehene Manifest. Es liegt daneben.
  Future<RainGrid?> _newestOnDisk(String layer) async {
    try {
      final dir = await _dir();
      final info = await _lastInfo(layer);
      if (info == null) return null;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.split('/').last.startsWith('${layer}_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      if (files.isEmpty) return null;
      return _read(files.first, info);
    } catch (_) {
      return null;
    }
  }

  Future<File> _infoFile(String layer) async =>
      File('${(await _dir()).path}/$layer.json');

  Future<RainGridInfo?> _lastInfo(String layer) async {
    try {
      final file = await _infoFile(layer);
      if (!await file.exists()) return null;
      return RainGridInfo.tryParse(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Legt die eingefärbte Fläche als PNG auf Platte und liefert die
  /// `file://`-URL — oder `null`, wenn das Schreiben scheitert.
  ///
  /// Warum überhaupt eine Datei: MapLibres `image`-Quelle nimmt eine URL,
  /// keine Bytes (flutter_map bekommt dieselben Bytes direkt als
  /// `MemoryImage`). Der Messzeitpunkt steckt im Namen, damit ein neuer
  /// Stand nie unter derselben URL liegt — die Engine würde sonst das
  /// alte Bild behalten und die Fläche wäre still veraltet.
  ///
  /// **Geschrieben wird immer**, auch wenn die Datei schon da ist: Der
  /// Name kennt den Messzeitpunkt, nicht die Darstellung. Ändert eine
  /// neue App-Version Farben, Deckkraft oder Glättung, läge sonst bis zur
  /// nächsten Messung das alte Bild auf der Karte — am Emulator genau so
  /// passiert (2026-08-04: das geglättete Bild war pixelgleich zum
  /// ungeglätteten, weil die Datei von vorher wiederverwendet wurde).
  Future<String?> writeFill(
      String layer, DateTime measured, List<int> png) async {
    try {
      final dir = await _dir();
      final stamp =
          measured.toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/fill_${layer}_$stamp.png');
      await file.writeAsBytes(png, flush: true);
      await _pruneOthers(file.path, prefix: 'fill_${layer}_');
      return 'file://${file.path}';
    } catch (_) {
      // Kein Platz, kein Schreibrecht: Dann bleibt es bei den Linien
      // ohne Fläche. Die Aussage steckt in den Linien, die Fläche ist
      // Orientierung — das ist ein hinnehmbarer Verlust und kein Fall
      // für `error_reports`.
      return null;
    }
  }

  Future<void> rememberInfo(RainGridInfo info) async {
    try {
      await (await _infoFile(info.layer)).writeAsString(jsonEncode({
        'layer': info.layer,
        'file': info.file,
        'width': info.width,
        'height': info.height,
        'west': info.west,
        'east': info.east,
        'north': info.north,
        'south': info.south,
        'measured': info.measured.toIso8601String(),
      }));
    } catch (_) {
      // Ohne gemerktes Manifest fehlt nur der Weg ohne Empfang.
    }
  }
}
