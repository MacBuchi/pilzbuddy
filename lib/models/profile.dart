class Profile {
  final String id;
  final String username;
  final String? displayName;
  final bool shareSpotsDefault;
  final bool shareDetails;

  const Profile({
    required this.id,
    required this.username,
    this.displayName,
    required this.shareSpotsDefault,
    required this.shareDetails,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        shareSpotsDefault: json['share_spots_default'] as bool? ?? true,
        shareDetails: json['share_details'] as bool? ?? true,
      );
}
