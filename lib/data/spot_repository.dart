import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dates.dart';
import '../models/spot.dart';

class SpotRepository {
  SpotRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<List<Spot>> fetchMySpots() async {
    final rows = await _client
        .from('spots')
        .select('*, finds(*)')
        .eq('owner_id', _uid)
        .order('created_at');
    return rows.map((r) => Spot.fromJson(r, currentUserId: _uid)).toList();
  }

  /// Von Freunden geteilte Spots. Die RLS-Policies liefern nur, was der
  /// jeweilige Besitzer freigegeben hat; ohne Detail-Freigabe kommt das
  /// finds-Array leer zurück.
  Future<List<Spot>> fetchFriendSpots() async {
    final rows = await _client
        .from('spots')
        .select('*, finds(*), profiles(username, avatar)')
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

  Future<void> addFind({
    required String spotId,
    String? species,
    int? count,
    required DateTime foundOn,
    String? note,
  }) async {
    await _client.from('finds').insert({
      'spot_id': spotId,
      'species': species,
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
