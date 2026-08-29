import 'package:supabase_flutter/supabase_flutter.dart';

import 'session.dart';

enum FeedbackType { feature, bug, species }

class FeedbackRepository {
  FeedbackRepository(this._client);

  final SupabaseClient _client;

  /// Feature-Wunsch oder Bug-Meldung einreichen — der Feedback-Bot legt
  /// daraus ein passend gelabeltes GitHub-Issue an.
  ///
  /// [appVersion] steht seit #358 im Issue. Ohne sie war bei einer
  /// Feldmeldung nicht entscheidbar, ob sie ein Duplikat einer schon
  /// behobenen ist oder ein neuer Fehler im frischen Stand — die Frage
  /// musste beim Melder zurückgestellt werden. `null` ist erlaubt und
  /// heißt schlicht „unbekannt": Eine erfundene Version wäre schlimmer.
  ///
  /// Sie kommt als PARAMETER und nicht aus `PackageInfo` im Repository:
  /// `appVersionProvider` hält sie ohnehin schon, und über den Parameter
  /// ist sie im Test überprüfbar statt immer null.
  Future<void> submit(FeedbackType type, String message,
      {String? appVersion}) async {
    await _client.from('feedback').insert({
      'user_id': _client.requireUid,
      'type': type == FeedbackType.bug ? 'bug' : 'feature',
      'message': message.trim(),
      'app_version': appVersion,
    });
  }

  /// Neue Pilzart vorschlagen — der Feedback-Bot baut daraus einen PR,
  /// den der Betreiber nur noch annehmen/ablehnen muss.
  Future<void> submitSpecies(String speciesName,
      {String? note, String? appVersion}) async {
    final name = speciesName.trim();
    await _client.from('feedback').insert({
      'user_id': _client.requireUid,
      'type': 'species',
      'species_name': name,
      'app_version': appVersion,
      'message': [
        'Pilzart-Vorschlag: $name',
        if (note != null && note.trim().isNotEmpty) note.trim(),
      ].join(' — '),
    });
  }
}
