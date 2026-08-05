import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dates.dart';
import '../core/mushroom_species.dart';
import '../models/spot.dart';
import 'session.dart';
import 'spot_cache.dart';

/// Die eigenen Spots samt Herkunft: `cachedAt == null` heißt frisch aus
/// dem Netz, sonst stammen sie aus dem Zwischenspeicher und sind von
/// diesem Zeitpunkt.
typedef SpotsSnapshot = ({List<Spot> spots, DateTime? cachedAt});

class SpotRepository {
  SpotRepository(this._client, {SpotCache? cache}) : _cache = cache;

  final SupabaseClient _client;
  final SpotCache? _cache;

  /// Nach dieser Zeit gilt der Abruf als gescheitert und der
  /// Zwischenspeicher übernimmt.
  ///
  /// Nötig, weil postgrest GET-Anfragen von sich aus dreimal wiederholt
  /// (Backoff 1+2+4 s). Ohne Deckel wartet die Karte im Funkloch alle
  /// vier Versuche ab — und bei „ein Balken, keine Daten" hängt jeder
  /// davon am Zeitlimit des Systems, was Minuten bedeuten kann. Genau
  /// dann soll die Offline-Kopie zügig einspringen.
  static const fetchTimeout = Duration(seconds: 10);

  String get _uid => _client.requireUid;

  /// Eigene Spots. Ohne Empfang kommen sie aus dem Zwischenspeicher —
  /// siehe `spot_cache.dart` für den Grund.
  Future<SpotsSnapshot> fetchMySpots() async {
    final uid = _uid;
    Future<List<Map<String, dynamic>>> fetch() async {
      // Der Autor kommt als benannter Embed über den FK-Namen mit —
      // seit Patch 014 können auch Buddies an eigenen Spots Funde haben,
      // und die Fundliste nennt dann, von wem einer stammt.
      final rows = await _client
          .from('spots')
          .select(
              '*, finds(*, author:profiles!finds_author_id_fkey(username, avatar))')
          .eq('owner_id', uid)
          .order('created_at')
          .timeout(fetchTimeout);
      return rows.cast<Map<String, dynamic>>();
    }

    final cache = _cache;
    final result = cache == null
        ? (rows: await fetch(), cachedAt: null)
        : await fetchSpotRowsWithCache(
            fetch: fetch,
            cache: cache,
            uid: uid,
            now: DateTime.now(),
          );
    return (
      spots: [
        for (final row in result.rows) Spot.fromJson(row, currentUserId: uid),
      ],
      cachedAt: result.cachedAt,
    );
  }

  /// Von Freunden geteilte Spots. Die RLS-Policies liefern nur, was der
  /// jeweilige Besitzer freigegeben hat; ohne Detail-Freigabe kommen von
  /// seinen Funden keine — die EIGENEN am Freundes-Spot liefert
  /// `finds_author_all` immer (Patch 014).
  Future<List<Spot>> fetchFriendSpots() async {
    final rows = await _client
        .from('spots')
        .select(
            '*, finds(*, author:profiles!finds_author_id_fkey(username, avatar)), profiles(username, avatar)')
        .neq('owner_id', _uid);
    return rows.map((r) => Spot.fromJson(r, currentUserId: _uid)).toList();
  }

  Future<void> addSpot({
    required double lat,
    required double lng,
    String? name,
    String? species,
    int? count,
    required DateTime foundOn,
    String? note,
  }) async {
    final spot = await _client
        .from('spots')
        .insert({'owner_id': _uid, 'name': name, 'lat': lat, 'lng': lng})
        .select('id')
        .single();
    await addFind(
      spotId: spot['id'] as String,
      species: species,
      count: count,
      foundOn: foundOn,
      note: note,
    );
  }

  /// Legt einen Fund an. Der Artname wird dabei auf die Hauptbezeichnung
  /// gebracht ([canonicalSpecies]) — „Totentrompete" wird als
  /// „Herbsttrompete" gespeichert. Das ist die einzige Schreibstelle für
  /// Funde, [addSpot] und der GPX-Import laufen ebenfalls hier durch;
  /// deshalb genügt diese eine Zeile, damit in der Datenbank keine zwei
  /// Namen für dieselbe Art nebeneinander liegen. Eigene Arten der Nutzer
  /// bleiben unverändert.
  ///
  /// `author_id` wird bewusst NICHT mitgesendet: Der Spalten-Default
  /// `auth.uid()` füllt ihn serverseitig (Patch 014) — derselbe Weg, den
  /// auch ältere Clients nehmen, die die Spalte gar nicht kennen.
  Future<void> addFind({
    required String spotId,
    String? species,
    int? count,
    required DateTime foundOn,
    String? note,
  }) async {
    await _client.from('finds').insert({
      'spot_id': spotId,
      'species': canonicalSpecies(species),
      'count': count,
      'found_on': isoDate(foundOn),
      'note': note,
    });
  }

  Future<void> deleteSpot(String spotId) async {
    await _client.from('spots').delete().eq('id', spotId);
  }

  Future<void> setSharingExcluded(String spotId, bool excluded) async {
    await _client
        .from('spots')
        .update({'sharing_excluded': excluded}).eq('id', spotId);
  }
}
