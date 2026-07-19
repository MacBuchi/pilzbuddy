import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend_location.dart';

/// Zeitlich begrenztes Live-Standort-Teilen. Genau eine Zeile pro Nutzer
/// (Upsert); die RLS-Policies erledigen die Sichtbarkeit — Freunde sehen
/// die eigene Zeile nur, solange sie nicht abgelaufen ist.
class LiveShareRepository {
  LiveShareRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// Meine aktuelle Position teilen (bzw. aktualisieren). `expiresAt` legt
  /// fest, bis wann Freunde mich sehen; bei jedem Positions-Tick erneut.
  Future<void> upsertMyLocation({
    required double lat,
    required double lng,
    required DateTime expiresAt,
  }) async {
    await _client.from('live_locations').upsert({
      'user_id': _uid,
      'lat': lat,
      'lng': lng,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    });
  }

  /// Ende meiner laufenden Freigabe, oder null, wenn ich gerade nicht
  /// (mehr) teile bzw. die Freigabe abgelaufen ist.
  Future<DateTime?> fetchMyShare() async {
    final row = await _client
        .from('live_locations')
        .select('expires_at')
        .eq('user_id', _uid)
        .maybeSingle();
    if (row == null) return null;
    final expiresAt = DateTime.parse(row['expires_at'] as String).toUtc();
    return expiresAt.isAfter(DateTime.now().toUtc()) ? expiresAt : null;
  }

  /// Standort-Teilen beenden.
  Future<void> stopSharing() async {
    await _client.from('live_locations').delete().eq('user_id', _uid);
  }

  /// Live-Standorte von Freunden. Die RLS-Policy liefert nur nicht
  /// abgelaufene Zeilen akzeptierter Freunde; die eigene wird ausgeblendet.
  Future<List<FriendLocation>> fetchFriendLocations() async {
    final rows = await _client
        .from('live_locations')
        .select('user_id, lat, lng, expires_at, profiles(username, avatar)')
        .neq('user_id', _uid);
    return rows
        .map(FriendLocation.fromJson)
        .where((l) => l.isActive)
        .toList();
  }
}
