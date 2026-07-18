import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<Profile> fetchMyProfile() async {
    final row =
        await _client.from('profiles').select().eq('id', _uid).single();
    return Profile.fromJson(row);
  }

  Future<void> updateAvatar(int avatar) async {
    await _client.from('profiles').update({'avatar': avatar}).eq('id', _uid);
  }

  Future<void> updateSharing({
    bool? shareSpotsDefault,
    bool? shareDetails,
  }) async {
    await _client.from('profiles').update({
      'share_spots_default': ?shareSpotsDefault,
      'share_details': ?shareDetails,
    }).eq('id', _uid);
  }
}
