/// Über welchen Kanal dieser Build ausgeliefert wird.
///
/// Der Play Store verbietet Apps, sich selbst zu aktualisieren oder Nutzer
/// zu APK-Downloads zu schicken („Device and Network Abuse"). Im Play-Build
/// entfällt deshalb der komplette Update-Pfad — dort erledigt das der Store.
/// Die GitHub-APK behält den Hinweis, weil sie sonst niemand aktualisiert.
///
/// Gesetzt beim Bauen: `flutter build appbundle --dart-define=PLAY_BUILD=true`
/// (siehe `.github/workflows/release.yml`). Ohne das Flag gilt der
/// GitHub-Kanal — der Standard für lokale Builds und die veröffentlichte APK.
abstract final class AppDistribution {
  static const isPlayBuild = bool.fromEnvironment('PLAY_BUILD');

  /// Zeigt die App selbst auf Updates hin? Nur außerhalb des Play Stores.
  static const showsUpdateHints = !isPlayBuild;
}
