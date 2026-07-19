import 'dart:io';
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Liefert Vector-Tiles aus einer lokalen PMTiles-Datei an vector_map_tiles.
/// (Das fertige Paket vector_map_tiles_pmtiles unterstützt flutter_map 8
/// noch nicht — dieser kleine Adapter ersetzt es.)
class PmTilesVectorTileProvider extends VectorTileProvider {
  PmTilesVectorTileProvider._(this._archive, this._minZoom, this._maxZoom);

  final PmTilesArchive _archive;
  final int _minZoom;
  final int _maxZoom;

  static Future<PmTilesVectorTileProvider> open(String path) async {
    final archive = await PmTilesArchive.fromFile(File(path));
    return PmTilesVectorTileProvider._(
        archive, archive.header.minZoom, archive.header.maxZoom);
  }

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final t = await _archive.tile(ZXY(tile.z, tile.x, tile.y).toTileId());
    try {
      return Uint8List.fromList(t.bytes());
    } on TileNotFoundException {
      throw ProviderException(
        message: 'Tile ${tile.key()} nicht in der Offline-Karte',
        retryable: Retryable.none,
        statusCode: 404,
      );
    }
  }

  @override
  int get minimumZoom => _minZoom;

  @override
  int get maximumZoom => _maxZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}

/// Kombiniert mehrere Regionskarten zu einer Quelle: Beim Tile-Abruf wird
/// die erste Karte genommen, die das Tile enthält (Regionen überlappen
/// höchstens an den Rändern).
class MultiPmTilesVectorTileProvider extends VectorTileProvider {
  MultiPmTilesVectorTileProvider(this._providers)
      : assert(_providers.isNotEmpty);

  final List<PmTilesVectorTileProvider> _providers;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    ProviderException? lastMiss;
    for (final provider in _providers) {
      try {
        return await provider.provide(tile);
      } on ProviderException catch (e) {
        lastMiss = e;
      }
    }
    throw lastMiss ??
        ProviderException(
          message: 'Keine Offline-Karte für Tile ${tile.key()}',
          retryable: Retryable.none,
          statusCode: 404,
        );
  }

  @override
  int get minimumZoom =>
      _providers.map((p) => p.minimumZoom).reduce((a, b) => a < b ? a : b);

  @override
  int get maximumZoom =>
      _providers.map((p) => p.maximumZoom).reduce((a, b) => a > b ? a : b);

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}
