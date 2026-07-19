import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'region_catalog.dart';

/// Eine zum Download angebotene Regionskarte (Release-Asset der Quelle).
class AvailableMap {
  final String key;
  final String dateStamp;
  final int sizeBytes;
  final String downloadUrl;

  const AvailableMap({
    required this.key,
    required this.dateStamp,
    required this.sizeBytes,
    required this.downloadUrl,
  });

  String get label => regionLabel(key);
}

/// Eine heruntergeladene Regionskarte auf dem Gerät.
class InstalledMap {
  final String key;
  final String dateStamp;
  final int sizeBytes;
  final String filePath;

  const InstalledMap({
    required this.key,
    required this.dateStamp,
    required this.sizeBytes,
    required this.filePath,
  });

  String get label => regionLabel(key);

  Map<String, dynamic> toJson() => {
        'key': key,
        'date_stamp': dateStamp,
        'size_bytes': sizeBytes,
        'file_path': filePath,
      };

  factory InstalledMap.fromJson(Map<String, dynamic> json) => InstalledMap(
        key: json['key'] as String,
        dateStamp: json['date_stamp'] as String,
        sizeBytes: json['size_bytes'] as int? ?? 0,
        filePath: json['file_path'] as String,
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
      maps.add(AvailableMap(
        key: parsed.key,
        dateStamp: parsed.dateStamp,
        sizeBytes: asset['size'] as int? ?? 0,
        downloadUrl: asset['browser_download_url'] as String,
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

  /// Lädt eine Karte herunter und meldet den Fortschritt (0..1).
  /// Ersetzt eine ältere Version derselben Region atomar (erst temporäre
  /// Datei, dann umbenennen), damit nie eine halbe Karte aktiv ist.
  Stream<double> download(AvailableMap map) async* {
    final dir = await _mapsDir();
    final targetPath = '${dir.path}/${map.key}_${map.dateStamp}.pmtiles';
    final tempFile = File('$targetPath.part');

    final request = http.Request('GET', Uri.parse(map.downloadUrl));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('Download: HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? map.sizeBytes;
    var received = 0;
    final sink = tempFile.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) yield received / total;
      }
      await sink.flush();
    } finally {
      await sink.close();
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
      ),
    ];
    await _writeRegistry(updated);
    yield 1.0;
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
