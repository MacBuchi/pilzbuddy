import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Öffentliche Links der App — für Einladungen und Hilfetexte.
class AppInfo {
  static const webAppUrl = 'https://macbuchi.github.io/pilzbuddy/';
  static const githubUrl = 'https://github.com/MacBuchi/pilzbuddy';
  static const apkDownloadUrl =
      'https://github.com/MacBuchi/pilzbuddy/releases/latest';

  /// Liegen als statische Seiten neben der Web-App (`web/*.html`) und sind
  /// damit auch ohne installierte App erreichbar — für die Konto-Löschung
  /// verlangt Google Play genau das.
  static const privacyUrl =
      'https://macbuchi.github.io/pilzbuddy/datenschutz.html';
  static const deleteAccountUrl =
      'https://macbuchi.github.io/pilzbuddy/konto-loeschen.html';

  static String inviteText(String? username) => [
        'Komm zu PilzBuddy 🍄 – wir teilen unsere Pilz-Spots!',
        'Web-App: $webAppUrl',
        'Android-App: $apkDownloadUrl',
        if (username != null && username.isNotEmpty)
          'Registriere dich und such mich dort als „$username", dann können wir uns verbinden.',
      ].join('\n');
}

/// Installierte App-Version für die „Über"-Sektion im Profil.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '–';
  }
});
