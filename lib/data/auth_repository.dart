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
