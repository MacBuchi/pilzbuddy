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
      expect(friendlyError(const PostgrestException(message: 'x', code: '42501')),
          contains('42501'));
    });

    test('Unerwartetes → Typ sichtbar (diagnostizierbar)', () {
      expect(friendlyError(StateError('kaputt')), contains('StateError'));
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
}
