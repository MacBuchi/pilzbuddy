/// Eine Freundschafts-Beziehung aus Sicht des angemeldeten Nutzers.
class FriendshipEntry {
  final String id;
  final String status; // 'pending' | 'accepted'
  final String requesterId;
  final String addresseeId;
  final String? requesterUsername;
  final String? addresseeUsername;

  const FriendshipEntry({
    required this.id,
    required this.status,
    required this.requesterId,
    required this.addresseeId,
    this.requesterUsername,
    this.addresseeUsername,
  });

  bool get isAccepted => status == 'accepted';

  bool isIncomingFor(String uid) => status == 'pending' && addresseeId == uid;

  bool isOutgoingFor(String uid) => status == 'pending' && requesterId == uid;

  String otherUsername(String uid) => (requesterId == uid
          ? addresseeUsername
          : requesterUsername) ??
      'Pilzfreund';

  factory FriendshipEntry.fromJson(Map<String, dynamic> json) =>
      FriendshipEntry(
        id: json['id'] as String,
        status: json['status'] as String,
        requesterId: json['requester_id'] as String,
        addresseeId: json['addressee_id'] as String,
        requesterUsername:
            (json['requester'] as Map<String, dynamic>?)?['username'] as String?,
        addresseeUsername:
            (json['addressee'] as Map<String, dynamic>?)?['username'] as String?,
      );
}

/// Suchtreffer der Freundesuche.
class ProfileSearchResult {
  final String id;
  final String username;
  final String? displayName;

  const ProfileSearchResult({
    required this.id,
    required this.username,
    this.displayName,
  });

  factory ProfileSearchResult.fromJson(Map<String, dynamic> json) =>
      ProfileSearchResult(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
      );
}
