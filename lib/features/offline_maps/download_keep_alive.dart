import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_keep_alive_stub.dart'
    if (dart.library.io) 'download_keep_alive_service.dart';

/// Hält den App-Prozess wach, solange eine Offline-Karte lädt.
///
/// Ohne das friert Android den Prozess ein, sobald der Nutzer in eine andere
/// App wechselt: der Download läuft im Main-Isolate, und ein „cached"
/// Prozess wird ab Android 12 (bei manchen Herstellern deutlich früher)
/// eingefroren — Sockets und Timer stehen still. Verloren geht dabei nichts
/// (die `.part`-Datei bleibt, der nächste Versuch setzt per Range-Request
/// auf), aber der Fortschritt bleibt eben stehen.
///
/// Ein Foreground-Service mit sichtbarer Benachrichtigung hebt die
/// Prozess-Priorität an und nimmt ihn damit aus dem Freezer heraus.
abstract class DownloadKeepAlive {
  /// Startet den Service (oder aktualisiert nur den Text, wenn er läuft).
  Future<void> start(String text);

  /// Aktualisiert den Benachrichtigungstext.
  Future<void> update(String text);

  /// Beendet den Service. Muss auch nach Fehlern laufen.
  Future<void> stop();
}

/// Plattform-Implementierung: Foreground-Service auf Android, sonst nichts.
/// Tests überschreiben diesen Provider (siehe `test/fakes/test_app.dart`).
final downloadKeepAliveProvider =
    Provider<DownloadKeepAlive>((ref) => createDownloadKeepAlive());

/// Teilt den EINEN Foreground-Service unter mehreren Downloads auf.
///
/// Nötig seit dem Wald-Vorlauf (#264): Regionskarte und feines Waldgitter
/// können gleichzeitig laufen, und `stop()` des einen zog dem anderen den
/// Service unter den Füßen weg — also genau der eingefrorene Prozess,
/// gegen den er da ist. Gezählt wird über Schlüssel und nicht als bloße
/// Zahl, damit der Text sagen kann, was gerade läuft.
///
/// Kein `logError` und keine Fehlerbehandlung: Die dahinterliegende
/// Implementierung schluckt bereits alles — der Download ist wichtiger
/// als seine Benachrichtigung.
class DownloadKeepAliveCoordinator {
  DownloadKeepAliveCoordinator(this._keepAlive);

  final DownloadKeepAlive _keepAlive;

  /// Schlüssel → Text des jeweiligen Melders, in Anmeldereihenfolge.
  final _texts = <String, String>{};

  /// Meldet einen Download an und startet den Service, falls er ruht.
  Future<void> start(String key, String text) async {
    _texts[key] = text;
    await _keepAlive.start(_combined());
  }

  /// Neuer Text dieses Melders. Unbekannte Schlüssel und unveränderte
  /// Texte tun nichts — sonst schickte jeder einzelne Chunk eine
  /// Aktualisierung über den Platform-Channel.
  Future<void> update(String key, String text) async {
    if (_texts[key] == null || _texts[key] == text) return;
    _texts[key] = text;
    await _keepAlive.update(_combined());
  }

  /// Meldet einen Download ab. Der Service endet erst, wenn der letzte
  /// gegangen ist.
  Future<void> stop(String key) async {
    if (_texts.remove(key) == null) return;
    if (_texts.isEmpty) {
      await _keepAlive.stop();
      return;
    }
    await _keepAlive.update(_combined());
  }

  /// Läuft gerade irgendein Download? (Für Aufrufer, die nur wissen
  /// wollen, ob sie den Service noch brauchen.)
  bool get isEmpty => _texts.isEmpty;

  String _combined() => _texts.values.join(' · ');
}

/// Der Koordinator lebt so lange wie der ProviderScope — er ist die
/// gemeinsame Buchführung beider Downloads.
final downloadKeepAliveCoordinatorProvider =
    Provider<DownloadKeepAliveCoordinator>(
        (ref) => DownloadKeepAliveCoordinator(
            ref.watch(downloadKeepAliveProvider)));
