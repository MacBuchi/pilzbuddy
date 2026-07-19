import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'offline_map_repository.dart';
import 'pmtiles_tile_provider.dart';

final offlineMapRepositoryProvider =
    Provider<OfflineMapRepository>((ref) => OfflineMapRepository());

/// Verfügbare Regionskarten der Quelle (Release-Assets).
final availableMapsProvider = FutureProvider<List<AvailableMap>>(
    (ref) => ref.watch(offlineMapRepositoryProvider).fetchAvailable());

/// Heruntergeladene Karten auf dem Gerät.
class InstalledMapsNotifier extends AsyncNotifier<List<InstalledMap>> {
  @override
  Future<List<InstalledMap>> build() =>
      ref.read(offlineMapRepositoryProvider).listInstalled();

  Future<void> delete(String key) async {
    await ref.read(offlineMapRepositoryProvider).delete(key);
    ref.invalidateSelf();
    await future;
  }

  /// Nach einem Download von außen aufrufen (der Download selbst läuft im
  /// Screen, damit der Fortschritt dort angezeigt werden kann).
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final installedMapsProvider =
    AsyncNotifierProvider<InstalledMapsNotifier, List<InstalledMap>>(
        InstalledMapsNotifier.new);

/// Kartenquelle der Hauptkarte: false = Online-OSM (Default), true = Offline.
final offlineMapEnabledProvider = StateProvider<bool>((ref) => false);

/// Alles, was der Offline-Layer zum Rendern braucht.
class OfflineMapStyle {
  final vtr.Theme theme;
  final TileProviders tileProviders;

  const OfflineMapStyle({required this.theme, required this.tileProviders});
}

/// Baut Theme + Tile-Provider für die installierten Karten auf — oder null,
/// wenn Offline aus ist, nichts installiert ist oder das Laden fehlschlägt.
/// Fehler führen bewusst zu null (= Online-Fallback), nie zu einer roten
/// Karte: Der Vector-Stack ist Beta, Online-OSM bleibt das Sicherheitsnetz.
final offlineMapStyleProvider = FutureProvider<OfflineMapStyle?>((ref) async {
  if (!ref.watch(offlineMapEnabledProvider)) return null;
  final installed = ref.watch(installedMapsProvider).valueOrNull ?? const [];
  if (installed.isEmpty) return null;
  try {
    final styleText = await rootBundle
        .loadString('assets/map_style/protomaps_light_de.json');
    final styleJson = jsonDecode(styleText) as Map<String, dynamic>;
    final theme = vtr.ThemeReader().read(styleJson);
    final providers = <PmTilesVectorTileProvider>[
      for (final map in installed)
        await PmTilesVectorTileProvider.open(map.filePath),
    ];
    return OfflineMapStyle(
      theme: theme,
      // Quellname "protomaps" entspricht `sources.protomaps` im Style-JSON.
      tileProviders: TileProviders(
          {'protomaps': MultiPmTilesVectorTileProvider(providers)}),
    );
  } catch (_) {
    return null;
  }
});
