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
