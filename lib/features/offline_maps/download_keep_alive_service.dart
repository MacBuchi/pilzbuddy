import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/errors.dart';
import 'download_keep_alive.dart';

/// Der Service braucht einen Task-Handler, tut darin aber bewusst nichts:
/// Der Download läuft weiter im Main-Isolate. Gebraucht wird allein die
/// Prozess-Priorität, die ein laufender Foreground-Service mitbringt.
@pragma('vm:entry-point')
void startDownloadKeepAlive() =>
    FlutterForegroundTask.setTaskHandler(_IdleTaskHandler());

/// Der Manifest-Eintrag, unter dem das Symbol der Download-Meldung steht
/// (#331). Muss Zeichen für Zeichen dem `meta-data`-Namen im Manifest
/// entsprechen.
const downloadNotificationIconMetaData =
    'de.mcbuchi.pilzbuddy.DOWNLOAD_NOTIFICATION_ICON';

class _IdleTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class _ForegroundServiceKeepAlive implements DownloadKeepAlive {
  static const _serviceId = 4711;
  bool _initialized = false;

  /// Nur Android hat den Freezer und den Service. Auf iOS/Desktop läuft der
  /// Download ohnehin weiter, dort bleibt das hier ein No-op.
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _initOnce() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        // Die Kanal-ID bleibt: Eine neue legte einen zweiten Eintrag in
        // den Systemeinstellungen an und ließe den alten als Leiche
        // zurück. Name und Beschreibung nennen seit #264 beide Nutzer
        // des Kanals — das Waldgitter lädt über denselben Service.
        channelId: 'map_download',
        channelName: 'Downloads',
        channelDescription:
            'Läuft, solange Karten oder Walddaten heruntergeladen werden.',
        // Nicht bei jeder Prozentzahl erneut piepen.
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Kein periodisches Event nötig — der Handler ist absichtlich leer.
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> start(String text) async {
    if (!_supported) return;
    try {
      _initOnce();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationText: text);
        return;
      }
      // Ohne die Berechtigung läuft der Service trotzdem, nur unsichtbar —
      // deshalb ist ein abgelehnter Dialog kein Grund abzubrechen.
      await FlutterForegroundTask.requestNotificationPermission();
      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        // Ohne das zeigt auch diese Meldung das Launcher-Icon als
        // Silhouette — denselben weißen Klotz wie die Push-Meldung vor
        // #331. Das Plugin sucht das Drawable ausschließlich über diesen
        // Namen in den Manifest-Meta-Daten; findet es ihn nicht, setzt es
        // stumm die Ressourcen-id 0. Deshalb steht der Name als Konstante
        // da und ein Test hält ihn mit dem Manifest zusammen.
        notificationIcon: const NotificationIcon(
          metaDataName: downloadNotificationIconMetaData,
        ),
        // Neutral, weil sich Karten-Download und Wald-Vorlauf denselben
        // Service teilen — der Text darunter nennt, was gerade läuft.
        notificationTitle: 'Offline-Daten werden geladen',
        notificationText: text,
        callback: startDownloadKeepAlive,
      );
    } catch (e, stackTrace) {
      // Der Download ist wichtiger als die Benachrichtigung: schlägt der
      // Service fehl, läuft eben nur im Vordergrund weiter.
      logError('Karten-Download: Foreground-Service starten', e, stackTrace);
    }
  }

  @override
  Future<void> update(String text) async {
    if (!_supported) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(notificationText: text);
    } catch (e, stackTrace) {
      logError('Karten-Download: Benachrichtigung aktualisieren', e,
          stackTrace);
    }
  }

  @override
  Future<void> stop() async {
    if (!_supported) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.stopService();
    } catch (e, stackTrace) {
      logError('Karten-Download: Foreground-Service beenden', e, stackTrace);
    }
  }
}

DownloadKeepAlive createDownloadKeepAlive() => _ForegroundServiceKeepAlive();
