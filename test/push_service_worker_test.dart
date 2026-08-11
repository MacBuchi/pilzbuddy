// Der Web-Push hängt an einem Dateipfad, der nur im ausgelieferten Build
// falsch sein kann (#277).
//
// Dieselbe Fehlerklasse wie `android_manifest_test.dart`: Es übersetzt
// sauber, jeder Widget-Test läuft grün — und in der Web-App bekäme
// niemand je ein Token, weil das FCM-SDK den Worker dort sucht, wo er
// nicht liegt. Genau so lag es im Nachbarprojekt bis 0.39.0.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/push_config.dart';
import 'package:pilzbuddy/core/push_messaging.dart';

const _config = 'lib/core/push_config.dart';

void main() {
  test('der Web-Push-Schlüssel ist da', () {
    // Ohne VAPID-Schlüssel liefert `getToken` im Web nichts — still, wie
    // alles an diesem Pfad. Deshalb steht er als Konstante da und nicht
    // als `--dart-define`: Ein vergessener Define wäre nirgends zu sehen,
    // eine leere Konstante fällt hier auf.
    expect(pushWebVapidKey, isNotEmpty,
        reason: 'ohne ihn bekommt die Web-App dauerhaft kein Token');
    expect(pushWebVapidKey, startsWith('B'),
        reason: 'ein VAPID-Schlüssel ist ein unkomprimierter '
            'P-256-Punkt in base64url — der beginnt mit B');
    expect(pushWebVapidKey.length, greaterThan(80),
        reason: 'abgeschnitten kopiert? Vollständig sind es ~87 Zeichen');
  });

  test('der Worker-Pfad ist relativ, nicht absolut', () {
    expect(webServiceWorkerPath, isNot(startsWith('/')),
        reason: 'Ein absoluter Pfad zeigte auf den Origin-Root und damit '
            'ins Leere — die App liegt unter /pilzbuddy/. Ein absoluter '
            'MIT Präfix wäre eine zweite Stelle, die mit --base-href in '
            'release.yml synchron bleiben müsste.');
    expect(webServiceWorkerPath, isNot(contains('..')),
        reason: 'Der Scope des Workers darf nicht über die App '
            'hinausreichen.');
  });

  test('der Worker liegt in einem EIGENEN Verzeichnis', () {
    // Flutter registriert `flutter_service_worker.js` im Basis-Scope.
    // Registrierungen sind über den Scope eindeutig: Läge unser Worker
    // daneben, ersetzte er beim ersten Einschalten der
    // Benachrichtigungen den Offline-Start der Web-App — still.
    expect(webServiceWorkerPath, contains('/'),
        reason: 'ohne Unterverzeichnis kollidiert der Scope mit Flutters '
            'eigenem Service Worker');
    expect(File('web/$webServiceWorkerPath').existsSync(), isTrue,
        reason: 'Der Worker wird aus web/ mit ausgeliefert. Wird er '
            'umbenannt oder verschoben, ohne den Pfad mitzuziehen, '
            'scheitert getToken im Web dauerhaft und ohne Meldung.');
  });

  test('der Worker zeigt auf dasselbe Firebase-Projekt wie die App', () {
    // Ein Service Worker kann kein Dart lesen, die Kennung steht deshalb
    // zwangsläufig zweimal da. Driftete sie, holte die App ein Token für
    // Projekt A, während der Worker Nachrichten von Projekt B erwartet —
    // und niemand bekäme etwas, ohne dass irgendwo ein Fehler stünde.
    final worker = File('web/$webServiceWorkerPath').readAsStringSync();
    final config = File(_config).readAsStringSync();

    String valueOf(String source, String key) {
      final match = RegExp("$key:\\s*'([^']+)'").firstMatch(source);
      expect(match, isNotNull, reason: '$key fehlt');
      return match!.group(1)!;
    }

    for (final key in const [
      'apiKey',
      'appId',
      'messagingSenderId',
      'projectId',
    ]) {
      expect(valueOf(worker, key), valueOf(config, key),
          reason: '$key läuft zwischen Worker und $_config auseinander');
    }
  });

  test('kein eigener Hintergrund-Handler im Worker', () {
    // Bei einer Nutzlast mit `notification` zeigt das SDK die Meldung
    // selbst an; ein eigener Handler erzeugte eine ZWEITE daneben.
    //
    // Geprüft wird der CODE, nicht die Datei: Der Kopfkommentar erklärt
    // die Regel und nennt den Namen dabei zwangsläufig. Ein Test, der
    // daran scheitert, bestraft das Aufschreiben der Begründung.
    final code = File('web/$webServiceWorkerPath')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(code, isNot(contains('onBackgroundMessage')),
        reason: 'doppelte Benachrichtigung — im Nachbarprojekt so '
            'passiert');
  });
}
