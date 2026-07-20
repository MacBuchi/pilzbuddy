import 'download_keep_alive.dart';

/// Web: es gibt keinen Prozess, den man wachhalten müsste — und Offline-
/// Karten gibt es dort ohnehin nicht.
class _NoKeepAlive implements DownloadKeepAlive {
  const _NoKeepAlive();

  @override
  Future<void> start(String text) async {}

  @override
  Future<void> update(String text) async {}

  @override
  Future<void> stop() async {}
}

DownloadKeepAlive createDownloadKeepAlive() => const _NoKeepAlive();
