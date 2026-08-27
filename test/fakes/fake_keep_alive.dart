// Ersetzt den Foreground-Service im Test: protokolliert nur, statt einen
// Platform-Channel anzufassen (den es im Widget-Test nicht gibt).
import 'package:pilzbuddy/features/offline_maps/download_keep_alive.dart';

class FakeKeepAlive implements DownloadKeepAlive {
  /// true, solange der Service laufen würde.
  bool running = false;

  /// Wie oft der Service gestartet wurde (parallele Downloads sollen sich
  /// einen Service teilen, nicht mehrere starten).
  int starts = 0;

  /// Alle gesetzten Benachrichtigungstexte, in der Reihenfolge.
  final texts = <String>[];

  /// Und die Titel dazu — seit #338 sagt der Titel, WAS läuft.
  final titles = <String>[];

  /// Die Typen des zuletzt gestarteten Service. Android prüft je Typ die
  /// passende Berechtigung; eine Pilztour, die als `dataSync` startet,
  /// bekäme im Hintergrund keine Standorte mehr.
  Set<KeepAliveType> types = const {};

  @override
  Future<void> start(
      String title, String text, Set<KeepAliveType> serviceTypes) async {
    if (!running) starts++;
    running = true;
    types = serviceTypes;
    titles.add(title);
    texts.add(text);
  }

  @override
  Future<void> update(String title, String text) async {
    if (!running) return;
    titles.add(title);
    texts.add(text);
  }

  /// Der zuletzt gesetzte Takt des Service-Isolates — `null` heißt
  /// „kein Takt" (der Zustand für Downloads).
  Duration? repeat;

  @override
  Future<void> setRepeat(Duration? every) async => repeat = every;

  @override
  Future<void> stop() async => running = false;
}
