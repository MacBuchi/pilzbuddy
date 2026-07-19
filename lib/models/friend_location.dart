import 'package:latlong2/latlong.dart';

/// Live-Standort eines Freundes, den dieser zeitlich begrenzt teilt.
/// Die RLS-Policy liefert nur nicht abgelaufene Zeilen akzeptierter
/// Freunde; `isActive` ist ein defensiver Zusatzfilter auf Client-Seite.
class FriendLocation {
  final String userId;
  final double lat;
  final double lng;
  final DateTime expiresAt;
  final String? username;
  final int avatar;

  const FriendLocation({
    required this.userId,
    required this.lat,
    required this.lng,
    required this.expiresAt,
    this.username,
    this.avatar = 0,
  });

  LatLng get position => LatLng(lat, lng);

  bool get isActive => expiresAt.isAfter(DateTime.now().toUtc());

  factory FriendLocation.fromJson(Map<String, dynamic> json) => FriendLocation(
        userId: json['user_id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
        username:
            (json['profiles'] as Map<String, dynamic>?)?['username'] as String?,
        avatar:
            (json['profiles'] as Map<String, dynamic>?)?['avatar'] as int? ?? 0,
      );
}
