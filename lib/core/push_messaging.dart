// Die Plattformseite der Push-Benachrichtigungen (#277): Firebase starten,
// ein Token holen, auf das Antippen einer Meldung hören.
//
// **Push ist ein Nebenfeature.** Jeder Fehlerpfad endet hier in `null` =
// kein Token = keine Registrierung, und [initPushMessaging] schluckt
// jeden Fehler. Ein kaputtes oder abgelaufenes Firebase-Projekt darf die
// App nicht am Starten hindern — dieselbe Linie wie beim Update-Check
// (`update_check.dart`) und bei der Offline-Karte: Optionale Wege dürfen
// still degradieren, der Kernpfad nicht.
//
// Die Berechtigung wird NICHT beim Start erfragt. Sie kommt erst, wenn
// jemand im Profil den Schalter umlegt — ein Systemdialog beim ersten
// Start, bevor die Karte auch nur zu sehen war, ist die zuverlässigste
// Art, ein „Nein für immer" zu bekommen.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'errors.dart';
import 'push_config.dart';

/// Firebase starten — auf Android OHNE Optionen.
///
/// **Der Fall, der sonst bei jedem Start einen Fehler ins Log schreibt:**
/// Das Google-Services-Gradle-Plugin startet die Standard-App längst
/// nativ aus `google-services.json`, bevor Dart überhaupt läuft. Ein
/// zweites `initializeApp` mit Optionen quittiert das mit
/// `[core/duplicate-app]` — folgenlos, aber es verdeckt die echten
/// Meldungen (im Nachbarprojekt auf einem Pixel beobachtet). Im Web gibt
/// es diesen Vorlauf nicht, dort sind die Optionen Pflicht.
Future<void> _ensureFirebase() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(
    options: kIsWeb ? pushFirebaseOptions : null,
  );
}

/// Wo der Web-Push-Worker liegt — RELATIV, und das ist der ganze Punkt.
///
/// Ohne Angabe sucht das FCM-SDK `/firebase-messaging-sw.js` am
/// **Origin-Root**. Unsere Web-App liegt unter `/pilzbuddy/`, dort steht
/// also nichts — 404, und `getToken` scheitert dauerhaft und STILL. Im
/// Nachbarprojekt bekam deshalb bis 0.39.0 in der PWA nie jemand ein
/// Token. Ein absoluter Pfad MIT Präfix wäre nur die zweitbeste Lösung:
/// eine weitere Stelle, die mit `--base-href` in `release.yml` synchron
/// bleiben müsste. Relativ löst der Browser gegen das `<base href>` auf,
/// das Flutter beim Bauen ohnehin setzt.
///
/// Das Unterverzeichnis ist ebenfalls Absicht — die Begründung steht in
/// der Datei selbst: Flutters eigener Worker hat den Basis-Scope, und
/// zwei Worker im selben Scope verdrängen sich.
const webServiceWorkerPath = 'push/firebase-messaging-sw.js';

/// Das FCM-Token dieses Geräts — `null`, wenn irgendetwas nicht geht.
///
/// Fragt dabei die Systemberechtigung ab; wer ablehnt, bekommt `null`.
Future<String?> requestPushToken() async {
  try {
    await _ensureFirebase();
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }
    // Im Web ohne VAPID-Schlüssel gibt es kein Token. Lieber gar nicht
    // erst fragen als eine Ausnahme fangen, die nichts erklärt.
    if (kIsWeb && pushWebVapidKey.isEmpty) return null;
    // Mit Frist: `getToken` scheitert nicht immer, es bleibt auch mal
    // stehen — etwa wenn die Registrierung bei FCM nicht durchkommt. Ohne
    // die Frist hinge der Schalter im Profil an einem Vorgang, der nie
    // endet. Ein Timeout landet unten im catch und wird zu „kein Token".
    return await messaging
        .getToken(
          vapidKey: kIsWeb ? pushWebVapidKey : null,
          serviceWorkerScriptPath: kIsWeb ? webServiceWorkerPath : null,
        )
        .timeout(const Duration(seconds: 15));
  } catch (e, stackTrace) {
    // Gemeldet, aber nicht geworfen: Dass Push nicht geht, ist eine
    // Information — dass die App deshalb stehen bleibt, wäre ein Fehler.
    logError('Push-Token holen', e, stackTrace);
    return null;
  }
}

/// Wie die App an ein Token kommt — die Test-Naht.
///
/// Im Widget-Test gibt es weder FCM noch Berechtigungsdialoge; das
/// Harness überschreibt diesen Provider, sonst hinge jeder Test, der das
/// Profil öffnet, an einer Plattform, die es dort nicht gibt.
final pushTokenProvider =
    Provider<Future<String?> Function()>((ref) => requestPushToken);

/// Auf das Antippen einer Meldung hören.
///
/// **Bewusst KEIN eigener `onBackgroundMessage`-Handler.** Er erzeugte im
/// Nachbarprojekt eine zweite Benachrichtigung neben der, die das System
/// ohnehin anzeigt.
Stream<RemoteMessage> pushTaps() => FirebaseMessaging.onMessageOpenedApp;

/// Dieselbe Naht für das Antippen.
final pushTapListenerProvider =
    Provider<Stream<RemoteMessage> Function()>((ref) => pushTaps);
