/// Öffentliche Links der App — für Einladungen und Hilfetexte.
class AppInfo {
  static const webAppUrl = 'https://macbuchi.github.io/pilzbuddy/';
  static const apkDownloadUrl =
      'https://github.com/MacBuchi/pilzbuddy/releases/latest';

  static String inviteText(String? username) => [
        'Komm zu PilzBuddy 🍄 – wir teilen unsere Pilz-Spots!',
        'Web-App: $webAppUrl',
        'Android-App: $apkDownloadUrl',
        if (username != null && username.isNotEmpty)
          'Registriere dich und such mich dort als „$username", dann können wir uns verbinden.',
      ].join('\n');
}
