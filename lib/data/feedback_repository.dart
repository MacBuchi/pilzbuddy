import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/photo_pipeline.dart';
import 'object_token.dart';
import 'session.dart';

enum FeedbackType { feature, bug, species }

/// Wo ein Bild am Feedback liegt (#525, Patch 027). Privat, und zwar
/// strenger als `find-photos`: Nutzer dürfen nur hineinlegen, lesen
/// darf allein der Betreiber (Service-Schlüssel, Dashboard). Das Bild
/// wird — anders als der Text — NICHT veröffentlicht.
const kFeedbackPhotoBucket = 'feedback-photos';

/// Wie lange ein Bild am Feedback bleibt — dieselbe Frist wie die
/// Fehlerberichte (`ERROR_REPORT_RETENTION_DAYS` im Bot).
const kFeedbackPhotoDays = 90;

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
  ///
  /// [photo] (#525): ein Bild dazu — nur als [PreparedPhoto], also nach
  /// der Pipeline. Es geht in den Bucket, die Zeile trägt den Pfad;
  /// scheitert die Zeile, wird das Objekt wieder abgeräumt (der Bot
  /// fegt nach 90 Tagen ohnehin).
  Future<void> submit(FeedbackType type, String message,
      {String? appVersion, PreparedPhoto? photo}) async {
    await _insert({
      'user_id': _client.requireUid,
      'type': type == FeedbackType.bug ? 'bug' : 'feature',
      'message': message.trim(),
      'app_version': appVersion,
    }, photo);
  }

  /// Neue Pilzart vorschlagen — der Feedback-Bot baut daraus einen PR,
  /// den der Betreiber nur noch annehmen/ablehnen muss.
  Future<void> submitSpecies(String speciesName,
      {String? note, String? appVersion, PreparedPhoto? photo}) async {
    final name = speciesName.trim();
    await _insert({
      'user_id': _client.requireUid,
      'type': 'species',
      'species_name': name,
      'app_version': appVersion,
      'message': [
        'Pilzart-Vorschlag: $name',
        if (note != null && note.trim().isNotEmpty) note.trim(),
      ].join(' — '),
    }, photo);
  }

  Future<void> _insert(Map<String, dynamic> row, PreparedPhoto? photo) async {
    String? path;
    if (photo != null) {
      // Erst das Objekt, dann die Zeile — wie bei den Fundfotos: Ein
      // Objekt ohne Zeile ist ein Waisenkind für den Bot, eine Zeile
      // mit fehlendem Bild wäre ein Issue, das auf nichts zeigt.
      path = '${_client.requireUid}/${newObjectToken()}.jpg';
      await _client.storage.from(kFeedbackPhotoBucket).uploadBinary(
          path, photo.full,
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
    }
    try {
      await _client.from('feedback').insert({...row, 'photo_path': path});
    } catch (_) {
      if (path != null) {
        // Aufräumen nach bestem Bemühen; gemeldet wird der erste Fehler.
        try {
          await _client.storage.from(kFeedbackPhotoBucket).remove([path]);
        } catch (_) {}
      }
      rethrow;
    }
  }
}
