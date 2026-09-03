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

  /// Aus einer Datei — der Weg auf dem Telefon.
  ///
  /// `FileAt` liest faul über einen Pool von acht Handles; die Karte liegt
  /// nie im Speicher, und genau darauf beruht, dass eine 1,7-GB-Region
  /// überhaupt benutzbar ist.
  static Future<PmTilesVectorTileProvider> open(String path) async {
    final archive = await PmTilesArchive.fromFile(File(path));
    return PmTilesVectorTileProvider._(
        archive, archive.header.minZoom, archive.header.maxZoom);
  }

  /// Aus Bytes — der Weg im Browser.
  ///
  /// Dort gibt es die Wahl nicht: `dart:io` kompiliert zwar (dart2js
  /// liefert Stubs), aber `pmtiles` exportiert für JS eine `FileAt`, die
  /// beim Anlegen `UnsupportedError` wirft. `MemoryAt` dagegen ist reines
  /// Dart und läuft; auch das Entpacken der Kacheln hat einen Web-Zweig
  /// (`package:archive` statt `dart:io`s zlib).
  ///
  /// Der Preis ist, dass die Karte im Speicher bleibt — vertretbar für die
  /// mitgelieferte Übersicht (8,6 MB), nicht für eine Regionskarte.
  /// [close] ist hier folgerichtig ein No-op: Es gibt kein Handle.
  static Future<PmTilesVectorTileProvider> openBytes(Uint8List bytes) async {
    final archive = await PmTilesArchive.fromBytes(bytes);
    return PmTilesVectorTileProvider._(
        archive, archive.header.minZoom, archive.header.maxZoom);
  }

  /// Gibt das Dateihandle des Archivs frei — beim Neuaufbau der
  /// Offline-Quellen aufrufen, sonst leaken Handles (#Karten-Freezes).
  Future<void> close() => _archive.close();

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    try {
      final t = await _archive.tile(ZXY(tile.z, tile.x, tile.y).toTileId());
      return Uint8List.fromList(t.bytes());
    } on TileNotFoundException {
      throw ProviderException(
        message: 'Tile ${tile.key()} nicht in der Offline-Karte',
        retryable: Retryable.none,
        statusCode: 404,
      );
    } on StateError catch (e) {
      // Das Archiv ist geschlossen — gefragt wird eine ältere Generation der
      // Quelle, die ein Layer noch in seinen Caches hält (Issue #144). Der
      // Lesepool von `pmtiles` wirft dann „withResource() may not be called
      // on a closed Pool". Ungefangen ist das ein unbehandelter Fehler pro
      // Kachel: auf dem Pixel 7 Pro 121 Stück in einem Stresslauf, jeder
      // davon eine Zeile in `error_reports` und im Wochendigest. Als
      // ProviderException degradiert es zu „Kachel fehlt", und die Schicht
      // darunter (die Übersicht) bleibt sichtbar.
      throw ProviderException(
        message: 'Offline-Karte bereits geschlossen (${tile.key()}): $e',
        retryable: Retryable.none,
        statusCode: 410,
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

  Future<void> close() async {
    for (final provider in _providers) {
      await provider.close();
    }
  }

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
