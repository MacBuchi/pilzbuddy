// Service Worker für Web-Push (#277).
//
// **Warum in einem Unterverzeichnis.** Flutter registriert seinen eigenen
// `flutter_service_worker.js` im Basis-Scope (`/pilzbuddy/`) — dort liegt
// der Offline-Start der Web-App. Service-Worker-Registrierungen sind über
// ihren SCOPE eindeutig: Ein zweiter Worker mit demselben Scope ersetzt
// den ersten. Läge diese Datei neben der index.html, verlöre die Web-App
// beim ersten Einschalten der Benachrichtigungen still ihren
// Offline-Start. Aus `web/push/` heraus bekommt sie den Scope
// `/pilzbuddy/push/` und kommt der anderen nicht in die Quere; Push-
// Ereignisse gehen an die Registrierung, nicht an die kontrollierten
// Seiten.
//
// **Kein `onBackgroundMessage`-Handler.** Bei einer Nutzlast mit
// `notification` zeigt das SDK die Meldung selbst an; ein eigener Handler
// erzeugte eine zweite daneben (im Nachbarprojekt so passiert).
//
// Die Werte unten sind dieselben wie in `lib/core/push_config.dart` und
// bewusst öffentlich. Ein Service Worker kann kein Dart lesen, sie stehen
// deshalb zwangsläufig zweimal da — `test/push_service_worker_test.dart`
// hält beide Stellen zusammen.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyD4iMisoagGpUZVtneLHvbAR0rKOkM9mSU',
  appId: '1:768561424854:web:273afd65b66516dc43dc77',
  messagingSenderId: '768561424854',
  projectId: 'pilzbuddy-app',
  authDomain: 'pilzbuddy-app.firebaseapp.com',
  storageBucket: 'pilzbuddy-app.firebasestorage.app',
});

firebase.messaging();
