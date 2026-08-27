import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/errors.dart';
import '../tour/tour_task_handler.dart';
import 'download_keep_alive.dart';

/// Der Einstiegspunkt des Service-Isolates.
///
/// Für den Download tut der Handler nichts — der läuft im Main-Isolate,
/// gebraucht wird allein die Prozess-Priorität. Für eine **Pilztour**
/// misst er (#342): Deren Arbeit MUSS hier passieren, weil dieses Isolate
/// das Wegwischen der App überlebt und der Main-Isolate nicht.
///
/// Der Service hat genau einen Einstiegspunkt, also trägt ein Handler
/// beide Fälle; welcher gilt, steht in der Isolat-Brücke
/// (`kTourDataActive`).
@pragma('vm:entry-point')
void startDownloadKeepAlive() =>
    FlutterForegroundTask.setTaskHandler(ServiceTaskHandler());

/// Der Manifest-Eintrag, unter dem das Symbol der Download-Meldung steht
/// (#331). Muss Zeichen für Zeichen dem `meta-data`-Namen im Manifest
/// entsprechen.
const downloadNotificationIconMetaData =
    'de.mcbuchi.pilzbuddy.DOWNLOAD_NOTIFICATION_ICON';

class _ForegroundServiceKeepAlive implements DownloadKeepAlive {
  static const _serviceId = 4711;
  bool _initialized = false;

  /// Nur Android hat den Freezer und den Service. Auf iOS/Desktop läuft der
  /// Download ohnehin weiter, dort bleibt das hier ein No-op.
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Die Optionen des Service-Isolates. `every == null` heißt „kein
  /// Takt" — der Zustand für Downloads.
  ///
  /// `allowWakeLock` ist hier keine Bequemlichkeit: Ohne ihn schläft die
  /// CPU zwischen den Takten, und eine Pilztour bekäme ihre Messungen
  /// gebündelt beim nächsten Aufwachen statt im eingestellten Abstand.
  static ForegroundTaskOptions _options(Duration? every) =>
      ForegroundTaskOptions(
        eventAction: every == null
            ? ForegroundTaskEventAction.nothing()
            : ForegroundTaskEventAction.repeat(every.inMilliseconds),
        allowWakeLock: true,
        allowWifiLock: true,
      );

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
        channelDescription: 'Läuft, solange Karten oder Walddaten '
            'heruntergeladen werden oder eine Pilztour aufzeichnet.',
        // Nicht bei jeder Prozentzahl erneut piepen.
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: _options(null),
    );
    _initialized = true;
  }

  @override
  Future<void> start(
      String title, String text, Set<KeepAliveType> types) async {
    if (!_supported) return;
    try {
      _initOnce();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: title, notificationText: text);
        return;
      }
      // Ohne die Berechtigung läuft der Service trotzdem, nur unsichtbar —
      // deshalb ist ein abgelehnter Dialog kein Grund abzubrechen.
      await FlutterForegroundTask.requestNotificationPermission();
      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        // Je Start entschieden, nicht fest verdrahtet (#338): Ein
        // Karten-Download nennt `dataSync`, eine Pilztour `location`.
        // Einen Typ zu nennen, den dieser Lauf gar nicht braucht, wäre
        // gegenüber Play eine falsche Angabe — und das Manifest deklariert
        // beide nur als Obermenge dessen, was vorkommen KANN.
        serviceTypes: [
          for (final type in types)
            switch (type) {
              KeepAliveType.dataSync => ForegroundServiceTypes.dataSync,
              KeepAliveType.location => ForegroundServiceTypes.location,
            },
        ],
        // Ohne das zeigt auch diese Meldung das Launcher-Icon als
        // Silhouette — denselben weißen Klotz wie die Push-Meldung vor
        // #331. Das Plugin sucht das Drawable ausschließlich über diesen
        // Namen in den Manifest-Meta-Daten; findet es ihn nicht, setzt es
        // stumm die Ressourcen-id 0. Deshalb steht der Name als Konstante
        // da und ein Test hält ihn mit dem Manifest zusammen.
        notificationIcon: const NotificationIcon(
          metaDataName: downloadNotificationIconMetaData,
        ),
        notificationTitle: title,
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
  Future<void> update(String title, String text) async {
    if (!_supported) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
          notificationTitle: title, notificationText: text);
    } catch (e, stackTrace) {
      logError('Karten-Download: Benachrichtigung aktualisieren', e,
          stackTrace);
    }
  }

  @override
  Future<void> setRepeat(Duration? every) async {
    if (!_supported) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      // Anders als die Service-Typen lässt sich der Takt am laufenden
      // Service ändern — genau deshalb braucht die Tour dafür keinen
      // Neustart.
      await FlutterForegroundTask.updateService(
          foregroundTaskOptions: _options(every));
    } catch (e, stackTrace) {
      logError('Foreground-Service: Takt setzen', e, stackTrace);
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
