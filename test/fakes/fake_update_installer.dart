import 'package:pilzbuddy/core/update_check.dart';
import 'package:pilzbuddy/features/update/update_installer.dart';

/// Update-Weg ohne Netz und ohne Dateien.
///
/// Der echte [UpdateInstaller] lädt und schreibt wirklich — beides läuft in
/// `testWidgets` nicht durch, weil dort die Uhr und die Ereignisschleife
/// gestellt sind. Seine Logik hängt deshalb an `update_installer_test.dart`;
/// hier geht es nur um den Dialog: Fortschritt, Fehlermeldung, Rückfallweg.
class FakeUpdateInstaller implements UpdateInstaller {
  FakeUpdateInstaller({
    this.supported = true,
    this.failure,
    this.progressSteps = const [0.4, 1.0],
  });

  @override
  bool supported;

  /// Was der Versuch ergibt — `null` heißt: Installer wurde geöffnet.
  UpdateFailure? failure;

  final List<double> progressSteps;

  /// Wofür der Download angestoßen wurde, oder null.
  UpdateInfo? started;

  @override
  Future<UpdateFailure?> downloadAndInstall(
    UpdateInfo info, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async {
    started = info;
    for (final step in progressSteps) {
      onProgress?.call(step);
    }
    return failure;
  }
}
