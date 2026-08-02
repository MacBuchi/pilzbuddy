import 'package:pilzbuddy/data/apk_installer.dart';

/// System-Installer im Test: merkt sich, was übergeben wurde, statt Androids
/// Installer zu öffnen. Der Method-Channel existiert im Widget-Test nicht.
class FakeApkInstaller implements ApkInstaller {
  FakeApkInstaller({
    this.supported = true,
    this.allowed = true,
    this.installSucceeds = true,
  });

  @override
  bool supported;

  /// Steht für die Freigabe „Unbekannte Apps installieren" (ab Android 8).
  bool allowed;

  /// Ließ sich der System-Installer öffnen?
  bool installSucceeds;

  /// Pfad der zuletzt übergebenen Datei — null, solange nichts kam.
  String? installedPath;

  int settingsOpened = 0;

  @override
  Future<bool> canInstall() async => supported && allowed;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<bool> install(String path) async {
    installedPath = path;
    return installSucceeds;
  }
}
