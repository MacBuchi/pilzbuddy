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
    expect(html, contains('Brevo'),
        reason: 'Der Mailversand gibt die Adresse an einen weiteren '
            'Auftragsverarbeiter — das muss dort stehen');
    expect(html, contains('Bestätigungsmail'),
        reason: 'Seit der Bestätigungspflicht (#129) geht bei JEDER '
            'Registrierung eine Mail über Brevo — nicht mehr nur beim '
            'Reset. Wer den Abschnitt darauf zurückdreht, macht die '
            'Erklärung wieder falsch');
  });

  // Die Regel aus CLAUDE.md — „ändert sich, wohin die App verbindet,
  // gehört die Erklärung in denselben PR" — als Wächter statt als
  // Vorsatz. Nicht die Erklärung wird auf Vollständigkeit geprüft (das
  // kann kein Test), sondern der umgekehrte Weg: Taucht in `lib/` ein
  // Ziel auf, das hier niemand eingetragen hat, bricht der Test.
  test('Kein neues Netzziel ohne Eintrag in der Datenschutzerklärung', () {
    /// Ziele, die die App von sich aus abruft — sie MÜSSEN in der
    /// Erklärung stehen.
    const fetched = {
      'tile.openstreetmap.org',
      'api.github.com',
      'github.com',
      'macbuchi.github.io',
      'maps.dwd.de',
    };

    /// Ziele, die erst der Nutzer mit einem Tipp öffnet (Lizenz- und
    /// Impressumslinks im Attributions-Bereich, Store-Seite). Sie
    /// erzeugen keine Verbindung, solange niemand sie antippt.
    const onTapOnly = {
      'opendatacommons.org',
      'protomaps.com',
      'www.openstreetmap.org',
      'www.dwd.de',
      'play.google.com',
    };

    /// Ziele, die nur als **Text** vorkommen und nicht einmal tippbar
    /// sind: die Quellenangaben im Lizenz-Eintrag der GBIF-Funddaten
    /// (`map_data_license.dart`). Die Kurven liegen im Binary — die App
    /// verbindet sich zu GBIF zu keinem Zeitpunkt; abgerufen wird nur
    /// beim Bauen, von `tool/season_curves.py`.
    ///
    /// Eigene Kategorie und nicht in [onTapOnly] gestopft: Der
    /// Unterschied zwischen „öffnet sich auf Tipp" und „ist reiner Text"
    /// ist genau die Entscheidung, die dieser Wächter einfordert.
    const textOnly = {
      'www.gbif.org',
      'creativecommons.org',
    };

    /// Supabase steht in der Erklärung mit Namen statt mit Hostnamen —
    /// die Projekt-Kennung im Host sagt einem Leser nichts.
    const namedInstead = {'supabase.co'};

    final hosts = <String>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final match in RegExp(r'https://([a-zA-Z0-9.\-]+)')
          .allMatches(file.readAsStringSync())) {
        hosts.add(match.group(1)!);
      }
    }

    final unknown = hosts.where((h) =>
        !fetched.contains(h) &&
        !onTapOnly.contains(h) &&
        !textOnly.contains(h) &&
        !namedInstead.any(h.endsWith));
    expect(unknown, isEmpty,
        reason: 'Neues Ziel in lib/: ${unknown.join(", ")}. Entscheide, ob '
            'die App es von sich aus abruft — dann gehört es in '
            '$_privacy und in docs/play-console.md — oder ob es nur ein '
            'Link ist. Danach hier eintragen.');

    final html = _read(_privacy);
    for (final host in fetched) {
      expect(html, contains(host), reason: '$host fehlt in der Erklärung');
    }
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
