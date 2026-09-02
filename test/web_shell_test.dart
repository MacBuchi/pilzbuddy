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
}
