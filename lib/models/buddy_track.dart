import '../features/tour/tour_track.dart';

/// Die Spur der laufenden Pilztour eines Buddys (#340, Stufe 2).
///
/// Dasselbe Muster wie [FriendLocation]: Die RLS-Policy
/// (`tt_friend_select`, Patch 023) liefert nur nicht abgelaufene Zeilen
/// akzeptierter Freunde; [isActive] ist der defensive Zusatzfilter auf
/// Client-Seite.
class BuddyTrack {
  const BuddyTrack({
    required this.userId,
    required this.startedAt,
    required this.points,
    required this.expiresAt,
    this.username,
    this.avatar = 0,
  });

  final String userId;
  final DateTime startedAt;

  /// Schon gedünnt — so hat der Sender sie abgelegt.
  final List<TourPoint> points;

  final DateTime expiresAt;
  final String? username;
  final int avatar;

  bool get isActive => expiresAt.isAfter(DateTime.now().toUtc());

  factory BuddyTrack.fromJson(Map<String, dynamic> json) => BuddyTrack(
        userId: json['user_id'] as String,
        startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
        points: decodeTrackPoints(json['points']),
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
        username:
            (json['profiles'] as Map<String, dynamic>?)?['username'] as String?,
        avatar:
            (json['profiles'] as Map<String, dynamic>?)?['avatar'] as int? ?? 0,
      );
}
