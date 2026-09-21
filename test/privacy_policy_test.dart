// Wacht über die statischen Rechtsseiten. Der wichtigste Test ist der
// letzte: eine Datenschutzerklärung mit unersetzten Platzhaltern darf
// niemals veröffentlicht werden — sie wäre schlimmer als keine, weil sie
// Vollständigkeit vortäuscht.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_info.dart';

const _privacy = 'web/datenschutz.html';
const _impressum = 'web/impressum.html';

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
    expect(AppInfo.impressumUrl, endsWith('/impressum.html'));
    expect(File(_privacy).existsSync(), isTrue);
    expect(File('web/konto-loeschen.html').existsSync(), isTrue);
    expect(File(_impressum).existsSync(), isTrue);
  });

  test('Das Impressum trägt eine ladungsfähige Anschrift', () {
    // **Der eigentliche Inhalt der Pflicht.** § 5 DDG verlangt Namen UND
    // Anschrift; Name plus E-Mail ist genau der Zustand, aus dem diese
    // Seite entstanden ist (so stand es bis 1.157.0 unter
    // „Verantwortlicher"). Ein Postfach genügt ebenfalls nicht — deshalb
    // wird auf Straße mit Hausnummer und auf PLZ mit Ort geprüft und
    // nicht bloß darauf, dass irgendein Text dasteht.
    final html = _read(_impressum);

    expect(html, contains('Marcus Bucher'));
    expect(RegExp(r'[A-ZÄÖÜ][\wäöüß.\-]*\s?(str\.|straße|weg|platz|gasse)\s+\d',
            caseSensitive: false)
        .hasMatch(html),
        isTrue, reason: 'Straße mit Hausnummer fehlt');
    expect(RegExp(r'\b\d{5}\s+\S').hasMatch(html), isTrue,
        reason: 'Postleitzahl und Ort fehlen');
    expect(html, contains('pilzbuddy@proton.me'));
  });

  test('Das Impressum ist aus der App und von den Nachbarseiten erreichbar',
      () {
    // „Leicht erkennbar, unmittelbar erreichbar und ständig verfügbar"
    // gilt für die App so gut wie für die Seite. Eine Datei, die im
    // Web-Ordner liegt und die niemand verlinkt, erfüllt nichts —
    // genau das ist der Fehler, den dieser Test fängt.
    final profile =
        _read('lib/features/profile/profile_screen.dart');
    expect(profile, contains('AppInfo.impressumUrl'),
        reason: 'ohne Zeile im Profil ist es in der App nicht erreichbar');

    expect(_read(_privacy), contains('impressum.html'));
    expect(_read('web/konto-loeschen.html'), contains('impressum.html'));
  });

  test('Kein toter Pflichtlink auf die EU-Streitschlichtung', () {
    // Die OS-Plattform der EU ist im Juli 2025 abgeschaltet worden. Der
    // Absatz steht in jeder zweiten Impressum-Vorlage und wandert beim
    // Abschreiben mit; ein Pflichtlink ins Leere ist schlechter als
    // keiner, weil er Sorgfalt vortäuscht.
    for (final path in const [_impressum, _privacy]) {
      expect(_read(path), isNot(contains('ec.europa.eu/consumers/odr')),
          reason: '$path verweist auf eine abgeschaltete Plattform');
    }
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
    expect(html, contains('Firebase Cloud Messaging'),
        reason: 'Push (#277) bringt Google als weiteren '
            'Auftragsverarbeiter — der Host taucht in lib/ nicht als URL '
            'auf, der Scan unten kann ihn also nicht finden');
    expect(html, contains('Koordinaten'),
        reason: 'Die Zusage, dass eine Meldung NIE Koordinaten oder '
            'Spot-Namen enthält, ist der Kern der Push-Entscheidung — '
            'sie gehört in die Erklärung, nicht nur in einen Kommentar');
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
      // Die Regengitter für die Web-App (#365/#366). Derselbe Anbieter
      // wie github.com, aber ein eigener Host — und der Wächter fragt
      // nach Hosts, nicht nach Anbietern.
      'raw.githubusercontent.com',
      'macbuchi.github.io',
      'maps.dwd.de',
    };

    /// Ziele, die erst nach einer ausdrücklichen ZUSTIMMUNG abgerufen
    /// werden — und trotzdem in der Erklärung stehen müssen (#110).
    ///
    /// Bisher gab es nur „ruft die App von sich aus ab" und „ist bloß
    /// ein Link". Dazwischen liegt der Push-Weg: `www.gstatic.com`
    /// liefert das Firebase-SDK an den Service Worker im Browser, und
    /// zwar erst, wenn jemand die Benachrichtigungen einschaltet
    /// (`requestPushToken` reicht den Worker-Pfad an `getToken`, nichts
    /// davor). Das ist ein echter Empfänger, kein Link — nur eben einer
    /// mit einem Schalter davor.
    ///
    /// Der Unterschied ist keine Wortklauberei: Ein Ziel, das VOR jeder
    /// Zustimmung kontaktiert wird, ist ein anderer Sachverhalt (so lag
    /// der Fall bei Roboto, #393).
    const afterConsent = {
      'www.gstatic.com',
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
    /// sind: die Quellenangaben in den Lizenz-Einträgen der
    /// GBIF-Funddaten und des Waldtypen-Gitters
    /// (`map_data_license.dart`). Kurven wie Gitter liegen im Binary —
    /// die App verbindet sich zu GBIF und Copernicus zu keinem
    /// Zeitpunkt; abgerufen wird nur in CI (`tool/season_curves.py`,
    /// `tool/forest_grid.py`).
    ///
    /// Eigene Kategorie und nicht in [onTapOnly] gestopft: Der
    /// Unterschied zwischen „öffnet sich auf Tipp" und „ist reiner Text"
    /// ist genau die Entscheidung, die dieser Wächter einfordert.
    const textOnly = {
      'www.gbif.org',
      'creativecommons.org',
      'land.copernicus.eu',
      // Die Baumartenkarte (#227) — dieselbe Lage wie Copernicus: Das
      // Gitter liegt im Binary, geholt wird nur in CI
      // (`tool/forest_species.py`). Die Adresse steht in der
      // Lizenz-Anzeige, weil CC BY die Nennung verlangt.
      'geoservice.dlr.de',
      // Die Zitation der Pilzwetter-Formel (Lizenzseite, seit 1.92.0):
      // ein DOI ist eine Fundstellenangabe, kein Abrufziel der App.
      'doi.org',
      // Das Höhengitter — dieselbe Lage wie Copernicus/DLR: Asset im
      // Binary, geholt nur in CI (`tool/elevation_grid.py`).
      'dataspace.copernicus.eu',
      // Doku-Links in KOMMENTAREN der Web-Hülle (#110): Sie stehen in
      // `web/sw.js` bzw. `web/flutter_bootstrap.js` als Beleg für eine
      // Entscheidung und werden von niemandem abgerufen — auch nicht auf
      // Tipp, denn sie sind nicht einmal anklickbar.
      'developer.mozilla.org',
      'docs.flutter.dev',
    };

    /// Supabase steht in der Erklärung mit Namen statt mit Hostnamen —
    /// die Projekt-Kennung im Host sagt einem Leser nichts.
    const namedInstead = {'supabase.co'};

    final hosts = <String>{};
    // `lib/` UND `web/` (#110). Bis 1.124.0 sah der Wächter nur nach
    // Dart — und genau daran ist ihm entgangen, dass
    // `web/push/firebase-messaging-sw.js` das Firebase-SDK von
    // `www.gstatic.com` nachlädt. Die Web-Hülle IST Teil der
    // ausgelieferten App; ein Ziel in einem Service Worker verbindet
    // sich so echt wie eines in Dart.
    for (final root in const ['lib', 'web']) {
      for (final file in Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') ||
              f.path.endsWith('.js') ||
              f.path.endsWith('.html'))) {
        // Die Erklärung selbst NENNT die Ziele — sie ist die Antwort auf
        // diesen Test, nicht seine Eingabe.
        if (file.path.endsWith('datenschutz.html')) continue;
        for (final match in RegExp(r'https://([a-zA-Z0-9.\-]+)')
            .allMatches(file.readAsStringSync())) {
          hosts.add(match.group(1)!);
        }
      }
    }

    final unknown = hosts.where((h) =>
        !fetched.contains(h) &&
        !afterConsent.contains(h) &&
        !onTapOnly.contains(h) &&
        !textOnly.contains(h) &&
        !namedInstead.any(h.endsWith));
    expect(unknown, isEmpty,
        reason: 'Neues Ziel in lib/ oder web/: ${unknown.join(", ")}. '
            'Entscheide, ob '
            'die App es von sich aus abruft — dann gehört es in '
            '$_privacy und in docs/play-console.md — oder ob es nur ein '
            'Link ist. Danach hier eintragen.');

    final html = _read(_privacy);
    // Beide Sorten müssen dastehen: „ruft von sich aus ab" und „ruft nach
    // Zustimmung ab". Nur der Anlass unterscheidet sie, nicht die Frage,
    // ob der Empfänger genannt gehört.
    for (final host in {...fetched, ...afterConsent}) {
      expect(html, contains(host), reason: '$host fehlt in der Erklärung');
    }
  });

  test('Kein Supabase-Ziel ohne Eintrag im Verarbeitungsverzeichnis', () {
    // Derselbe Weg RÜCKWÄRTS wie beim Netzziel-Wächter darüber, nur für
    // die Datenbank statt für Hosts: Nicht das Verzeichnis wird auf
    // Vollständigkeit geprüft (das kann kein Test), sondern ob in `lib/`
    // eine Tabelle beschrieben wird, die dort niemand eingeordnet hat.
    //
    // **Warum es ihn gibt.** Das Verzeichnis ist zweimal still veraltet.
    // Die geteilte Tourspur (#340) fehlte von 1.147.0 an; Freundschaften
    // und die Freundessuche standen NIE darin, obwohl sie Monate älter
    // sind. Beides ist beim Nachzählen von Hand aufgefallen, nicht beim
    // Bauen — und Handarbeit, die halbjährlich fällig wird, passiert
    // einmal.
    //
    // **Die Zuordnung liegt HIER und nicht im Dokument.** Das
    // Verzeichnis ist in Alltagssprache geschrieben und nennt keine
    // Tabellennamen; sie hineinzuschreiben, nur damit ein Test sie
    // findet, würde das Dokument für seinen Leser schlechter machen.
    // Die Übersetzung ist genau die Entscheidung, die jemand treffen
    // muss — deshalb steht sie im Test.
    const record = 'docs/datenschutz-nachweise.md';

    /// Ziel → die Zweck-Formulierung, die im Verzeichnis stehen muss.
    const recorded = {
      'profiles': 'Konto führen',
      'spots': 'Spots und Funde speichern',
      'finds': 'Spots und Funde speichern',
      'friendships': 'Freundschaften verwalten',
      'search_profiles': 'Freunde suchen',
      'live_locations': 'Live-Standort teilen',
      'tour_tracks': 'Pilztour-Weg teilen',
      'push_devices': 'Benachrichtigungen',
      'error_reports': 'Fehlerdiagnose',
      'feedback': 'Feedback',
    };

    /// Ziele ohne Personenbezug — sie gehören NICHT ins Verzeichnis, und
    /// das ist auch eine Entscheidung, die jemand getroffen haben muss.
    ///
    /// `app_config`: eine Zeile mit der Mindestversion, für alle gleich
    /// und bewusst ohne Anmeldung lesbar, weil die Prüfung vor dem Login
    /// läuft. Wer hier etwas hinzufügt, das einen Nutzer unterscheidbar
    /// macht, hat kein Config-Feld mehr.
    const noPersonalData = {'app_config'};

    final targets = <String>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match
          in RegExp(r"\.(?:from|rpc)\('([a-z_]+)'").allMatches(source)) {
        targets.add(match.group(1)!);
      }
    }

    // Die Gegenprobe zum Wächter selbst: Findet die Suche gar nichts,
    // wäre er grün und nutzlos.
    expect(targets.length, greaterThanOrEqualTo(10),
        reason: 'der Wächter hat nichts gefunden — stimmt das Muster noch?');

    final unclassified = targets
        .where((t) => !recorded.containsKey(t) && !noPersonalData.contains(t));
    expect(unclassified, isEmpty,
        reason: 'Neues Supabase-Ziel in lib/: ${unclassified.join(", ")}. '
            'Entscheide, ob dort personenbezogene Daten verarbeitet '
            'werden — dann gehört ein Zweck in $record und hier die '
            'Zuordnung dazu — oder ob nicht; dann in noPersonalData '
            'eintragen, mit Begründung.');

    final text = _read(record);
    for (final entry in recorded.entries) {
      if (!targets.contains(entry.key)) continue;
      expect(text, contains(entry.value),
          reason: 'Der Zweck „${entry.value}" (${entry.key}) fehlt in '
              '$record — oder die Zeile wurde umbenannt, dann gehört die '
              'Zuordnung hier nachgezogen');
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
