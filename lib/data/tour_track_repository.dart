// Die Spur einer laufenden Pilztour für Buddys (#340, Stufe 2).
//
// **Was hier NEU ist, und zwar als Zusage:** Bis Stufe 1 verließ die
// Spur das Gerät nie. Dieses Repository ist die einzige Stelle, an der
// sie das tut — und nur unter der Bedingung, die [uploadMyTrack]
// beschreibt.
//
// Genau ein Zeilen-Upsert je Nutzer, wie `LiveShareRepository`: Die
// Sichtbarkeit erledigen die Policies (`tt_owner_all`,
// `tt_friend_select`, Patch 023), und `expires_at` kommt aus der
// laufenden Standort-Freigabe.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/tour/tour_track.dart';
import '../models/buddy_track.dart';
import 'session.dart';

class TourTrackRepository {
  TourTrackRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.requireUid;

  /// Lädt meine Spur hoch — ersetzt die vorige Zeile vollständig.
  ///
  /// **[expiresAt] kommt von der Standort-Freigabe, nicht von der Tour.**
  /// Die Spur ist genau so lange sichtbar wie der Standort, den sie
  /// erklärt; wer nicht teilt, ruft das hier gar nicht erst auf. Eine
  /// eigene Frist wäre eine zweite Zustimmung auf dieselbe Entscheidung
  /// — und zwei Fristen, die auseinanderlaufen können.
  ///
  /// [points] gehört GEDÜNNT herein (`thinnedTrack`). Roh wären es bei
  /// 15-Sekunden-Takt rund 720 Punkte je Drei-Stunden-Tour; gedünnt sind
  /// es höchstens 400 und damit rund 10 KB — und das Auge löst mehr
  /// ohnehin nicht auf.
  Future<void> uploadMyTrack({
    required DateTime startedAt,
    required List<TourPoint> points,
    required DateTime expiresAt,
  }) async {
    await _client.from('tour_tracks').upsert({
      'user_id': _uid,
      'started_at': startedAt.toUtc().toIso8601String(),
      'points': [for (final p in points) encodeTrackPoint(p)],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    });
  }

  /// Nimmt meine Spur vom Server.
  ///
  /// Gerufen beim Beenden der Tour und beim Beenden des Teilens — beides
  /// sind Momente, in denen der Nutzer etwas zurücknimmt. Ohne das läge
  /// sie bis `expires_at` weiter da, und das wäre eine Freigabe, die
  /// niemand mehr gibt.
  Future<void> deleteMyTrack() async {
    await _client.from('tour_tracks').delete().eq('user_id', _uid);
  }

  /// Die Spuren meiner Buddys. Die Policy liefert nur nicht abgelaufene
  /// Zeilen akzeptierter Freunde; die eigene wird ausgeblendet.
  ///
  /// Schon hier, obwohl erst die Anzeige (zweiter PR) sie braucht: Eine
  /// Tabelle, die nur beschrieben und nie gelesen wird, lässt sich nicht
  /// gegen die RLS prüfen — und genau die Leserichtung ist der Teil, der
  /// falsch sein könnte.
  Future<List<BuddyTrack>> fetchFriendTracks() async {
    final rows = await _client
        .from('tour_tracks')
        .select('user_id, started_at, points, expires_at, '
            'profiles(username, avatar)')
        .neq('user_id', _uid);
    return rows
        .map(BuddyTrack.fromJson)
        .where((t) => t.isActive)
        .toList();
  }
}
