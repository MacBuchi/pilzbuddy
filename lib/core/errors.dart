import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:executor_lib/executor_lib.dart' show CancellationException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Empfänger für Fehlerberichte. `main()` hängt hier das Schreiben nach
/// Supabase ein (siehe `ErrorReportRepository`); in Tests bleibt der Haken
/// leer, damit `flutter test` ohne Netz auskommt.
typedef ErrorSink = void Function(
    String context, Object error, StackTrace? stackTrace);

ErrorSink? _sink;

/// Einmalig in `main()` setzen. `null` schaltet das Melden wieder ab.
void setErrorSink(ErrorSink? sink) => _sink = sink;

/// Zentrales, bewusst minimales Logging: gefangene Fehler landen mit
/// Stacktrace im Log (dart:developer → adb logcat / DevTools), statt
/// still in generischen SnackBars zu verschwinden. Optionale Features
/// (Offline-Karten, Update-Check, GPS) degradieren weiterhin still —
/// aber auch dort darf geloggt werden.
///
/// Zusätzlich geht der Fehler an den [ErrorSink], falls einer gesetzt ist.
/// Der Aufruf darf unter keinen Umständen werfen: ein Fehler beim Melden
/// eines Fehlers würde sonst erneut hier landen und sich aufschaukeln.
void logError(String context, Object error, [StackTrace? stackTrace]) {
  developer.log(context,
      name: 'pilzbuddy', error: error, stackTrace: stackTrace);
  if (kDebugMode) debugPrint('[$context] $error');
  try {
    _sink?.call(context, error, stackTrace);
  } catch (_) {
    // Bewusst still: hier zu loggen wäre genau die Endlosschleife.
  }
}

/// Gehört dieser Fehler in `error_reports`?
///
/// Für die globalen Handler in `main()`, die alles melden, was ihnen vor die
/// Füße fällt. Zwei Dinge fallen dort regelmäßig hin, ohne dass etwas kaputt
/// ist — und 193 Meldungen pro Woche für einen Normalfall begraben im
/// Wochendigest die echten Funde (Issue #136, gleiche Lehre wie #124):
///
/// * `CancellationException` aus `executor_lib`: Der Kartenrenderer bricht
///   Kachel-Aufträge ab, sobald die Kachel aus dem Bild gewandert ist
///   (`vector_map_tiles`, u. a. `raster/tile_loader.dart`). Das Paket
///   filtert sie an einer Stelle selbst weg — an anderer entkommt sie als
///   unbehandelter async-Fehler. Genau dafür ist sie gedacht: abgebrochen
///   heißt abgebrochen.
/// * [NotSignedInException]: Hintergrundabfragen, die nach dem Abmelden
///   noch einen Moment weiterlaufen.
///
/// Bewusst NICHT in `logError` selbst: Wer einen Fehler mit eigenem Kontext
/// meldet, hat sich für das Melden entschieden — diese Entscheidung darf ein
/// Filter nicht überstimmen.
bool worthReporting(Object error) =>
    error is! CancellationException && error is! NotSignedInException;

/// Es gibt gerade keine angemeldete Sitzung.
///
/// Kein Fehler im eigentlichen Sinn: Beim Abmelden und beim Ablaufen eines
/// Tokens laufen Hintergrundabfragen noch einen Moment weiter und greifen
/// dann ins Leere. Vorher war das ein `Null check operator used on a null
/// value` aus `currentUser!` — 37 Fehlerberichte in einer Woche für einen
/// völlig normalen Vorgang (Issue #124). Als eigener Typ, damit genau die
/// Stellen ihn erkennen und still aufhören können, statt zu melden.
class NotSignedInException implements Exception {
  const NotSignedInException();

  @override
  String toString() => 'NotSignedInException: keine angemeldete Sitzung';
}

/// Sieht dieser Fehler nach fehlendem Empfang aus?
///
/// Bewusst eng: Der Spot-Zwischenspeicher (`spot_cache.dart`) springt NUR
/// dafür ein. Ein Schema- oder Rechtefehler darf sich nicht hinter einer
/// alten Kopie verstecken — sonst bliebe ein kaputtes Deployment
/// unsichtbar, während alle Geräte stillschweigend veraltete Daten
/// zeigen. Dieselbe Lehre wie Issue #80.
bool looksOffline(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is http.ClientException;

/// Nutzerfreundliche Meldung nach Fehlerklasse statt pauschalem
/// „… Internet verfügbar?": Netzwerk, Server und Unerwartetes werden
/// unterschieden, damit Problemberichte diagnostizierbar sind.
String friendlyError(Object error) {
  if (looksOffline(error)) {
    return 'Keine Verbindung — bitte Internet prüfen.';
  }
  if (error is NotSignedInException) {
    return 'Nicht mehr angemeldet — bitte neu anmelden.';
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
  // Vor der Standardmeldung prüfen: Die unbestätigte Adresse kommt zwar
  // auch als 400, ist aber etwas völlig anderes als ein falsches Passwort
  // — wer hier „E-Mail oder Passwort falsch" liest, sucht den Fehler an
  // der falschen Stelle (Issue #129).
  if (error.code == 'email_not_confirmed') {
    return 'Bitte bestätige zuerst deine E-Mail-Adresse — die Mail dazu '
        'liegt in deinem Postfach.';
  }
  if (error.code == 'invalid_credentials' || error.statusCode == '400') {
    return 'E-Mail oder Passwort falsch.';
  }
  return 'Anmeldung fehlgeschlagen: ${error.message}';
}

/// Fehler beim Einlösen eines Reset-Codes → Meldung.
///
/// Der falsche oder abgelaufene Code ist der Normalfall (abgetippt), er
/// braucht eine Meldung, die zum nächsten Schritt führt. `weak_password`
/// kommt aus der Passwort-Prüfung von Supabase (Leaked Password Protection
/// ist im Dashboard aktiv, siehe CLAUDE.md) — dort ist „zu kurz" falsch,
/// das Passwort kann auch bekannt geleakt sein.
String resetErrorMessage(AuthException error) {
  if (error.code == 'otp_expired' || error.statusCode == '403') {
    return 'Der Code ist falsch oder abgelaufen — bitte einen neuen '
        'anfordern.';
  }
  if (error.code == 'weak_password') {
    return 'Dieses Passwort ist zu unsicher — bitte ein anderes wählen.';
  }
  if (error.code == 'same_password') {
    return 'Das ist das bisherige Passwort — bitte ein neues wählen.';
  }
  return 'Zurücksetzen fehlgeschlagen: ${error.message}';
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

/// Fehler beim Ändern des Benutzernamens → Meldung.
///
/// Anders als bei der Registrierung kommt der Konflikt hier nicht als
/// Auth-Fehler aus dem Profil-Trigger, sondern direkt aus PostgREST:
/// unique-Verletzung = SQLSTATE 23505 (`profiles_username_key` bzw. seit
/// Patch 013 `profiles_username_lower_key`). Derselbe Text wie bei der
/// Registrierung — es ist derselbe Fall, und zwei Formulierungen für
/// eine Ursache wären Rätselraten.
String usernameChangeErrorMessage(Object error) {
  if (error is PostgrestException && error.code == '23505') {
    return 'Dieser Benutzername ist schon vergeben.';
  }
  return friendlyError(error);
}

/// Fehler beim Bestätigen der Adresse (Code aus der Mail) und beim erneuten
/// Anfordern dieser Mail → Meldung.
///
/// Eigene Funktion statt `resetErrorMessage`: Deren Fallback sagt
/// „Zurücksetzen fehlgeschlagen" — mitten in der Registrierung schickt das
/// den Leser in die falsche Richtung. Dazu kommt das Rate Limit, das es beim
/// Reset praktisch nicht gibt, beim „Erneut senden" aber der häufigste Fall
/// ist (Issue #129/#131).
String confirmErrorMessage(AuthException error) {
  if (error.code == 'otp_expired' || error.statusCode == '403') {
    return 'Der Code ist falsch oder abgelaufen — bitte einen neuen '
        'anfordern.';
  }
  if (error.code == 'over_email_send_rate_limit' ||
      error.statusCode == '429') {
    return 'Es ist gerade eine Mail rausgegangen — bitte eine Minute warten.';
  }
  return 'Bestätigung fehlgeschlagen: ${error.message}';
}

/// Fehler beim Ändern des Passworts durch Angemeldete → Meldung (Issue #127).
///
/// Der erste Schritt des Ändern-Flows ist eine erneute Anmeldung mit dem
/// aktuellen Passwort. Deren `invalid_credentials` heißt hier deshalb NICHT
/// „E-Mail oder Passwort falsch", sondern genau eines von beidem.
/// Die typisierten Codes stehen bewusst VOR dem Status-Fallback: Ein
/// abgelehntes neues Passwort kommt je nach Server-Version auch als 400 an
/// und läse sich sonst als „aktuelles Passwort falsch".
String changePasswordErrorMessage(AuthException error) {
  if (error.code == 'weak_password') {
    return 'Dieses Passwort ist zu unsicher — bitte ein anderes wählen.';
  }
  if (error.code == 'same_password') {
    return 'Das ist das bisherige Passwort — bitte ein neues wählen.';
  }
  if (error.code == 'invalid_credentials' || error.statusCode == '400') {
    return 'Das aktuelle Passwort stimmt nicht.';
  }
  return 'Ändern fehlgeschlagen: ${error.message}';
}
