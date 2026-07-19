import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'region_catalog.dart';

/// Eine zum Download angebotene Regionskarte (Release-Asset der Quelle).
class AvailableMap {
  final String key;
  final String dateStamp;
  final int sizeBytes;
  final String downloadUrl;

  /// Erwartete Prüfsumme im GitHub-Format `sha256:<hex>` — null, wenn
  /// die Quelle keine liefert (dann wird ohne Validierung installiert).
  final String? sha256;

  const AvailableMap({
    required this.key,
    required this.dateStamp,
    required this.sizeBytes,
    required this.downloadUrl,
    this.sha256,
  });

  String get label => regionLabel(key);
}

/// Eine heruntergeladene Regionskarte auf dem Gerät.
class InstalledMap {
  final String key;
  final String dateStamp;
  final int sizeBytes;
  final String filePath;

  /// Prüfsumme der installierten Datei (`sha256:<hex>`), falls die
  /// Quelle beim Download eine geliefert hat.
  final String? sha256;

  const InstalledMap({
    required this.key,
    required this.dateStamp,
    required this.sizeBytes,
    required this.filePath,
    this.sha256,
  });

  String get label => regionLabel(key);

  Map<String, dynamic> toJson() => {
        'key': key,
        'date_stamp': dateStamp,
        'size_bytes': sizeBytes,
        'file_path': filePath,
        'sha256': sha256,
      };

  factory InstalledMap.fromJson(Map<String, dynamic> json) => InstalledMap(
        key: json['key'] as String,
        dateStamp: json['date_stamp'] as String,
        sizeBytes: json['size_bytes'] as int? ?? 0,
        filePath: json['file_path'] as String,
        sha256: json['sha256'] as String?,
      );
}

/// Verwaltet Offline-Karten: verfügbare Regionen von der Quelle abfragen,
/// Dateien herunterladen/löschen und die Registry der installierten Karten
/// pflegen. Quelle: fertige Bundesland-PMTiles (Protomaps Basemap v4,
/// © OpenStreetMap-Mitwirkende, ODbL) aus einem GitHub-Release.
class OfflineMapRepository {
  OfflineMapRepository({http.Client? client, Directory? baseDirOverride})
      : _client = client ?? http.Client(),
        _baseDirOverride = baseDirOverride;

  /// Austauschbar, falls die Karten später aus einem eigenen Repo kommen.
  static const releasesLatestUrl =
      'https://api.github.com/repos/whitespring/project-nomad-maps-europe/releases/latest';

  final http.Client _client;
  final Directory? _baseDirOverride;

  Future<Directory> _mapsDir() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline_maps');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _registryFile() async =>
      File('${(await _mapsDir()).path}/registry.json');

  /// Verfügbare Regionen aus dem neuesten Release der Quelle.
  Future<List<AvailableMap>> fetchAvailable() async {
    final response = await _client.get(
      Uri.parse(releasesLatestUrl),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('GitHub-API: HTTP ${response.statusCode}');
    }
    final release = jsonDecode(response.body) as Map<String, dynamic>;
    final assets = release['assets'] as List<dynamic>? ?? const [];
    final maps = <AvailableMap>[];
    for (final asset in assets.cast<Map<String, dynamic>>()) {
      final parsed = parseMapAssetName(asset['name'] as String? ?? '');
      if (parsed == null) continue;
      final digest = asset['digest'] as String?;
      maps.add(AvailableMap(
        key: parsed.key,
        dateStamp: parsed.dateStamp,
        sizeBytes: asset['size'] as int? ?? 0,
        downloadUrl: asset['browser_download_url'] as String,
        sha256: (digest != null && digest.startsWith('sha256:'))
            ? digest
            : null,
      ));
    }
    maps.sort((a, b) => compareRegionKeys(a.key, b.key));
    return maps;
  }

  Future<List<InstalledMap>> listInstalled() async {
    final file = await _registryFile();
    if (!await file.exists()) return const [];
    final entries = jsonDecode(await file.readAsString()) as List<dynamic>;
    final maps = entries
        .map((e) => InstalledMap.fromJson(e as Map<String, dynamic>))
        // Registry-Einträge ohne Datei (z. B. vom System aufgeräumt) ignorieren.
        .where((m) => File(m.filePath).existsSync())
        .toList();
    maps.sort((a, b) => compareRegionKeys(a.key, b.key));
    return maps;
  }

  Future<void> _writeRegistry(List<InstalledMap> maps) async {
    final file = await _registryFile();
    await file.writeAsString(jsonEncode([for (final m in maps) m.toJson()]));
  }

  /// Nach so vielen Versuchen ohne jeden Fortschritt wird aufgegeben.
  /// Solange Bytes fließen, zählt der Zähler immer wieder von vorn —
  /// ein wackliges WLAN bricht einen langen Download damit nicht ab.
  static const _maxStalledAttempts = 5;

  /// Wartet keine Ewigkeit auf tote Verbindungen: kommt so lange kein
  /// einziges Byte, gilt der Versuch als gescheitert (→ Retry).
  static const _inactivityTimeout = Duration(seconds: 45);

  /// Lädt eine Karte herunter und meldet den Fortschritt (0..1).
  ///
  /// Robust für große Karten (#41): Verbindungsabrisse werden mit
  /// HTTP-Range-Requests automatisch dort fortgesetzt, wo der Download
  /// stand — auch über App-Neustarts hinweg, denn die .part-Datei
  /// bleibt bei Fehlschlägen liegen und der nächste Versuch setzt auf.
  /// Ersetzt eine ältere Version derselben Region atomar (erst temporäre
  /// Datei, dann umbenennen), damit nie eine halbe Karte aktiv ist.
  Stream<double> download(AvailableMap map) {
    final controller = StreamController<double>();
    _runDownload(map, controller).then(
      (_) => controller.close(),
      onError: (Object error, StackTrace stackTrace) {
        controller.addError(error, stackTrace);
        controller.close();
      },
    );
    return controller.stream;
  }

  Future<void> _runDownload(
      AvailableMap map, StreamController<double> progress) async {
    final dir = await _mapsDir();
    final targetPath = '${dir.path}/${map.key}_${map.dateStamp}.pmtiles';
    final tempFile = File('$targetPath.part');

    final total = map.sizeBytes;
    var received = await tempFile.exists() ? await tempFile.length() : 0;
    if (total > 0 && received > 0) progress.add(received / total);

    var stalledAttempts = 0;
    var checksumFailures = 0;
    while (total <= 0 || received < total) {
      final receivedBefore = received;
      try {
        final request = http.Request('GET', Uri.parse(map.downloadUrl));
        if (received > 0) request.headers['range'] = 'bytes=$received-';
        final response =
            await _client.send(request).timeout(_inactivityTimeout);

        if (received > 0 && response.statusCode == 200) {
          // Server kann kein Range → noch einmal von vorn.
          received = 0;
        } else if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException('Download: HTTP ${response.statusCode}');
        }

        final sink = tempFile.openWrite(
            mode: received > 0 ? FileMode.append : FileMode.write);
        try {
          await for (final chunk
              in response.stream.timeout(_inactivityTimeout)) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0) progress.add(received / total);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        // Prüfsummen-Validierung (#41-Nachzug): fängt korrupte Dateien,
        // bevor sie installiert werden — vor allem den Fall, dass die
        // Quelle das Asset ersetzt hat, während eine .part-Datei per
        // Range fortgesetzt wurde (alte + neue Hälfte = Datenmüll).
        if ((total <= 0 || received >= total) && map.sha256 != null) {
          final actual = await _fileSha256(tempFile);
          if (actual != map.sha256) {
            checksumFailures++;
            await tempFile.delete();
            received = 0;
            if (checksumFailures >= 2) {
              throw const FileSystemException(
                  'Prüfsumme stimmt nicht — Download verworfen');
            }
            continue; // Einmal komplett neu laden.
          }
        }

        if (total <= 0) break; // Größe unbekannt — Stream-Ende zählt.
      } catch (e) {
        if (e is FileSystemException) rethrow;
        if (received > receivedBefore) stalledAttempts = 0;
        stalledAttempts++;
        if (stalledAttempts >= _maxStalledAttempts) {
          // .part bleibt liegen: der nächste Download-Tap setzt hier fort.
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: 2 * stalledAttempts));
      }
    }

    await tempFile.rename(targetPath);

    final installed = await listInstalled();
    // Alte Datei derselben Region entfernen (bei Karten-Update).
    for (final old in installed.where((m) => m.key == map.key)) {
      if (old.filePath != targetPath) {
        final oldFile = File(old.filePath);
        if (await oldFile.exists()) await oldFile.delete();
      }
    }
    final updated = [
      ...installed.where((m) => m.key != map.key),
      InstalledMap(
        key: map.key,
        dateStamp: map.dateStamp,
        sizeBytes: received,
        filePath: targetPath,
        sha256: map.sha256,
      ),
    ];
    await _writeRegistry(updated);
    progress.add(1.0);
  }

  /// SHA-256 einer Datei im GitHub-Digest-Format `sha256:<hex>` —
  /// gestreamt, damit auch 1,7-GB-Karten nicht in den Speicher müssen.
  Future<String> _fileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return 'sha256:$digest';
  }

  Future<void> delete(String key) async {
    final installed = await listInstalled();
    for (final map in installed.where((m) => m.key == key)) {
      final file = File(map.filePath);
      if (await file.exists()) await file.delete();
    }
    await _writeRegistry(installed.where((m) => m.key != key).toList());
  }
}
