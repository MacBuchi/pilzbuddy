import 'package:supabase_flutter/supabase_flutter.dart';

class FeedbackRepository {
  FeedbackRepository(this._client);

  final SupabaseClient _client;

  Future<void> submit(String message) async {
    await _client.from('feedback').insert({
      'user_id': _client.auth.currentUser!.id,
      'message': message.trim(),
    });
  }
}
