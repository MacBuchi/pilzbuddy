// Die HTML-Hülle der Web-App.
//
// Sie ist die einzige Datei im Projekt, die kein Dart-Werkzeug ansieht:
// `flutter analyze` kennt sie nicht, `flutter test` startet sie nicht,
// und ein fehlender Meta-Tag bricht keinen Build. Genau so sind bis
// 1.111.0 zwei Zeilen unbemerkt verschwunden (#364) — bemerkt hat es
// ein Nutzer auf seinem Startbildschirm, nicht die CI.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final html = File('web/index.html').readAsStringSync();
  final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
      as Map<String, dynamic>;
  final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
  final worker = File('web/sw.js').readAsStringSync();
  /// Nur der Code — die Begründungen in dieser Datei nennen die Fallen
  /// beim Namen, und eine Prüfung auf „kommt nicht vor" fände sonst den
  /// Kommentar statt der Zeile.
  final bootstrapCode = bootstrap
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('die Seite bringt ihren eigenen Maßstab mit', () {
    // Ohne `viewport` legt ein mobiler Browser eine 980 px breite Seite
    // an und skaliert sie herunter. Die Karte bekäme nie die echte
    // Auflösung des Geräts zu sehen — und ausgerechnet sie lebt davon.
    expect(html, contains('name="viewport"'));
    expect(html, contains('width=device-width'));
  });

  test('die Systemleisten der installierten App haben eine Farbe', () {
    // Ohne `theme-color` entscheidet der Browser selbst, womit er die
    // Leisten oben und unten füllt. Auf dem Gerät des Betreibers wurde
    // daraus Weiß auf Weiß: Uhr, Benachrichtigungs- und Gestensymbole
    // waren unsichtbar (#364).
    final tag = RegExp(r'<meta name="theme-color" content="([^"]+)"')
        .firstMatch(html);
    expect(tag, isNotNull, reason: 'der Tag fehlt ganz');
    expect(tag!.group(1), manifest['theme_color'],
        reason: 'Dokument und Manifest färben dieselben Leisten. Zwei '
            'Werte an zwei Stellen wären zwei Antworten auf dieselbe '
            'Frage — und welche gilt, hängt vom Browser ab');
  });

  // Der Offline-Start der Web-App (#387). Was diese Prüfungen NICHT
  // leisten: zu zeigen, dass der Worker sich im Browser richtig verhält.
  // Das tut `tool/check_service_worker.mjs` — ein echter Chrome, dem
  // mitten im Lauf der Webserver abgeschaltet wird. Hier stehen nur die
  // Fallen, die man beim Lesen des Diffs übersieht.
  group('Der eigene Service Worker (#387)', () {
    test('die Startdatei bringt Lader und Build-Konfiguration mit', () {
      // Fehlt eines von beiden, startet die App überhaupt nicht — und
      // zwar auch online.
      expect(bootstrap, contains('{{flutter_js}}'));
      expect(bootstrap, contains('{{flutter_build_config}}'));
    });

    test('kein Platzhalter steht in einem Kommentar', () {
      // Der Build ersetzt sie ÜBERALL, und der Lader ist mehrzeilig: Aus
      // einer `//`-Zeile bricht er sofort aus, danach ist die Datei
      // Syntaxmüll. Genau so beim Bau dieses Features passiert; sichtbar
      // war es nur als SyntaxError in der Browser-Konsole.
      final drin = bootstrap
          .split('\n')
          .where((line) => line.trimLeft().startsWith('//'))
          .where((line) => line.contains('{{'))
          .toList();
      expect(drin, isEmpty, reason: 'Platzhalter im Kommentar: $drin');
    });

    test('der Lader bekommt KEIN serviceWorkerSettings', () {
      // Sonst registriert er `flutter_service_worker.js` — 784 Bytes,
      // deren einzige Aufgabe es ist, sich selbst wieder abzumelden. Und
      // er tut das genau dann, wenn für diesen Scope schon eine
      // Registrierung existiert: ab dem zweiten Besuch also UNSERE. Der
      // Cache wäre bei jedem Laden weg, ohne eine Fehlermeldung.
      expect(bootstrapCode, isNot(contains('serviceWorkerSettings')));
    });

    test('registriert wird relativ und mit der Bauversion', () {
      expect(bootstrap, contains("register('sw.js?v='"),
          reason: 'Ein führender Schrägstrich zeigte auf den Origin-Root '
              'statt auf /pilzbuddy/ — und der Scope entscheidet, welche '
              'Seiten der Worker überhaupt sieht.');
      expect(bootstrap, contains('{{flutter_service_worker_version}}'),
          reason: 'Ohne die Bauversion bekäme jeder Deploy denselben '
              'Cache-Namen, und der alte Stand bliebe liegen.');
      expect(bootstrap, contains("updateViaCache: 'none'"));
    });

    test('der Worker holt seinen Cache-Namen aus der eigenen URL', () {
      // Eine Quelle, keine zweite Stelle zum Synchronhalten.
      expect(worker, contains("searchParams.get('v')"));
      expect(worker, contains("'pilzbuddy-'"));
    });

    test('er übernimmt sofort und räumt alte Caches weg', () {
      expect(worker, contains('skipWaiting'));
      expect(worker, contains('clients.claim'));
      expect(worker, contains('caches.delete'));
    });

    test('er fasst nur an, was er anfassen darf', () {
      // Gegen den HANDLER geprüft, nicht gegen die Datei: `origin` kommt
      // auch im Vorwärmen vor, und eine Prüfung auf „steht irgendwo"
      // bliebe grün, wenn genau hier die Zeile fehlte. Einmal
      // gegengeprobt und genau daran gescheitert.
      final start = worker.indexOf("addEventListener('fetch'");
      expect(start, greaterThan(-1));
      final handler = worker.substring(start, worker.indexOf('\n});', start));

      expect(handler, contains("method !== 'GET'"),
          reason: 'Ein POST an Supabase hat hier nichts verloren.');
      expect(handler, contains("headers.has('range')"),
          reason: 'Eine 206 lässt sich nicht ablegen — cache.put wirft.');
      expect(handler, contains('self.location.origin'),
          reason: 'Fremde Ziele (Supabase, DWD, GitHub) gehören der App.');
      expect(worker, contains('status === 200'),
          reason: 'Weiterleitungen und Fehler als Kopie zu behalten hieße, '
              'sie später ohne Netz zu wiederholen.');
    });

    test('das Netz gewinnt immer, der Cache ist nur der Rückfall', () {
      // Die tragende Entscheidung: Ein Cache, der gewinnt, nagelt Nutzer
      // auf einen alten Stand und umgeht die kontrollierte Beförderung.
      // Flutters Web-Ausgaben tragen keine Inhalts-Prüfsummen —
      // `main.dart.js` heißt immer gleich.
      final start = worker.indexOf('async function networkFirst');
      expect(start, greaterThan(-1));
      final body = worker.substring(start, worker.indexOf('\n}', start));
      final netz = body.indexOf('fetchAndCache(request)');
      final cache = body.indexOf('caches.match(request');
      expect(netz, greaterThan(-1));
      expect(cache, greaterThan(netz),
          reason: 'Innerhalb von networkFirst muss der Netzversuch VOR '
              'dem Griff in den Cache stehen — nicht andersherum.');
    });

    test('es gibt eine Notbremse', () {
      // Ein kaputter Worker darf keine Sackgasse sein.
      expect(worker, contains("'unregister'"));
      expect(worker, contains('registration.unregister()'));
    });
  });
}
