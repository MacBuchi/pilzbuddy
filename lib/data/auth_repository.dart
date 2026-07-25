import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  String? get currentUserId => _client.auth.currentUser?.id;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Schickt einen Zahlencode zum Zurücksetzen des Passworts per Mail.
  ///
  /// Bewusst der Code aus der Mail und NICHT der enthaltene Link: Im
  /// PKCE-Standardflow legt Supabase beim Anfordern einen „code verifier"
  /// im Speicher des *anfragenden* Geräts ab und verlangt ihn beim Einlösen
  /// wieder (`gotrue`: `_generatePKCECodeChallenge`). Wer in der App
  /// anfordert und die Mail dann im Browser öffnet, hat ihn dort nicht —
  /// der Link stirbt mit „Code verifier could not be found in local
  /// storage.". Der Code ist gerätefrei und bleibt in derselben Maske.
  /// Die Mail-Vorlage im Dashboard führt deshalb `{{ .Token }}` und keinen
  /// Link (siehe CLAUDE.md); sonst existiert der kaputte Weg weiter.
  ///
  /// Wirft nicht, wenn es zu der Adresse kein Konto gibt — Supabase
  /// antwortet absichtlich gleich, damit daraus kein Konto-Orakel wird.
  /// Die Oberfläche muss dieselbe Meldung zeigen.
  Future<void> sendPasswordResetCode(String email) =>
      _client.auth.resetPasswordForEmail(email);

  /// Löst den Code ein und setzt das neue Passwort — in einem Schritt.
  ///
  /// `verifyOTP` legt eine Recovery-Sitzung an, erst `updateUser` macht das
  /// neue Passwort gültig. Beides gehört zusammen: bliebe es dazwischen
  /// stehen, wäre jemand angemeldet, ohne sein Passwort zu kennen. Deshalb
  /// lässt der Router eine Recovery-Sitzung allein nicht in die App
  /// (siehe `lib/core/router.dart`) — erst das geänderte Passwort öffnet
  /// sie.
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.recovery,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Löscht das eigene Konto endgültig — sofort, ohne Karenzzeit.
  ///
  /// Serverseitig genügt eine Zeile: alle Tabellen hängen per
  /// `on delete cascade` an `profiles`, das wiederum an `auth.users`
  /// (siehe `supabase/patch_008_konto_loeschen.sql`). Die RPC nimmt
  /// bewusst keine id entgegen — sie löscht immer nur `auth.uid()`.
  ///
  /// Danach lokal abmelden: die Sitzung auf dem Gerät bliebe sonst liegen
  /// und würde bei jedem Request auf einen Nutzer zeigen, den es nicht
  /// mehr gibt.
  Future<void> deleteAccount() async {
    await _client.rpc<void>('delete_own_account');
    await _client.auth.signOut();
  }
}
