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

  String workerCode() => File('web/$webServiceWorkerPath')
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('der Worker lädt nichts nach (seit 1.203.0 ohne Firebase-SDK)', () {
    // Geprüft wird der CODE, nicht die Datei: Der Kopfkommentar erklärt,
    // warum das SDK gegangen ist, und nennt es dabei zwangsläufig.
    final code = workerCode();
    expect(code, isNot(contains('importScripts')),
        reason: 'Das SDK entschied nach „irgendein Fenster der Domain '
            'sichtbar" und schluckte Meldungen, sobald die Vorschau neben '
            'der Freigabe offen war — und es kam bei jedem Aufwachen von '
            'www.gstatic.com.');
    expect(code, isNot(contains('https://')),
        reason: 'kein fremder Ursprung im Worker');
  });

  test('Worker und App meinen dieselbe Übergabe-Kennung', () {
    // Stimmt sie nicht überein, verwirft die App jede weitergereichte
    // Meldung — im Vordergrund käme dann still nichts an.
    final match =
        RegExp(r"const BRIDGE = '([^']+)'").firstMatch(workerCode());
    expect(match?.group(1), kPushBridgeType);
  });

  group('pushBridgeMessageOf', () {
    test('Meldung mit Titel, Text und Ziel', () {
      final m = pushBridgeMessageOf({
        'type': kPushBridgeType,
        'kind': 'message',
        'notification': {'title': 'bert', 'body': 'Morgen?'},
        'data': {'route': '/friends/chat/x'},
      })!;
      expect(m.kind, 'message');
      expect(m.message.notification?.title, 'bert');
      expect(m.message.notification?.body, 'Morgen?');
      expect(m.message.data, {'route': '/friends/chat/x'});
    });

    test('Tipp ohne Meldung, nur das Ziel', () {
      final m = pushBridgeMessageOf({
        'type': kPushBridgeType,
        'kind': 'tap',
        'data': {'route': '/friends/chat/x'},
      })!;
      expect(m.kind, 'tap');
      expect(m.message.notification, isNull);
      expect(m.message.data['route'], '/friends/chat/x');
    });

    test('fremde Nachrichten bleiben liegen', () {
      // `sw.js` und ein alter Firebase-Worker schicken der Seite eigene
      // Nachrichten; keine davon darf als Push gelten.
      for (final raw in <Object?>[
        null,
        'warm',
        {'type': 'warm'},
        {'isFirebaseMessaging': true, 'messageType': 'push-received'},
        {'type': kPushBridgeType},
      ]) {
        expect(pushBridgeMessageOf(raw), isNull, reason: '$raw');
      }
    });

    test('nur Zeichenketten in data — wie FCM sie liefert', () {
      final m = pushBridgeMessageOf({
        'type': kPushBridgeType,
        'kind': 'tap',
        'data': {'route': '/friends/chat/x', 'n': 3, 'x': null},
      })!;
      expect(m.message.data, {'route': '/friends/chat/x'});
    });
  });
}
