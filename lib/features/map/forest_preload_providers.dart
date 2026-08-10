// Das feine Waldgitter am Stück vorladen (#264).
//
// Warum es das gibt: Der Weg auf Bedarf (#253) holt einen Block, sobald
// die Kamera nah genug zur Ruhe kommt — richtig beim Gehen, aber die
// Daten kommen damit genau dort an, wo kein Empfang ist. Dieser Vorlauf
// ist der Gegenentwurf: einmal im WLAN alles holen, dann trägt die feine
// Stufe im Wald.
//
// Bewusst OHNE Gebietsauswahl: Der ganze Katalog sind ~26 MB gegen
// mehrere hundert je Regionskarte. Eine Bbox-Wahl wäre mehr Oberfläche,
// mehr Erklärung („welcher Teil ist geladen?") und mehr Code als die
// Daten wert sind.
//
// Die Geduld ist von `MapDownloadsNotifier` abgeschaut und aus demselben
// Grund: Wer im Wald anfängt und im Funkloch landet, soll keinen Fehler
// sehen, sondern einen Balken, der später weiterläuft.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/forest_block_repository.dart';
import '../offline_maps/download_keep_alive.dart';
import '../offline_maps/offline_map_providers.dart'
    show mapDownloadDelaysProvider, noConnectivityProvider;
import 'forest_block_providers.dart';

/// Was von der feinen Stufe auf dem Gerät liegt — samt Sollwerten, damit
/// die Kachel „18 von 30 Blöcken · 15 von 26 MB" sagen kann.
typedef ForestPreloadStatus = ({
  int blocks,
  int bytes,
  int totalBlocks,
  int totalBytes,
});

/// Zustand eines laufenden Vorlaufs; `null` heißt: läuft nicht.
class ForestPreloadState {
  const ForestPreloadState(this.progress, {this.waitingForNetwork = false});

  /// 0..1 über den GANZEN Katalog — bereits vorhandene Blöcke zählen mit,
  /// sonst spränge der Balken beim Fortsetzen zurück auf null.
  final double progress;

  /// Kein Netz: Der Vorlauf wartet auf die Rückkehr der Verbindung,
  /// statt aufzugeben.
  final bool waitingForNetwork;
}

/// Wie viel schon da ist. `null`, solange die Zustimmung fehlt — ohne sie
/// wird nicht einmal der Katalog geholt (#253), die Kachel nennt dann die
/// ungefähre Größe statt einer erfundenen Genauigkeit.
final forestPreloadStatusProvider =
    FutureProvider<ForestPreloadStatus?>((ref) async {
  final catalog = await ref.watch(forestBlockCatalogProvider.future);
  if (catalog == null) return null;
  final installed =
      await ref.watch(forestBlockRepositoryProvider).installedOf(catalog);
  return (
    blocks: installed.blocks,
    bytes: installed.bytes,
    totalBlocks: catalog.blocks.length,
    totalBytes: catalog.blocks.fold<int>(0, (sum, b) => sum + b.bytes),
  );
});

/// Ungefähre Gesamtgröße für die Kachel, bevor der Katalog gesehen werden
/// darf. Grobkörnig gehalten und als „rund" beschriftet: Die Daten werden
/// quartalsweise neu geschnitten, eine Nachkommastelle wäre eine
/// Genauigkeit, die diese Zahl nicht hat.
const forestPreloadApproxMb = 26;

class ForestPreloadNotifier extends Notifier<ForestPreloadState?> {
  /// Schlüssel am gemeinsamen Foreground-Service — der Karten-Download
  /// hat seinen eigenen, beide dürfen gleichzeitig laufen.
  static const _keepAliveKey = 'forest';

  /// Notbremse gegen Endlosschleifen bei dauerhaft kaputter Quelle.
  static const _maxResumeRounds = 30;

  var _cancelled = false;

  @override
  ForestPreloadState? build() => null;

  void _set(ForestPreloadState value) {
    state = value;
    unawaited(ref
        .read(downloadKeepAliveCoordinatorProvider)
        .update(_keepAliveKey, _notificationText(value)));
  }

  String _notificationText(ForestPreloadState value) {
    final percent = (value.progress * 100).round();
    return value.waitingForNetwork
        ? 'Waldkarte wartet auf Verbindung … $percent %'
        : 'Feine Waldkarte — $percent %';
  }

  /// Lädt alles Fehlende. Gibt zurück, ob der Katalog vollständig auf dem
  /// Gerät liegt — `false` heißt: von Hand angehalten.
  ///
  /// Wirft bei endgültigen Fehlern weiter, damit der Bildschirm eine
  /// Meldung zeigen kann.
  Future<bool> start() async {
    if (state != null) return false;
    _cancelled = false;
    _set(const ForestPreloadState(0));

    // Der Knopf IST die Zustimmung — dieselbe Regel wie beim Schalter im
    // Wald-Blatt (#253). Sie steht hier und nicht im Bildschirm, damit
    // kein zweiter Aufrufer sie vergessen kann: Ohne sie liefert der
    // Katalog-Provider grundsätzlich `null`, der Vorlauf liefe ins Leere.
    if (!ref.read(forestFineEnabledProvider)) {
      ref.read(forestFineEnabledProvider.notifier).state = true;
      await ref.read(settingsProvider).setForestFineEnabled(true);
    }

    final keepAlive = ref.read(downloadKeepAliveCoordinatorProvider);
    // Ohne Foreground-Service friert Android den Prozess beim App-Wechsel
    // ein — 26 MB sind schnell geladen, aber nicht so schnell, dass man
    // dabei nicht kurz woanders hinschaut.
    await keepAlive.start(_keepAliveKey, _notificationText(state!));
    try {
      final catalog = await ref.read(forestBlockCatalogProvider.future);
      // Kein Katalog heißt: keine Verbindung und noch nie einen gesehen.
      // Als Fehlschlag behandeln, nicht als „nichts zu tun" — sonst
      // meldete der Bildschirm Erfolg für einen Vorlauf, der nie lief.
      if (catalog == null) {
        throw const ForestBlockDownloadFailed('forest_blocks.json');
      }

      final repository = ref.read(forestBlockRepositoryProvider);
      var resumeRounds = 0;
      while (true) {
        try {
          await for (final progress in repository.downloadAll(catalog,
              isCancelled: () => _cancelled)) {
            _set(ForestPreloadState(progress));
          }
          break; // Fertig oder angehalten.
        } catch (e) {
          // Volle Platte: Wiederholen hilft nicht.
          if (e is FileSystemException) rethrow;
          resumeRounds++;
          if (resumeRounds >= _maxResumeRounds) rethrow;
          final delays = ref.read(mapDownloadDelaysProvider);
          while (ref.read(noConnectivityProvider)) {
            if (_cancelled) return false;
            _set(ForestPreloadState(state?.progress ?? 0,
                waitingForNetwork: true));
            await Future<void>.delayed(delays.networkPoll);
          }
          await Future<void>.delayed(delays.retry);
          if (_cancelled) return false;
          _set(ForestPreloadState(state?.progress ?? 0));
        }
      }
      // Die Karte soll die neuen Blöcke sofort nehmen, nicht erst nach
      // einem Neustart.
      ref.invalidate(forestPreloadStatusProvider);
      ref.invalidate(forestBlockSetProvider);
      return !_cancelled;
    } finally {
      state = null;
      await keepAlive.stop(_keepAliveKey);
    }
  }

  /// Hält den Vorlauf an. Geladene Blöcke bleiben liegen; ein neuer Start
  /// setzt dort auf.
  void cancel() => _cancelled = true;

  /// Wirft die feinen Blöcke vom Gerät und liefert, wie viel frei wurde.
  Future<int> delete() async {
    final freed =
        await ref.read(forestBlockRepositoryProvider).deleteBlocks();
    ref.invalidate(forestPreloadStatusProvider);
    ref.invalidate(forestBlockSetProvider);
    return freed;
  }
}

final forestPreloadProvider =
    NotifierProvider<ForestPreloadNotifier, ForestPreloadState?>(
        ForestPreloadNotifier.new);
