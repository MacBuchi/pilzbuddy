// Nagelt die Fehler-→-Meldung-Zuordnungen fest (#55): Supabase-Updates
// dürfen diese Mappings nicht unbemerkt brechen.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pilzbuddy/core/errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('friendlyError', () {
    test('Netzwerkfehler → Verbindungshinweis', () {
      expect(friendlyError(const SocketException('down')),
          contains('Keine Verbindung'));
      expect(friendlyError(TimeoutException('langsam')),
          contains('Keine Verbindung'));
      expect(friendlyError(http.ClientException('abgebrochen')),
          contains('Keine Verbindung'));
    });

    test('Serverfehler → Code sichtbar', () {
      expect(
          friendlyError(
              const PostgrestException(message: 'x', code: 'PGRST301')),
          contains('PGRST301'));
    });

    test('42501 (RLS-Verbot) heißt: nicht mehr geteilt — kein Serverfehler',
        () {
      // Der reale Fall seit #190: Blatt offen, Freigabe endet, Speichern
      // scheitert an der RLS. „Serverfehler" wäre die falsche Fährte.
      expect(
          friendlyError(
              const PostgrestException(message: 'x', code: '42501')),
          contains('nicht mehr mit dir geteilt'));
    });

    test('Still verworfene Änderung heißt nicht „unerwarteter Fehler"', () {
      // Der stille No-op einer von RLS abgelehnten Zeile (#240). Ohne
      // eigenen Zweig läse der Nutzer „Unerwarteter Fehler
      // (WriteRejectedException)" — richtig, aber unbrauchbar.
      final message =
          friendlyError(const WriteRejectedException('Fund ändern'));
      expect(message, contains('nicht speichern'));
      expect(message, isNot(contains('WriteRejectedException')));
    });

    test('Unerwartetes → Typ sichtbar (diagnostizierbar)', () {
      expect(friendlyError(StateError('kaputt')), contains('StateError'));
    });
  });

  group('Gateway-Timeout (504)', () {
    // Der Wochendigest KW37: 18 von 19 Berichten waren 504er — 15 aus
    // „Passwort-Reset anfordern" (Googles Prüf-Robots klicken den
    // Login-Screen durch), dazu Freundes-Standorte und ein Neuladen der
    // Spots. Keiner davon ist ein Defekt der App.
    final authTimeout =
        AuthRetryableFetchException(message: '', statusCode: '504');
    const restTimeout = PostgrestException(
        message: '', code: '504', details: 'Gateway Timeout');

    test('zählt als fehlender Empfang — aus beiden Paketen', () {
      // Daran hängt der Ausgangskorb: `_queueIfOffline` fragt genau das,
      // bevor ein Fund liegen bleibt statt verloren zu gehen.
      expect(looksOffline(authTimeout), isTrue);
      expect(looksOffline(restTimeout), isTrue);
    });

    test('aber nicht gemeldet — der Digest ist für Defekte da', () {
      expect(worthReporting(authTimeout), isFalse);
      expect(worthReporting(restTimeout), isFalse);
    });

    test('die Meldung schickt niemanden ins eigene Netz', () {
      // „bitte Internet prüfen" wäre hier die falsche Fährte: Wer eine
      // 504 bekommt, hat sehr wohl eine Verbindung.
      expect(friendlyError(authTimeout), isNot(contains('Internet')));
      expect(friendlyError(restTimeout), isNot(contains('Internet')));
      expect(friendlyError(restTimeout), contains('zu lange'));
    });

    test('die anderen 5xx behalten ihren Weg nach draußen (#80)', () {
      // **Die tragende Zeile dieser Gruppe.** 500, 502 und 503 heißen:
      // Der Server hat geantwortet, und die Antwort ist kaputt. Genau
      // dafür ist die Grenze da — ein kaputtes Deployment darf sich
      // nicht hinter einer alten Kopie und einem stillen Korb
      // verstecken.
      for (final code in ['500', '502', '503']) {
        final rest = PostgrestException(message: '', code: code);
        expect(looksOffline(rest), isFalse, reason: '$code gilt als offline');
        expect(worthReporting(rest), isTrue, reason: '$code wird verschwiegen');
        expect(friendlyError(rest), contains(code));

        final auth = AuthRetryableFetchException(message: '', statusCode: code);
        expect(looksOffline(auth), isFalse, reason: '$code gilt als offline');
        expect(worthReporting(auth), isTrue, reason: '$code wird verschwiegen');
      }
    });

    test('ohne Antwort bleibt es der alte Netzfehler-Weg', () {
      // `statusCode == null` heißt: Es kam gar keine HTTP-Antwort. Der
      // Fall stand schon vorher in `looksOffline` und behält seine
      // Meldung.
      final noAnswer = AuthRetryableFetchException(message: '');
      expect(looksOffline(noAnswer), isTrue);
      expect(friendlyError(noAnswer), contains('Keine Verbindung'));
    });
  });

  group('loginErrorMessage', () {
    test('typisierter Code invalid_credentials', () {
      expect(
          loginErrorMessage(const AuthException('x',
              code: 'invalid_credentials')),
          'E-Mail oder Passwort falsch.');
    });

    test('Fallback über HTTP-Status 400 (ältere Server)', () {
      expect(loginErrorMessage(const AuthException('x', statusCode: '400')),
          'E-Mail oder Passwort falsch.');
    });
  });

  group('signupErrorMessage', () {
    test('typisierter Code user_already_exists', () {
      expect(
          signupErrorMessage(
              const AuthException('x', code: 'user_already_exists')),
          contains('schon ein Konto'));
    });

    test('String-Match "Database error saving new user" bleibt festgenagelt',
        () {
      // Profil-Trigger-Fehler (unique username) kommt als 500 OHNE Code —
      // dieses Matching ist unvermeidbar, siehe core/errors.dart.
      expect(
          signupErrorMessage(const AuthException(
              'AuthApiException: Database error saving new user')),
          'Dieser Benutzername ist schon vergeben.');
    });
  });

  group('usernameChangeErrorMessage', () {
    test('23505 aus PostgREST heißt: Name vergeben — derselbe Text wie '
        'bei der Registrierung', () {
      expect(
          usernameChangeErrorMessage(const PostgrestException(
              message: 'duplicate key value violates unique constraint '
                  '"profiles_username_lower_key"',
              code: '23505')),
          'Dieser Benutzername ist schon vergeben.');
    });

    test('alles andere fällt auf friendlyError zurück', () {
      const other = PostgrestException(message: 'kaputt', code: '42501');
      expect(usernameChangeErrorMessage(other), friendlyError(other));
    });
  });

  group('emailChangeErrorMessage', () {
    test('email_exists nennt die vergebene Adresse beim Namen', () {
      // Kein neues Orakel: Die Registrierung sagt es längst genauso.
      expect(
          emailChangeErrorMessage(
              const AuthException('x', code: 'email_exists')),
          'Für diese Adresse gibt es schon ein Konto.');
    });

    test('invalid_credentials heißt: das aktuelle Passwort', () {
      // Der Fehler kommt aus der vorgeschalteten frischen Anmeldung —
      // „E-Mail oder Passwort falsch" schickte den Leser zur falschen
      // Maske.
      expect(
          emailChangeErrorMessage(
              const AuthException('x', code: 'invalid_credentials')),
          'Das aktuelle Passwort stimmt nicht.');
    });

    test('otp_expired ist der abgetippte Code', () {
      expect(
          emailChangeErrorMessage(
              const AuthException('x', code: 'otp_expired')),
          contains('falsch oder abgelaufen'));
    });
  });

  group('loginErrorMessage: unbestätigte Adresse', () {
    test('email_not_confirmed geht dem 400-Fallback vor', () {
      // Der Fall kommt AUCH als 400. Ohne Vorrang läse er sich als
      // „E-Mail oder Passwort falsch" — und das Passwort stimmt ja.
      expect(
          loginErrorMessage(const AuthException('x',
              statusCode: '400', code: 'email_not_confirmed')),
          contains('bestätige zuerst'));
    });
  });

  group('resetErrorMessage', () {
    test('otp_expired führt zum neuen Code', () {
      expect(resetErrorMessage(const AuthException('x', code: 'otp_expired')),
          contains('neuen'));
    });

    test('Fallback über HTTP-Status 403', () {
      expect(resetErrorMessage(const AuthException('x', statusCode: '403')),
          contains('falsch oder abgelaufen'));
    });

    test('weak_password sagt nicht „zu kurz"', () {
      // Leaked Password Protection lehnt auch lange Passwörter ab.
      final message =
          resetErrorMessage(const AuthException('x', code: 'weak_password'));
      expect(message, contains('zu unsicher'));
      expect(message, isNot(contains('Zeichen')));
    });

    test('same_password nennt den Grund', () {
      expect(
          resetErrorMessage(const AuthException('x', code: 'same_password')),
          contains('bisherige'));
    });
  });

  group('confirmErrorMessage', () {
    test('Rate-Limit bekommt eine eigene Meldung', () {
      // Vorher lief das durch loginErrorMessage und behauptete
      // „Anmeldung fehlgeschlagen" mitten in der Registrierung.
      expect(
          confirmErrorMessage(const AuthException('x',
              statusCode: '429', code: 'over_email_send_rate_limit')),
          contains('warten'));
    });

    test('Falscher Code führt zum neuen Code', () {
      expect(confirmErrorMessage(const AuthException('x', code: 'otp_expired')),
          contains('falsch oder abgelaufen'));
    });

    test('Der Fallback spricht von der Bestätigung, nicht vom Zurücksetzen',
        () {
      final message = confirmErrorMessage(const AuthException('kaputt'));
      expect(message, contains('Bestätigung fehlgeschlagen'));
      expect(message, isNot(contains('Zurücksetzen')));
    });
  });

  group('changePasswordErrorMessage', () {
    test('invalid_credentials meint das AKTUELLE Passwort', () {
      // Der erste Schritt ist eine erneute Anmeldung — „E-Mail oder
      // Passwort falsch" wäre hier irreführend.
      expect(
          changePasswordErrorMessage(
              const AuthException('x', code: 'invalid_credentials')),
          'Das aktuelle Passwort stimmt nicht.');
    });

    test('weak_password geht dem 400-Fallback vor', () {
      // Sonst läse sich ein abgelehntes NEUES Passwort als falsches altes.
      expect(
          changePasswordErrorMessage(const AuthException('x',
              statusCode: '400', code: 'weak_password')),
          contains('zu unsicher'));
    });

    test('same_password geht dem 400-Fallback vor', () {
      expect(
          changePasswordErrorMessage(const AuthException('x',
              statusCode: '400', code: 'same_password')),
          contains('bisherige'));
    });
  });
}
