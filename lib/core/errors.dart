import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Zentrales, bewusst minimales Logging: gefangene Fehler landen mit
/// Stacktrace im Log (dart:developer → adb logcat / DevTools), statt
/// still in generischen SnackBars zu verschwinden. Optionale Features
/// (Offline-Karten, Update-Check, GPS) degradieren weiterhin still —
/// aber auch dort darf geloggt werden.
void logError(String context, Object error, [StackTrace? stackTrace]) {
  developer.log(context,
      name: 'pilzbuddy', error: error, stackTrace: stackTrace);
  if (kDebugMode) debugPrint('[$context] $error');
}

/// Nutzerfreundliche Meldung nach Fehlerklasse statt pauschalem
/// „… Internet verfügbar?": Netzwerk, Server und Unerwartetes werden
/// unterschieden, damit Problemberichte diagnostizierbar sind.
String friendlyError(Object error) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException) {
    return 'Keine Verbindung — bitte Internet prüfen.';
  }
  if (error is PostgrestException) {
    return 'Serverfehler (${error.code ?? 'unbekannt'}) — '
        'bitte später erneut versuchen.';
  }
  if (error is AuthException) {
    return 'Anmeldung abgelaufen — bitte neu anmelden.';
  }
  return 'Unerwarteter Fehler (${error.runtimeType}) — '
      'bitte über das Banner melden.';
}

/// Login-Fehler → Meldung. Bevorzugt den typisierten Supabase-Fehlercode;
/// der HTTP-Status bleibt als Fallback für ältere Server.
String loginErrorMessage(AuthException error) {
  if (error.code == 'invalid_credentials' || error.statusCode == '400') {
    return 'E-Mail oder Passwort falsch.';
  }
  return 'Anmeldung fehlgeschlagen: ${error.message}';
}

/// Registrierungs-Fehler → Meldung. `user_already_exists` ist typisiert;
/// der "Database error saving new user"-Fall ist ein 500 aus dem
/// Profil-Trigger OHNE Fehlercode (unique-Verletzung am Benutzernamen) —
/// dieses String-Matching ist unvermeidbar und per Test festgenagelt.
String signupErrorMessage(AuthException error) {
  if (error.code == 'user_already_exists') {
    return 'Für diese E-Mail gibt es schon ein Konto.';
  }
  if (error.message.contains('Database error saving new user')) {
    return 'Dieser Benutzername ist schon vergeben.';
  }
  return 'Registrierung fehlgeschlagen: ${error.message}';
}
