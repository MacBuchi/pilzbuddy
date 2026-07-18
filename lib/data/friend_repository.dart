import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friendship.dart';

class FriendRepository {
  FriendRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<List<ProfileSearchResult>> search(String query) async {
    final rows = await _client
        .rpc('search_profiles', params: {'query': query}) as List<dynamic>;
    return rows
        .map((r) => ProfileSearchResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<FriendshipEntry>> fetchFriendships() async {
    final rows = await _client.from('friendships').select(
        'id, status, requester_id, addressee_id, '
        'requester:profiles!friendships_requester_id_fkey(username), '
        'addressee:profiles!friendships_addressee_id_fkey(username)');
    return rows.map((r) => FriendshipEntry.fromJson(r)).toList();
  }

  Future<void> sendRequest(String addresseeId) async {
    await _client.from('friendships').insert({
      'requester_id': _uid,
      'addressee_id': addresseeId,
    });
  }

  Future<void> accept(String friendshipId) async {
    await _client
        .from('friendships')
        .update({'status': 'accepted'}).eq('id', friendshipId);
  }

  /// Ablehnen, Anfrage zurückziehen oder Freundschaft beenden.
  Future<void> remove(String friendshipId) async {
    await _client.from('friendships').delete().eq('id', friendshipId);
  }
}
