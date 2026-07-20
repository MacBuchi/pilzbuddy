// Wacht über die statischen Rechtsseiten. Der wichtigste Test ist der
// letzte: eine Datenschutzerklärung mit unersetzten Platzhaltern darf
// niemals veröffentlicht werden — sie wäre schlimmer als keine, weil sie
// Vollständigkeit vortäuscht.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_info.dart';

const _privacy = 'web/datenschutz.html';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path fehlt');
  return file.readAsStringSync();
}

void main() {
  test('Die verlinkten Seiten liegen wirklich im Web-Verzeichnis', () {
    // Die URLs zeigen auf GitHub Pages; ausgeliefert wird, was in web/ liegt.
    // Ein Tippfehler im Dateinamen fiele sonst erst im Store auf.
    expect(AppInfo.privacyUrl, endsWith('/datenschutz.html'));
    expect(AppInfo.deleteAccountUrl, endsWith('/konto-loeschen.html'));
    expect(File(_privacy).existsSync(), isTrue);
    expect(File('web/konto-loeschen.html').existsSync(), isTrue);
  });

  test('Die Erklärung benennt die heiklen Punkte', () {
    final html = _read(_privacy);

    // Genau die Stellen, an denen eine Standard-Vorlage schweigt und die
    // bei dieser App die Substanz ausmachen.
    expect(html, contains('tile.openstreetmap.org'),
        reason: 'IP-Übertragung beim Kartenabruf fehlt');
    expect(html, contains('öffentlich'),
        reason: 'Feedback wird öffentlich — muss dort stehen');
    expect(html, contains('Live-Standort'));
    expect(html, contains('Konto löschen'));
    expect(html, contains('Fehlerberichte'));
    expect(html, contains('Supabase'));
  });

  test('Keine unersetzten Platzhalter mehr', () {
    // ABSICHTLICH ROT, solange Name, Anschrift, Kontakt, Supabase-Region und
    // Datum fehlen. Dieser Test ist die Bremse davor, eine unfertige
    // Datenschutzerklärung live zu stellen.
    final open = RegExp(r'\[\[([A-ZÄÖÜ\- ]+)\]\]')
        .allMatches(_read(_privacy))
        .map((m) => m.group(1))
        .toSet();

    expect(open, isEmpty,
        reason: 'Noch offen in $_privacy: ${open.join(", ")}');
  });
}
