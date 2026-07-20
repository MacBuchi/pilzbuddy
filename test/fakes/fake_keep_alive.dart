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

  @override
  Future<void> start(String text) async {
    if (!running) starts++;
    running = true;
    texts.add(text);
  }

  @override
  Future<void> update(String text) async {
    if (running) texts.add(text);
  }

  @override
  Future<void> stop() async => running = false;
}
