import 'package:supabase_flutter/supabase_flutter.dart';

enum FeedbackType { feature, bug, species }

class FeedbackRepository {
  FeedbackRepository(this._client);

  final SupabaseClient _client;

  /// Feature-Wunsch oder Bug-Meldung einreichen — der Feedback-Bot legt
  /// daraus ein passend gelabeltes GitHub-Issue an.
  Future<void> submit(FeedbackType type, String message) async {
    await _client.from('feedback').insert({
      'user_id': _client.auth.currentUser!.id,
      'type': type == FeedbackType.bug ? 'bug' : 'feature',
      'message': message.trim(),
    });
  }

  /// Neue Pilzart vorschlagen — der Feedback-Bot baut daraus einen PR,
  /// den der Betreiber nur noch annehmen/ablehnen muss.
  Future<void> submitSpecies(String speciesName, {String? note}) async {
    final name = speciesName.trim();
    await _client.from('feedback').insert({
      'user_id': _client.auth.currentUser!.id,
      'type': 'species',
      'species_name': name,
      'message': [
        'Pilzart-Vorschlag: $name',
        if (note != null && note.trim().isNotEmpty) note.trim(),
      ].join(' — '),
    });
  }
}
