import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
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

/// Wartezeiten des Download-Managers — in Tests auf Millisekunden
/// überschreibbar.
final mapDownloadDelaysProvider =
    Provider<({Duration retry, Duration networkPoll})>((ref) =>
        (retry: const Duration(seconds: 5),
        networkPoll: const Duration(seconds: 3)));

/// Zustand eines laufenden Karten-Downloads.
class MapDownloadState {
  final double progress;

  /// true, wenn gerade kein Netz da ist und der Download auf die
  /// Rückkehr der Verbindung wartet (statt aufzugeben).
  final bool waitingForNetwork;

  const MapDownloadState(this.progress, {this.waitingForNetwork = false});
}

/// Laufende Karten-Downloads (Region-Key → Zustand). Lebt im
/// Root-ProviderScope und damit unabhängig vom Verwaltungs-Screen:
/// Tab-Wechsel oder Navigation brechen einen Download nicht ab (#38).
///
/// Geduldig bei schlechtem Netz: Gibt das Repository nach mehreren
/// fortschrittslosen Versuchen auf, übernimmt dieser Manager — er wartet
/// auf die Rückkehr der Verbindung und setzt automatisch fort, statt den
/// Nutzer neu tippen zu lassen. Nur nicht-netzwerkbedingte Fehler
/// (z. B. wiederholt falsche Prüfsumme) brechen wirklich ab.
class MapDownloadsNotifier extends Notifier<Map<String, MapDownloadState>> {
  final _cancelled = <String>{};

  /// Notbremse gegen Endlosschleifen bei dauerhaft kaputtem Server.
  static const _maxResumeRounds = 30;

  @override
  Map<String, MapDownloadState> build() => const {};

  void _set(String key, MapDownloadState value) =>
      state = {...state, key: value};

  /// Startet (oder setzt fort); wirft bei endgültigen Fehlern weiter,
  /// damit die UI eine Meldung zeigen kann. Läuft die Region schon,
  /// passiert nichts.
  Future<void> start(AvailableMap map) async {
    if (state.containsKey(map.key)) return;
    _cancelled.remove(map.key);
    _set(map.key, const MapDownloadState(0));
    try {
      var resumeRounds = 0;
      while (true) {
        try {
          await for (final progress in ref
              .read(offlineMapRepositoryProvider)
              .download(map,
                  isCancelled: () => _cancelled.contains(map.key))) {
            _set(map.key, MapDownloadState(progress));
          }
          break; // Fertig.
        } catch (e) {
          if (e is DownloadCancelled || e is FileSystemException) rethrow;
          resumeRounds++;
          if (resumeRounds >= _maxResumeRounds) rethrow;
          final delays = ref.read(mapDownloadDelaysProvider);
          // Ohne Netz warten wir sichtbar, statt Fehler zu zeigen …
          while (ref.read(noConnectivityProvider)) {
            if (_cancelled.contains(map.key)) {
              throw const DownloadCancelled();
            }
            _set(map.key,
                MapDownloadState(state[map.key]?.progress ?? 0,
                    waitingForNetwork: true));
            await Future<void>.delayed(delays.networkPoll);
          }
          // … und setzen mit Netz nach kurzer Pause automatisch fort.
          await Future<void>.delayed(delays.retry);
          if (_cancelled.contains(map.key)) {
            throw const DownloadCancelled();
          }
          _set(map.key, MapDownloadState(state[map.key]?.progress ?? 0));
        }
      }
      // Registry neu laden — auch wenn der Screen längst zu ist.
      ref.invalidate(installedMapsProvider);
    } on DownloadCancelled {
      // Kein Fehler: .part bleibt liegen, nächster Start setzt fort.
    } finally {
      state = {...state}..remove(map.key);
    }
  }

  /// Hält den Download an. Der Fortschritt bleibt gespeichert.
  void cancel(String key) => _cancelled.add(key);
}

final mapDownloadsProvider =
    NotifierProvider<MapDownloadsNotifier, Map<String, MapDownloadState>>(
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

/// Entpackt die mitgelieferte Übersichts-Basiskarte (DACH, Zoom 0–7)
/// einmalig aus den Assets ins Dateisystem und öffnet sie. Liefert null,
/// wenn das schiefgeht — die Übersicht ist nice-to-have, nie Pflicht.
Future<PmTilesVectorTileProvider?> _openBundledOverview() async {
  try {
    final data =
        await rootBundle.load('assets/offline_maps/overview_dach.pmtiles');
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/offline_maps/overview_dach.pmtiles');
    if (!await file.exists() || await file.length() != data.lengthInBytes) {
      await file.create(recursive: true);
      await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return await PmTilesVectorTileProvider.open(file.path);
  } catch (_) {
    return null;
  }
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
    // Regionskarten zuerst (liefern das Detail), die eingebaute
    // DACH-Übersicht als letzte Quelle — sie füllt alle Bereiche, für
    // die keine Region installiert ist, statt sie grau zu lassen.
    final overview = await _openBundledOverview();
    final providers = <PmTilesVectorTileProvider>[
      for (final map in installed)
        await PmTilesVectorTileProvider.open(map.filePath),
      ?overview,
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
