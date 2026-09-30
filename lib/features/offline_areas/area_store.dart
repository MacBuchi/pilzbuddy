// Die Ablage gespeicherter Kartenbereiche (#630, Stufe 2): je Bereich
// EIN PMTiles-Archiv (Zoom 8 bis zum Zoom des Hosts) und ein Eintrag im
// Index. Auf dem Telefon Dateien unter `offline_maps/areas/` (wie die
// Regionskarten vom Backup ausgenommen — jederzeit neu ladbar), im Browser
// IndexedDB (`area_store_idb.dart`), im Test der Speicher.
//
// Bereiche sind Absicht: Sie werden nie verdrängt, nur auf Wunsch
// gelöscht (Liste „Kartenbereiche").
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'area_plan.dart';
import 'area_store_web.dart' if (dart.library.io) 'area_store_io.dart';

/// Ein gespeicherter Bereich, wie der Index ihn führt.
class StoredArea {
  StoredArea({
    required this.id,
    required this.name,
    required this.bounds,
    AreaShape? shape,
    required this.minZoom,
    required this.maxZoom,
    required this.build,
    required this.tiles,
    required this.bytes,
    required this.savedAt,
  }) : shape = shape ?? RectShape(bounds);

  final String id;
  final String name;

  /// Die Hülle der Form. Innerhalb der Hülle kann eine Kachel FEHLEN
  /// (Form um die Spots) — wer eine braucht, fragt das Archiv.
  final AreaBounds bounds;

  /// Die Form, mit der der Bereich geplant wurde — „Aktualisieren" holt
  /// sie noch einmal.
  final AreaShape shape;
  final int minZoom;
  final int maxZoom;

  /// Der Kartenstand: `source_build` des Host-Manifests (`JJJJMMTT`).
  final String build;
  final int tiles;
  final int bytes;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bounds': bounds.toJson(),
        'shape': shape.toJson(),
        'min_zoom': minZoom,
        'max_zoom': maxZoom,
        'build': build,
        'tiles': tiles,
        'bytes': bytes,
        'saved_at': savedAt.toUtc().toIso8601String(),
      };

  factory StoredArea.fromJson(Map<String, dynamic> j) => StoredArea(
        id: j['id'] as String,
        name: j['name'] as String,
        bounds: AreaBounds.fromJson(j['bounds'] as Map<String, dynamic>),
        shape: j['shape'] == null
            ? null
            : AreaShape.fromJson(j['shape'] as Map<String, dynamic>),
        minZoom: j['min_zoom'] as int,
        maxZoom: j['max_zoom'] as int,
        build: j['build'] as String,
        tiles: j['tiles'] as int,
        bytes: j['bytes'] as int,
        savedAt: DateTime.parse(j['saved_at'] as String),
      );
}

/// Was die Ablage kann. Archive kommen als Ganzes (geschrieben wird
/// einmal, am Ende des Downloads); gelesen wird auf dem Telefon über den
/// PFAD (MapLibre und `FileAt` lesen faul), im Browser über die Bytes.
abstract interface class AreaStore {
  Future<List<StoredArea>> list();

  /// Schreibt den Index ganz neu — die eine Stelle, an der ein Bereich
  /// sichtbar wird oder verschwindet.
  Future<void> saveIndex(List<StoredArea> areas);

  Future<void> putArchive(String id, Uint8List bytes);

  /// Der Pfad des Archivs auf der Platte, null im Browser.
  Future<String?> archivePath(String id);

  /// Die Bytes des Archivs — der Weg im Browser; null, wenn es fehlt.
  Future<Uint8List?> readArchive(String id);

  /// Löscht Archiv und Index-Eintrag.
  Future<void> delete(String id);
}

/// Im Speicher — für Tests.
class MemoryAreaStore implements AreaStore {
  List<StoredArea> areas = [];
  final archives = <String, Uint8List>{};

  @override
  Future<List<StoredArea>> list() async => List.unmodifiable(areas);

  @override
  Future<void> saveIndex(List<StoredArea> areas) async =>
      this.areas = List.of(areas);

  @override
  Future<void> putArchive(String id, Uint8List bytes) async =>
      archives[id] = bytes;

  @override
  Future<String?> archivePath(String id) async => null;

  @override
  Future<Uint8List?> readArchive(String id) async => archives[id];

  @override
  Future<void> delete(String id) async {
    areas = [
      for (final a in areas)
        if (a.id != id) a,
    ];
    archives.remove(id);
  }
}

/// Die Ablage der Plattform: Dateien auf dem Telefon, IndexedDB im
/// Browser. Tests hängen `MemoryAreaStore` ein.
final areaStoreProvider = Provider<AreaStore>((ref) => createAreaStore());
