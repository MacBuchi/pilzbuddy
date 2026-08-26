import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../map/live_share_providers.dart' show appInForegroundProvider;
import 'download_keep_alive.dart';
import 'network_metering.dart';
import 'offline_map_repository.dart';
import 'pmtiles_tile_provider.dart';
import 'region_catalog.dart';

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

  /// Unter diesem Schlüssel meldet sich der Karten-Download beim
  /// gemeinsamen Foreground-Service an — der Wald-Vorlauf (#264) hat
  /// seinen eigenen.
  static const _keepAliveKey = 'maps';

  void _set(String key, MapDownloadState value) {
    state = {...state, key: value};
    _syncNotification();
  }

  /// Text der Service-Benachrichtigung aus dem aktuellen Zustand.
  String _notificationText() {
    final entries = state.entries.toList();
    if (entries.isEmpty) return 'Wird vorbereitet …';
    if (entries.length == 1) {
      final download = entries.single.value;
      final percent = (download.progress * 100).round();
      return download.waitingForNetwork
          ? 'Wartet auf Verbindung … $percent %'
          : '${regionLabel(entries.single.key)} — $percent %';
    }
    final average =
        entries.map((e) => e.value.progress).reduce((a, b) => a + b) /
            entries.length;
    return '${entries.length} Karten — ${(average * 100).round()} %';
  }

  /// Der Koordinator entprellt selbst (gleicher Text ⇒ kein Kanalaufruf),
  /// deshalb darf das hier bei jedem Chunk laufen.
  void _syncNotification() {
    unawaited(ref
        .read(downloadKeepAliveCoordinatorProvider)
        .update(_keepAliveKey, _notificationText()));
  }

  /// Startet (oder setzt fort); wirft bei endgültigen Fehlern weiter,
  /// damit die UI eine Meldung zeigen kann. Läuft die Region schon,
  /// passiert nichts.
  Future<void> start(AvailableMap map) async {
    if (state.containsKey(map.key)) return;
    _cancelled.remove(map.key);
    _set(map.key, const MapDownloadState(0));
    // Ohne Foreground-Service friert Android den Prozess ein, sobald der
    // Nutzer die App wechselt — der Download stünde still.
    final keepAlive = ref.read(downloadKeepAliveCoordinatorProvider);
    await keepAlive.start(_keepAliveKey, _notificationText());
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
      // Service nur abmelden, wenn wirklich keine KARTE mehr lädt —
      // parallele Downloads teilen sich einen Service, und ob er dann
      // wirklich endet, entscheidet der Koordinator (der Wald-Vorlauf
      // kann noch laufen).
      if (state.isEmpty) {
        await keepAlive.stop(_keepAliveKey);
      } else {
        _syncNotification();
      }
    }
  }

  /// Hält den Download an. Der Fortschritt bleibt gespeichert.
  void cancel(String key) => _cancelled.add(key);
}

final mapDownloadsProvider =
    NotifierProvider<MapDownloadsNotifier, Map<String, MapDownloadState>>(
        MapDownloadsNotifier.new);

/// Kartenquelle der Hauptkarte: false = Online-OSM (Default), true = Offline.
///
/// Überdauert den Neustart (Issue #145). Vorher war das ein reiner
/// Speicherzustand — wer im Wald bewusst umschaltete, stand nach jedem
/// Neustart wieder auf Online. Die Wahl gilt bewusst unverfallbar weiter,
/// auch bei gutem Empfang: Sie überraschend zurückzudrehen wäre schlimmer
/// als eine Offline-Karte trotz Netz, und der Weg zurück ist ein Tipp.
class OfflineMapEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).offlineMapEnabled;

  /// Wechselt die Quelle. Der Zustand springt sofort, das Speichern läuft
  /// nach — eine Karte, die auf einen Schreibvorgang wartet, wäre für die
  /// Nutzerin ein Hänger. Scheitert das Speichern, bleibt die Umschaltung
  /// für diese Sitzung trotzdem gültig; verloren geht nur das Merken.
  void toggle() {
    final value = !state;
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setOfflineMapEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Kartenquelle merken', e, stackTrace);
    }));
  }
}

final offlineMapEnabledProvider =
    NotifierProvider<OfflineMapEnabledNotifier, bool>(
        OfflineMapEnabledNotifier.new);

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

/// Kostet die aktive Verbindung Datenvolumen? Nur der Auto-Nachlauf
/// (#332) fragt das; in Tests überschrieben.
final networkMeteringProvider =
    Provider<NetworkMetering>((ref) => const PlatformNetworkMetering());

/// Ein Netz, in dem sich mehrere hundert MB ohne schlechtes Gewissen
/// laden lassen (#332).
///
/// „WLAN" allein reicht als Maßstab NICHT: Ein Handy-Hotspot ist für
/// `connectivity_plus` WLAN und kostet trotzdem — und das ist genau die
/// Verbindung, die man unterwegs benutzt. Deshalb zwei Bedingungen, und
/// beide müssen halten: ein Transportweg, der kein Mobilfunk ist, UND
/// eine Verbindung, die Android nicht als kostenpflichtig führt.
///
/// Rein und ohne Riverpod, damit jede Kombination ohne Gerät prüfbar ist.
bool isFreeNetwork(List<ConnectivityResult> results, {required bool metered}) {
  if (metered) return false;
  if (results.isEmpty) return false;
  if (results.every((r) => r == ConnectivityResult.none)) return false;
  // Mobilfunk auch dann nicht, wenn der Tarif als unbegrenzt gemeldet
  // wird: „unbegrenzt" heißt bei den meisten Verträgen gedrosselt, nicht
  // kostenlos.
  if (results.contains(ConnectivityResult.mobile)) return false;
  return true;
}

/// [isFreeNetwork] für die aktuelle Verbindung. Wird bei jedem
/// Verbindungswechsel neu beantwortet — die Metered-Auskunft ist eine
/// Momentaufnahme, kein Strom.
final freeNetworkProvider = FutureProvider<bool>((ref) async {
  final results = ref.watch(connectivityProvider).valueOrNull ?? const [];
  // Der Transportweg entscheidet schon die meisten Fälle und spart dabei
  // den Sprung nach Android.
  if (!isFreeNetwork(results, metered: false)) return false;
  final metered = await ref.read(networkMeteringProvider).isMetered();
  return isFreeNetwork(results, metered: metered);
});

/// Darf die App veraltete Regionen im freien Netz von selbst nachladen?
/// (#332) Muster [OfflineMapEnabledNotifier]: Zustand springt sofort,
/// Speichern läuft nach, ein Fehler beim Merken wird nur protokolliert.
class MapAutoUpdateEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).mapAutoUpdateEnabled;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setMapAutoUpdateEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Auto-Update der Karten merken', e, stackTrace);
    }));
  }
}

final mapAutoUpdateEnabledProvider =
    NotifierProvider<MapAutoUpdateEnabledNotifier, bool>(
        MapAutoUpdateEnabledNotifier.new);

/// Was der Auto-Nachlauf jetzt tun soll — als reine Funktion, damit jede
/// Regel ohne Netz, Platte und Widget prüfbar ist.
///
/// Zwei Ausgänge, weil es zwei Richtungen gibt. Das Starten ist die
/// offensichtliche; das ANHALTEN ist die, die man leicht vergisst:
/// [MapDownloadsNotifier] ist mit Absicht geduldig und setzt bei jeder
/// zurückkehrenden Verbindung fort — auch über Mobilfunk. Für einen
/// Download, den die Nutzerin angetippt hat, ist das richtig. Für einen,
/// den die App selbst begonnen hat, wäre es ein Loch: Wer mit laufendem
/// Nachlauf das Haus verlässt, lädt 1,7 GB aus seinem Datentarif.
({AvailableMap? start, List<String> pause}) planAutoMapUpdate({
  required bool enabled,
  required bool freeNetwork,
  required bool inForeground,
  required List<AvailableMap> outdated,
  required Set<String> running,
  required Set<String> autoStarted,
  required Set<String> failed,
}) {
  // Anhalten hängt NICHT am Vordergrund: Das freie Netz kann auch
  // verschwinden, während die App in der Tasche steckt.
  if (!enabled || !freeNetwork) {
    final pause = autoStarted.intersection(running).toList()..sort();
    return (start: null, pause: pause);
  }
  // Nicht mit einem laufenden Download um die Leitung streiten — auch
  // nicht mit einem eigenen. Immer nur EINE Region auf einmal: So bleibt
  // die Service-Meldung lesbar („Berlin — 12 %") und ein Abbruch kostet
  // höchstens einen halben Download.
  if (!inForeground || running.isNotEmpty) return (start: null, pause: const []);
  for (final map in outdated) {
    if (!failed.contains(map.key)) return (start: map, pause: const []);
  }
  return (start: null, pause: const []);
}

/// Der Auslöser, der #332 gefehlt hat: veraltete Regionen im freien Netz
/// von selbst nachladen.
///
/// Alles darunter war schon gebaut — der Versionsvergleich, das Banner
/// und vor allem der Failsafe (in eine `.part`-Datei laden, SHA-256
/// prüfen, erst dann atomar über die alte Karte legen). Hier kommt nur
/// dazu, WANN das ohne Tippen passiert.
///
/// Der Zustand ist die Menge der Regionen, die dieser Nachlauf gerade
/// selbst lädt — daran unterscheidet er beim Anhalten seine eigenen
/// Downloads von denen, die jemand angetippt hat.
class MapAutoUpdateNotifier extends Notifier<Set<String>> {
  /// Regionen, die in dieser Sitzung endgültig gescheitert sind. Ohne
  /// diese Merkliste liefe eine Karte, die der Server dauerhaft nicht
  /// hergibt, bei jedem Verbindungswechsel erneut an. Ein ANGEHALTENER
  /// Download zählt nicht dazu — der wirft nicht, er kommt wieder.
  final _failed = <String>{};

  @override
  Set<String> build() => const {};

  /// Einmal nachsehen, ob etwas zu tun ist. Angestoßen bei jedem Wechsel
  /// der Zutaten (siehe [mapAutoUpdateInputsProvider]).
  void sync() {
    final plan = planAutoMapUpdate(
      enabled: ref.read(mapAutoUpdateEnabledProvider),
      freeNetwork: ref.read(freeNetworkProvider).valueOrNull ?? false,
      inForeground: ref.read(appInForegroundProvider),
      outdated: ref.read(outdatedMapsProvider),
      running: ref.read(mapDownloadsProvider).keys.toSet(),
      autoStarted: state,
      failed: _failed,
    );
    for (final key in plan.pause) {
      // Hält an, statt zu verwerfen: Die .part-Datei bleibt liegen, der
      // nächste Lauf setzt genau dort fort.
      ref.read(mapDownloadsProvider.notifier).cancel(key);
    }
    final map = plan.start;
    if (map == null) return;
    state = {...state, map.key};
    unawaited(_run(map));
  }

  Future<void> _run(AvailableMap map) async {
    try {
      await ref.read(mapDownloadsProvider.notifier).start(map);
    } catch (e, stackTrace) {
      // Kein Weg, das der Nutzerin zu zeigen — sie hat nichts angetippt.
      // Also protokollieren und diese Region in dieser Sitzung ruhen
      // lassen; von Hand geht sie weiterhin.
      _failed.add(map.key);
      logError('Karten-Auto-Update ${map.key}', e, stackTrace);
    } finally {
      state = {...state}..remove(map.key);
    }
  }
}

final mapAutoUpdateProvider =
    NotifierProvider<MapAutoUpdateNotifier, Set<String>>(
        MapAutoUpdateNotifier.new);

/// Die Zutaten der Auto-Entscheidung in EINEM Wert.
///
/// Als Record, weil Records strukturell vergleichen: Der Karten-Screen
/// kommt damit mit einem einzigen `ref.listen` aus, und der feuert nur,
/// wenn sich wirklich etwas geändert hat. Die Regionen stehen bewusst als
/// zusammengefügte Schlüssel darin und nicht als Liste — zwei inhaltlich
/// gleiche Listen sind für `==` verschieden, und der Nachlauf liefe bei
/// jedem Neuaufbau erneut an.
typedef MapAutoUpdateInputs = ({
  bool enabled,
  bool freeNetwork,
  bool inForeground,
  String outdatedKeys,
  String runningKeys,
});

final mapAutoUpdateInputsProvider = Provider<MapAutoUpdateInputs>((ref) => (
      enabled: ref.watch(mapAutoUpdateEnabledProvider),
      freeNetwork: ref.watch(freeNetworkProvider).valueOrNull ?? false,
      inForeground: ref.watch(appInForegroundProvider),
      outdatedKeys: [for (final m in ref.watch(outdatedMapsProvider)) m.key]
          .join(','),
      runningKeys: (ref.watch(mapDownloadsProvider).keys.toList()..sort())
          .join(','),
    ));

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

/// Das Renderthema — einmal geladen, für immer gecacht (statisches Asset).
final _offlineThemeProvider = FutureProvider<vtr.Theme>((ref) async {
  final styleText =
      await rootBundle.loadString('assets/map_style/protomaps_light_de.json');
  return vtr.ThemeReader().read(jsonDecode(styleText) as Map<String, dynamic>);
});

/// Dasselbe Thema ohne die `background`-Ebene — für jeden Layer, unter dem
/// noch etwas liegt.
///
/// Die Ebene malt `#cccccc` deckend über die volle Kachelfläche, auch für
/// Kacheln ganz ohne Daten (der Renderer zeichnet ein leeres Tileset gegen
/// dasselbe Thema). Im Detail-Layer würde sie damit exakt dort die
/// Basiskarte zudecken, wo diese gebraucht wird — an den Rändern der
/// Regionskarten. Das Style-Asset selbst bleibt unangetastet: Es ist
/// generiert (siehe CLAUDE.md), gefiltert wird beim Laden.
final _offlineThemeWithoutBackgroundProvider =
    FutureProvider<vtr.Theme>((ref) async {
  final styleText =
      await rootBundle.loadString('assets/map_style/protomaps_light_de.json');
  final style = jsonDecode(styleText) as Map<String, dynamic>;
  return vtr.ThemeReader().read(styleWithoutBackground(style));
});

/// Entfernt die `background`-Ebene aus einem Style-JSON (Kopie, das
/// Original bleibt unberührt). Eigene Funktion, damit prüfbar ist, dass
/// wirklich nur diese eine Ebene verschwindet — siehe map_style_test.dart.
Map<String, dynamic> styleWithoutBackground(Map<String, dynamic> style) => {
      ...style,
      'layers': (style['layers'] as List)
          .where((layer) => (layer as Map)['type'] != 'background')
          .toList(),
    };

/// Die mitgelieferte Übersichtskarte als eigene, IMMER verfügbare Quelle.
///
/// Sie hängt weder am Offline-Schalter noch an installierten Regionen:
/// Sie ist die unterste Schicht der Karte und sorgt dafür, dass unter dem
/// Finger nie eine leere Fläche liegt (Issues #118/#119). Weil sie ein
/// eigener Layer mit eigenem Provider ist, meldet dieser `maximumZoom = 7`
/// — und genau daran erkennt der Renderer, dass er für höhere Zoomstufen
/// die z7-Kachel holen und hochskalieren soll (`SlippyMapTranslator` in
/// `vector_tile_loading_cache.dart`). In der gemeinsamen Quelle mit den
/// Regionen ging das nicht: Dort galt deren `maximumZoom`, und die
/// Übersicht wurde nach Kacheln gefragt, die es in ihr nie gab.
final baseMapStyleProvider = FutureProvider<OfflineMapStyle?>((ref) async {
  try {
    final overview = await _openBundledOverview();
    if (overview == null) return null;
    ref.onDispose(overview.close);
    final theme = await ref.watch(_offlineThemeProvider.future);
    return OfflineMapStyle(
      theme: theme,
      tileProviders: TileProviders({'protomaps': overview}),
    );
  } catch (_) {
    // Wie überall im Offline-Pfad: still degradieren. Ohne Basiskarte
    // sieht man den Hintergrundton, aber nie einen Fehler.
    return null;
  }
});

/// Die Offline-Kachelquellen. Hängt NUR an den installierten Karten —
/// Verbindungswechsel oder das Umschalten online/offline öffnen die
/// Archive nicht neu. Beim Neuaufbau (Karte installiert/gelöscht) werden
/// die alten Archive geschlossen, sonst leaken Dateihandles
/// (#Karten-Freezes).
final _offlineTileSourceProvider =
    FutureProvider<MultiPmTilesVectorTileProvider?>((ref) async {
  final installed = ref.watch(installedMapsProvider).valueOrNull ?? const [];
  if (installed.isEmpty) return null;
  final providers = <PmTilesVectorTileProvider>[];
  ref.onDispose(() {
    for (final provider in providers) {
      provider.close();
    }
  });
  try {
    // Nur die Regionskarten: Die DACH-Übersicht liegt seit #118 als
    // eigener Layer darunter (baseMapStyleProvider). Hier mit drin wäre
    // sie wirkungslos — die Quelle meldet dann das Maximum aller Archive
    // als maximumZoom, und die Übersicht würde nach z12-Kacheln gefragt,
    // die es in ihr nicht gibt.
    for (final map in installed) {
      providers.add(await PmTilesVectorTileProvider.open(map.filePath));
    }
    return MultiPmTilesVectorTileProvider(providers);
  } catch (_) {
    return null;
  }
});

/// Kombiniert Theme + Kachelquellen zum Offline-Style — oder null, wenn
/// Offline aus ist, nichts installiert ist oder das Laden fehlschlägt.
/// Fehler führen bewusst zu null (= Online-Fallback), nie zu einer roten
/// Karte: Der Vector-Stack ist Beta, Online-OSM bleibt das Sicherheitsnetz.
/// Theme und Quellen sind gecacht — dieser Provider selbst macht kein I/O.
final offlineMapStyleProvider = FutureProvider<OfflineMapStyle?>((ref) async {
  final manuallyEnabled = ref.watch(offlineMapEnabledProvider);
  final autoOffline = ref.watch(noConnectivityProvider);
  if (!manuallyEnabled && !autoOffline) return null;
  try {
    final tiles = await ref.watch(_offlineTileSourceProvider.future);
    if (tiles == null) return null;
    // Ohne Hintergrund-Ebene: Unter dem Detail-Layer liegt die Basiskarte.
    final theme =
        await ref.watch(_offlineThemeWithoutBackgroundProvider.future);
    return OfflineMapStyle(
      theme: theme,
      // Quellname "protomaps" entspricht `sources.protomaps` im Style-JSON.
      tileProviders: TileProviders({'protomaps': tiles}),
    );
  } catch (_) {
    return null;
  }
});
