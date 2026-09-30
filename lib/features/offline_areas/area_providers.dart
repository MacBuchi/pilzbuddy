// Die gespeicherten Kartenbereiche in der App (#630, Stufe 2): die Liste,
// der laufende Download (mit Fortschritt, Abbruch und dem
// Vordergrunddienst über den Koordinator), und die geöffneten Archive für
// die Karte — für flutter_map als Kachelquelle, für MapLibre als Pfade.
//
// **Die Bereiche liegen IMMER auf der Karte, zuoberst** — in beiden
// Engines, mit und ohne Empfang, über OSM, der Neuen Karte und den
// Regionskarten. Die Lehre stammt aus TrailBuddy #82: Im Wald heißt „kein
// Empfang" meist „ein Balken, über den nichts kommt"; eine Regel „Bereiche
// nur ohne Empfang" griff dort nicht, und die gespeicherten Kacheln
// blieben ungefragt. Jede Kachel eines Bereichs trägt die deckende
// `earth`-Fläche des Stils und verdeckt darunter alles; wo der Bereich
// keine Kachel hat, liefert sein Archiv nichts, und die Karte darunter
// scheint durch.
//
// **Gespeichert wird nur mit dem Schalter „Neue Karte"** (ab Werk an seit
// 1.217.0):
// Die Kacheln kommen vom selben Kartenhost, und solange der eine Vorschau
// ist, gehört auch das Speichern dazu. Einmal gespeicherte Bereiche
// zeichnet die Karte unabhängig vom Schalter — sie liegen auf dem Gerät,
// und da fragt niemand mehr den Host.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../core/errors.dart';
import '../map/online_map.dart';
import '../offline_maps/download_keep_alive.dart';
import '../offline_maps/offline_map_providers.dart';
import '../offline_maps/pmtiles_tile_provider.dart';
import 'area_downloader.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'area_trim.dart';

/// Die Liste aus dem Index, in Speicherreihenfolge.
class StoredAreasNotifier extends AsyncNotifier<List<StoredArea>> {
  @override
  Future<List<StoredArea>> build() => ref.watch(areaStoreProvider).list();

  Future<void> refresh() async =>
      state = AsyncData(await ref.read(areaStoreProvider).list());

  Future<void> delete(String id) async {
    await ref.read(areaStoreProvider).delete(id);
    await refresh();
  }

  /// Was der Radierer mit den Bereichen macht — gemessen, ohne Netz.
  Future<TrimPlan> planTrim(Set<int> removes) async => AreaTrimmer(
          ref.read(areaStoreProvider))
      .plan(await future, removes);

  /// Schreibt die betroffenen Bereiche ohne die Kacheln neu.
  Future<void> applyTrim(TrimPlan plan) async {
    await AreaTrimmer(ref.read(areaStoreProvider)).apply(plan);
    await refresh();
  }
}

final storedAreasProvider =
    AsyncNotifierProvider<StoredAreasNotifier, List<StoredArea>>(
        StoredAreasNotifier.new);

/// Öffnet das Archiv des Hosts für Plan und Download — die Naht für
/// Tests. Ein EIGENES `PmTilesArchive`, nicht das der Online-Karte: Das
/// gehört dem Kartenlayer und wird geschlossen, wenn der neu aufbaut.
final areaSourceOpenerProvider =
    Provider<Future<PmTilesArchive> Function(Uri)>(
        (ref) => PmTilesArchive.fromUri);

enum AreaDownloadPhase { idle, planning, running, done, failed }

/// Der Zustand des einen laufenden Downloads (es gibt höchstens einen).
@immutable
class AreaDownloadState {
  const AreaDownloadState({
    this.phase = AreaDownloadPhase.idle,
    this.name,
    this.progress,
    this.result,
    this.error,
  });

  final AreaDownloadPhase phase;
  final String? name;
  final AreaProgress? progress;
  final StoredArea? result;
  final String? error;

  bool get busy =>
      phase == AreaDownloadPhase.planning || phase == AreaDownloadPhase.running;
}

class AreaDownloadNotifier extends Notifier<AreaDownloadState> {
  static const _keepAliveKey = 'area';
  bool _cancelled = false;

  @override
  AreaDownloadState build() => const AreaDownloadState();

  Future<MapManifest> _manifest() => ref
      .read(mapManifestLoaderProvider)()
      .timeout(const Duration(seconds: 10));

  /// Der Plan für [shape]: wirft [AreaTooLarge], liefert Kacheln und
  /// Bytes. Braucht den Kartenhost — ohne Empfang gibt es keinen Plan.
  Future<AreaPlan> plan(AreaShape shape) async {
    state = const AreaDownloadState(phase: AreaDownloadPhase.planning);
    PmTilesArchive? archive;
    try {
      final manifest = await _manifest();
      archive = await ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
      final plan = await AreaDownloader(
              archive: archive,
              manifest: manifest,
              store: ref.read(areaStoreProvider))
          .plan(shape);
      state = const AreaDownloadState();
      return plan;
    } catch (_) {
      state = const AreaDownloadState();
      rethrow;
    } finally {
      await archive?.close();
    }
  }

  /// Holt und speichert. Läuft im Main-Isolate; der Koordinator hält den
  /// Prozess auf Android wach. Ein Fehler landet im Zustand (die
  /// Oberfläche zeigt ihn), nie beim Aufrufer.
  Future<StoredArea?> start(AreaPlan plan,
      {required String name, String? id}) async {
    if (state.busy) return null;
    _cancelled = false;
    state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name);
    final coordinator = ref.read(downloadKeepAliveCoordinatorProvider);
    await coordinator.start(_keepAliveKey, '$name — 0 %',
        title: 'Kartenbereich wird gespeichert');
    PmTilesArchive? archive;
    try {
      final manifest = await _manifest();
      archive = await ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
      final area = await AreaDownloader(
        archive: archive,
        manifest: manifest,
        store: ref.read(areaStoreProvider),
      ).download(
        plan,
        name: name,
        id: id,
        isCancelled: () => _cancelled,
        onProgress: (p) {
          state = AreaDownloadState(
              phase: AreaDownloadPhase.running, name: name, progress: p);
          final text = p.writing
              ? '$name — wird geschrieben'
              : '$name — ${(p.fraction * 100).round()} %';
          unawaited(coordinator.update(_keepAliveKey, text));
        },
      );
      await ref.read(storedAreasProvider.notifier).refresh();
      state = AreaDownloadState(
          phase: AreaDownloadPhase.done, name: name, result: area);
      return area;
    } on AreaCancelled {
      state = const AreaDownloadState();
      return null;
    } catch (e, s) {
      if (!looksOffline(e)) logError('Kartenbereich speichern', e, s);
      state = AreaDownloadState(
          phase: AreaDownloadPhase.failed,
          name: name,
          error: looksOffline(e)
              ? 'Die Verbindung ist abgerissen. Nichts gespeichert — noch '
                  'einmal versuchen, sobald Empfang da ist.'
              : 'Der Bereich ließ sich nicht speichern.');
      return null;
    } finally {
      await archive?.close();
      await coordinator.stop(_keepAliveKey);
    }
  }

  void cancel() => _cancelled = true;

  void reset() {
    if (!state.busy) state = const AreaDownloadState();
  }
}

final areaDownloadProvider =
    NotifierProvider<AreaDownloadNotifier, AreaDownloadState>(
        AreaDownloadNotifier.new);

/// Die Archive der Bereiche mit Pfad — für MapLibre (`file://`). Leer im
/// Browser (dort gibt es keine Pfade und keine MapLibre-Engine).
final areaArchivePathsProvider =
    FutureProvider<List<({StoredArea area, String path})>>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  final store = ref.watch(areaStoreProvider);
  return [
    for (final area in areas)
      if (await store.archivePath(area.id) case final path?)
        (area: area, path: path),
  ];
});

/// Öffnet ein gespeichertes Archiv für die flutter_map-Engine — die Naht
/// für Tests.
final areaArchiveOpenerProvider = Provider<
    Future<PmTilesVectorTileProvider?> Function(
        AreaStore store, StoredArea area)>((ref) => _openArea);

Future<PmTilesVectorTileProvider?> _openArea(
    AreaStore store, StoredArea area) async {
  final path = await store.archivePath(area.id);
  if (path != null) return PmTilesVectorTileProvider.open(path);
  final bytes = await store.readArchive(area.id);
  if (bytes == null) return null;
  return PmTilesVectorTileProvider.openBytes(bytes);
}

/// Mehrere Bereiche als EINE Kachelquelle: Die erste, die die Kachel
/// hat, liefert; keine ⇒ 404 wie bei einer Kachel außerhalb.
class MultiAreaTileProvider extends VectorTileProvider {
  MultiAreaTileProvider(this._areas);

  final List<({StoredArea area, PmTilesVectorTileProvider provider})> _areas;

  Future<void> close() async {
    for (final a in _areas) {
      await a.provider.close();
    }
  }

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    ProviderException? last;
    for (final a in _areas) {
      if (tile.z < a.area.minZoom || tile.z > a.area.maxZoom) continue;
      try {
        return await a.provider.provide(tile);
      } on ProviderException catch (e) {
        last = e;
      }
    }
    throw last ??
        ProviderException(
            message: 'Kachel ${tile.key()} in keinem Bereich',
            retryable: Retryable.none,
            statusCode: 404);
  }

  @override
  int get minimumZoom => kAreaMinZoom;

  @override
  int get maximumZoom {
    var max = kAreaMinZoom;
    for (final a in _areas) {
      if (a.area.maxZoom > max) max = a.area.maxZoom;
    }
    return max;
  }

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}

/// Die Bereiche als oberste Kartenschicht der flutter_map-Engine — null,
/// wenn es keine gibt oder keiner aufgeht. Thema OHNE `background`, damit
/// die Karte darunter durchscheint, wo kein Bereich liegt.
final areaMapStyleProvider = FutureProvider<OfflineMapStyle?>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  if (areas.isEmpty) return null;
  final store = ref.watch(areaStoreProvider);
  final open = ref.watch(areaArchiveOpenerProvider);
  final opened = <({StoredArea area, PmTilesVectorTileProvider provider})>[];
  for (final area in areas) {
    try {
      final provider = await open(store, area);
      if (provider != null) opened.add((area: area, provider: provider));
    } catch (e, s) {
      // Ein Bereich, der nicht aufgeht, nimmt der Karte nicht den Rest.
      logError('Kartenbereich öffnen', e, s);
    }
  }
  if (opened.isEmpty) return null;
  final multi = MultiAreaTileProvider(opened);
  ref.onDispose(multi.close);
  final theme = await ref.watch(offlineThemeWithoutBackgroundProvider.future);
  return OfflineMapStyle(
      theme: theme, tileProviders: TileProviders({'protomaps': multi}));
});
