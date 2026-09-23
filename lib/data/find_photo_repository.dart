// Fundfotos für Buddys (#532): hochladen, lesen, löschen.
//
// **Die Bytes gehen in den Bucket, die Zeile in die Tabelle** — und in
// dieser Reihenfolge. Die Storage-Policy `find_photos_read` gibt ein
// Objekt nur heraus, wenn es eine sichtbare Zeile dazu gibt; ein Objekt
// ohne Zeile ist also für niemanden lesbar, nicht einmal für den, der
// es hochgeladen hat. Bricht der Weg zwischen den beiden Schritten ab,
// bleibt ein unsichtbares Objekt liegen, und das räumt der Feedback-Bot
// beim nächsten Abgleich weg. Andersherum — erst die Zeile, dann die
// Objekte — stünde bei einem Abbruch eine Zeile mit kaputtem Bild bei
// jedem Buddy.
//
// **Hier kommt nur hinein, was `preparePhoto` durchgelassen hat.** Das
// Repository nimmt ein [PreparedPhoto] und keine rohen Bytes; wer den
// Typ in der Hand hat, hat die Pipeline durchlaufen. Die Prüfung steht
// nicht hier, weil ein Repository nicht der Ort ist, an dem ein Bild
// dekodiert wird — aber der Typ sorgt dafür, dass niemand daran vorbei
// kann.
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors.dart';
import '../core/photo_pipeline.dart';
import '../models/find_photo.dart';
import 'file_cache.dart';
import 'object_token.dart';
import 'session.dart';

const kFindPhotoBucket = 'find-photos';

/// Wie lange ein Foto bleibt — die Zahl, die Patch 026 als Default und
/// als Constraint trägt. Hier nur für die Oberfläche („14 Tage
/// sichtbar"); gesetzt wird sie von der Datenbank.
const kFindPhotoDays = 14;

/// Derselbe Rahmen wie für die Artbilder (#537): eine Größe, keine
/// Frist — ein Bild ist jederzeit nachladbar.
const kFindPhotoCacheBytes = 24 * 1024 * 1024;

class FindPhotoRepository {
  FindPhotoRepository(this._client, {BoundedFileCache? cache})
      : _cache = cache ??
            BoundedFileCache(
                dirName: 'find_photos', maxBytes: kFindPhotoCacheBytes);

  final SupabaseClient _client;
  final BoundedFileCache _cache;

  String get _uid => _client.requireUid;

  /// Exakt diese Spalten prüft `tool/schema_check.sh` gegen das
  /// Live-Schema — die beiden Embeds hängen an Fremdschlüsseln, und ein
  /// fehlender antwortet mit PGRST200 statt mit einer leeren Liste.
  ///
  /// Das Kudos-Embed (Patch 028) holt nur `user_id`: Die Tabelle
  /// verweist auf `auth.users`, nicht auf `profiles` — sonst wäre das
  /// `profiles`-Embed daneben mehrdeutig (PGRST201).
  static const columns = 'id, find_id, user_id, key, created_at, expires_at, '
      'profiles(username, avatar), '
      'finds(species, found_on, spot_id, spots(name)), '
      'find_photo_kudos(user_id)';

  StorageFileApi get _bucket => _client.storage.from(kFindPhotoBucket);

  /// Teilt [photo] zu einem eigenen Fund. Liefert die Zeile, wie sie
  /// der Betrachter sieht — mit Frist, Art und Spot.
  Future<FindPhoto> share({
    required String findId,
    required PreparedPhoto photo,
  }) async {
    // `<user_id>/<zufall>`: Der Ordner ist der Nutzer, das ist die
    // Bedingung der Upload-Policy.
    final key = '$_uid/${newObjectToken()}';
    const jpeg = FileOptions(contentType: 'image/jpeg', upsert: false);
    await _bucket.uploadBinary('$key.jpg', photo.full, fileOptions: jpeg);
    await _bucket.uploadBinary('${key}_s.jpg', photo.thumb, fileOptions: jpeg);
    final Map<String, dynamic> row;
    try {
      row = await _client
          .from('find_photos')
          .insert({'find_id': findId, 'user_id': _uid, 'key': key})
          .select(columns)
          .single();
    } catch (_) {
      // Die Zeile ist gescheitert (Freigabe weg, Netz weg): Die beiden
      // Objekte wieder abräumen, so gut es geht. Scheitert auch das,
      // findet sie der Bot — deshalb darf dieser zweite Fehler still
      // sein; gemeldet wird der erste.
      try {
        await _bucket.remove(['$key.jpg', '${key}_s.jpg']);
      } catch (_) {}
      rethrow;
    }
    // Was ich eben hochgeladen habe, muss ich nicht wieder holen.
    await _cache.write('$key.jpg', photo.full);
    await _cache.write('${key}_s.jpg', photo.thumb);
    return FindPhoto.fromJson(row, myUid: _uid);
  }

  /// Nimmt ein eigenes Foto zurück — vor der Frist.
  ///
  /// Zeile zuerst: Ohne sie ist das Objekt für niemanden mehr lesbar
  /// (Policy `find_photos_read`), die Wirkung tritt also mit dem
  /// ersten Schritt ein. Die Objekte danach; scheitert das, räumt der
  /// Bot beim nächsten Abgleich auf.
  Future<void> delete(FindPhoto photo) async {
    await _client.from('find_photos').delete().eq('id', photo.id);
    try {
      await _bucket.remove([photo.fullPath, photo.thumbPath]);
    } catch (e, s) {
      logError('Fundfoto-Datei löschen', e, s);
    }
  }

  /// Einen Pilz geben (Patch 028). `user_id` füllt der Spalten-Default;
  /// ans eigene Foto lehnt die Policy ab.
  ///
  /// Ein zweites Geben ist kein Fehler: Die Zeile steht schon (23505),
  /// und das ist genau der Zustand, den der Tipp wollte — etwa nach
  /// einem Doppeltipp oder einer Antwort, die unterwegs verloren ging.
  Future<void> giveKudos(String photoId) async {
    try {
      await _client.from('find_photo_kudos').insert({'photo_id': photoId});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  /// Den eigenen Pilz zurücknehmen.
  Future<void> takeBackKudos(String photoId) => _client
      .from('find_photo_kudos')
      .delete()
      .eq('photo_id', photoId)
      .eq('user_id', _uid);

  /// Alle Fotos, die ich sehen darf — jüngste zuerst, so wie die
  /// Policies sie liefern: eigene immer, fremde nur mit lesbarem Fund
  /// und vor der Frist. **Eigene abgelaufene sind dabei** (`fp_owner_all`
  /// kennt keine Frist, sonst könnte man sie nicht mehr löschen); die
  /// Frist zieht `findPhotosProvider`, damit sie für Fake und echt
  /// gleich gilt.
  Future<List<FindPhoto>> fetchVisible() async {
    final rows = await _client
        .from('find_photos')
        .select(columns)
        .order('created_at', ascending: false);
    return [for (final row in rows) FindPhoto.fromJson(row, myUid: _uid)];
  }

  /// Die Bytes zu [path] — aus dem Speicher oder vom Bucket. `null`,
  /// wenn nicht zu holen. Wirft nie: Ein Bild ist eine Zugabe.
  Future<Uint8List?> loadBytes(String path) async {
    final cached = await _cache.read(path);
    if (cached != null) return cached;
    try {
      final bytes = await _bucket.download(path);
      await _cache.write(path, bytes);
      return bytes;
    } catch (e, s) {
      // Ohne Empfang der Normalfall — kein `logError`, sonst füllt
      // jeder Waldgang den Wochendigest (#124). Alles andere (Policy,
      // Bucket) ist ein Befund und wird gemeldet.
      if (!looksOffline(e)) logError('Fundfoto laden', e, s);
      return null;
    }
  }
}
