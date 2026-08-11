// Die Firebase-Kennung der Web-App (#277).
//
// **Diese Werte sind bewusst öffentlich** — genau wie der
// Supabase-Publishable-Key in `supabase_config.dart`: Sie identifizieren
// das Projekt, sie berechtigen zu nichts. Wer damit etwas anstellen will,
// scheitert an den Regeln auf der Serverseite, nicht an ihrer
// Geheimhaltung.
//
// Android liest seine Entsprechung NICHT hier, sondern nativ aus
// `android/app/google-services.json` — das Google-Services-Gradle-Plugin
// startet die Firebase-App, bevor Dart überhaupt läuft. Deshalb dürfen
// diese Optionen dort nicht ein zweites Mal übergeben werden; siehe
// `push_messaging.dart`.
import 'package:firebase_core/firebase_core.dart';

/// Projekt `pilzbuddy-app`, angelegt am 2026-08-11.
const pushFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyD4iMisoagGpUZVtneLHvbAR0rKOkM9mSU',
  appId: '1:768561424854:web:273afd65b66516dc43dc77',
  messagingSenderId: '768561424854',
  projectId: 'pilzbuddy-app',
  authDomain: 'pilzbuddy-app.firebaseapp.com',
  storageBucket: 'pilzbuddy-app.firebasestorage.app',
);

/// Der Web-Push-Schlüssel („Web Push certificate", VAPID) aus den
/// Projekteinstellungen → Cloud Messaging.
///
/// **Ohne ihn liefert `getToken` im Web nichts** — und zwar still, wie
/// alles an diesem Pfad. Er lässt sich nicht über die CLI erzeugen,
/// sondern nur in der Konsole.
///
/// Bewusst eine KONSTANTE und kein `--dart-define`: Ein vergessener
/// Define beim Web-Build hieße „kein Token", ohne dass irgendwo ein
/// Fehler stünde — genau die Fehlerklasse, gegen die der Rest dieser
/// Ecke geschrieben ist (siehe `webServiceWorkerPath`). Hier steht der
/// Wert an einer Stelle, ist sichtbar, und ein Test hält fest, dass er
/// nicht leer ist. Öffentlich ist er ohnehin: Der Browser bekommt ihn
/// bei jeder Registrierung zu sehen.
const pushWebVapidKey =
    'BADSTgGpAgZQSSGSWeO14lYA47_aA7zUI0yra4W3wNCk5d4xfC7taqIol0rTkmFnV3lNA'
    '_w9QvgpIaib-ggMWkM';
