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

/// So viele Bilder darf eine Meldung tragen — derselbe Wert wie der
/// Check in Patch 033 (#569).
const kFeedbackMaxPhotos = 3;

/// Unter dieser Lizenz dürfen Bilder mit Einwilligung in die Artgalerie
/// (Patch 034) — dieselbe wie bei den eigenen Aufnahmen des Betreibers.
/// NC und ND scheiden aus: `species_photos_test.dart` lässt sie nicht zu.
const kGalleryPhotoLicence = 'CC BY-SA 4.0';

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
  /// [photos] (#525, seit #569 bis zu [kFeedbackMaxPhotos]): nur als
  /// [PreparedPhoto], also nach der Pipeline. Sie gehen in den Bucket,
  /// die Zeile trägt die Pfade.
  ///
  /// [galleryConsent] (Patch 034): Die Bilder dürfen unter
  /// [kGalleryPhotoLicence] mit dem Benutzernamen als Urheber in die
  /// Artgalerie. Ohne Bilder wird es ignoriert — die Datenbank ließe es
  /// ohnehin nicht zu.
  Future<void> submit(FeedbackType type, String message,
      {String? appVersion,
      List<PreparedPhoto> photos = const [],
      bool galleryConsent = false}) async {
    await _insert({
      'user_id': _client.requireUid,
      'type': type == FeedbackType.bug ? 'bug' : 'feature',
      'message': message.trim(),
      'app_version': appVersion,
      if (galleryConsent && photos.isNotEmpty) 'photo_consent': true,
    }, photos);
  }

  /// Neue Pilzart vorschlagen — der Feedback-Bot baut daraus einen PR,
  /// den der Betreiber nur noch annehmen/ablehnen muss.
  Future<void> submitSpecies(String speciesName,
      {String? note,
      String? appVersion,
      List<PreparedPhoto> photos = const []}) async {
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
    }, photos);
  }

  Future<void> _insert(
      Map<String, dynamic> row, List<PreparedPhoto> photos) async {
    if (photos.length > kFeedbackMaxPhotos) {
      throw ArgumentError('höchstens $kFeedbackMaxPhotos Bilder');
    }
    // Erst die Objekte, dann die Zeile — wie bei den Fundfotos: Ein
    // Objekt ohne Zeile ist ein Waisenkind für den Bot, eine Zeile mit
    // fehlendem Bild wäre ein Issue, das auf nichts zeigt.
    //
    // Scheitert ein Upload oder die Zeile, bleiben die schon
    // hochgeladenen Objekte liegen: Löschen dürfen Nutzer in diesem
    // Bucket nicht (Patch 027 — das frühere Aufräumen hier lief deshalb
    // immer ins Leere), und der Bot fegt sie nach [kFeedbackPhotoDays]
    // Tagen.
    final paths = <String>[];
    for (final photo in photos) {
      final path = '${_client.requireUid}/${newObjectToken()}.jpg';
      await _client.storage.from(kFeedbackPhotoBucket).uploadBinary(
          path, photo.full,
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
      paths.add(path);
    }
    // NUR `photo_paths` (Patch 033). `photo_path` gehört den Clients bis
    // 1.195.x — zwei Spalten mit derselben Aussage wären zwei Wahrheiten.
    await _client
        .from('feedback')
        .insert({...row, 'photo_paths': paths.isEmpty ? null : paths});
  }
}
