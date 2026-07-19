import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
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

/// Laufende Karten-Downloads (Region-Key → Fortschritt 0..1). Lebt im
/// Root-ProviderScope und damit unabhängig vom Verwaltungs-Screen:
/// Tab-Wechsel oder Navigation brechen einen Download nicht mehr ab (#38).
class MapDownloadsNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  /// Startet den Download; wirft bei Fehlern weiter, damit die UI (falls
  /// noch sichtbar) eine Meldung zeigen kann. Läuft die Region schon,
  /// passiert nichts.
  Future<void> start(AvailableMap map) async {
    if (state.containsKey(map.key)) return;
    state = {...state, map.key: 0};
    try {
      await for (final progress
          in ref.read(offlineMapRepositoryProvider).download(map)) {
        state = {...state, map.key: progress};
      }
      // Registry neu laden — auch wenn der Screen längst zu ist.
      ref.invalidate(installedMapsProvider);
    } finally {
      state = {...state}..remove(map.key);
    }
  }
}

final mapDownloadsProvider =
    NotifierProvider<MapDownloadsNotifier, Map<String, double>>(
        MapDownloadsNotifier.new);

/// Kartenquelle der Hauptkarte: false = Online-OSM (Default), true = Offline.
final offlineMapEnabledProvider = StateProvider<bool>((ref) => false);

/// Verbindungsstatus des Geräts (connectivity_plus).
final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
    (ref) => Connectivity().onConnectivityChanged);

/// Kein Empfang? Dann schaltet die Karte automatisch auf offline,
/// sobald eine Karte installiert ist — im Wald muss man nichts tun.
final noConnectivityProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).valueOrNull;
  if (results == null) return false;
  return results.isEmpty ||
      results.every((r) => r == ConnectivityResult.none);
});

/// Das „Karten-Abo": installierte Regionen, für die die Quelle eine
/// neuere Version anbietet (Vergleich über den Datumsstempel im Namen).
final outdatedMapsProvider = Provider<List<AvailableMap>>((ref) {
  final installed = ref.watch(installedMapsProvider).valueOrNull ?? const [];
  if (installed.isEmpty) return const [];
  final available = ref.watch(availableMapsProvider).valueOrNull ?? const [];
  final installedByKey = {for (final m in installed) m.key: m};
  return [
    for (final map in available)
      if (installedByKey[map.key] != null &&
          installedByKey[map.key]!.dateStamp.compareTo(map.dateStamp) < 0)
        map,
  ];
});

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
  final manuallyEnabled = ref.watch(offlineMapEnabledProvider);
  final autoOffline = ref.watch(noConnectivityProvider);
  if (!manuallyEnabled && !autoOffline) return null;
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
