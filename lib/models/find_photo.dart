/// Ein geteiltes Fundfoto (#532) — die Zeile aus `find_photos`, aus
/// Sicht des Betrachters.
///
/// Das Bild selbst liegt nicht in der Zeile, sondern im Bucket
/// `find-photos` unter [fullPath] und [thumbPath]; die Zeile trägt nur
/// den Schlüssel. Sichtbar ist sie, wem der FUND sichtbar ist — die
/// Policy `fp_friend_select` fragt `finds` und erbt damit dessen
/// Freigabe, statt eine zweite zu erfinden. Und sie läuft ab:
/// `expires_at` wird von der Datenbank gesetzt und ist per Constraint
/// auf 14 Tage begrenzt; [isActive] ist nur der defensive Zusatz wie
/// bei `BuddyTrack`.
class FindPhoto {
  const FindPhoto({
    required this.id,
    required this.findId,
    required this.userId,
    required this.key,
    required this.createdAt,
    required this.expiresAt,
    required this.isOwn,
    this.username,
    this.avatar = 0,
    this.species,
    this.foundOn,
    this.spotId,
    this.spotName,
  });

  final String id;
  final String findId;
  final String userId;

  /// Pfad im Bucket OHNE Endung: `<user_id>/<id>`. Der Ordner ist der
  /// Nutzer — die Storage-Policy für das Hochladen prüft genau das.
  final String key;

  String get fullPath => '$key.jpg';
  String get thumbPath => '${key}_s.jpg';

  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isOwn;

  /// Wer geteilt hat — `null` nur, wenn das Profil-Embed fehlt.
  final String? username;
  final int avatar;

  /// Aus dem Fund, an dem das Foto hängt. `null`, wenn der Fund für
  /// den Betrachter nicht mehr lesbar ist (die Freigabe endete zwischen
  /// zwei Abfragen) — dann steht das Foto ohne Art und Spot da, statt
  /// dass die ganze Liste scheitert.
  final String? species;
  final DateTime? foundOn;
  final String? spotId;
  final String? spotName;

  bool get isActive => expiresAt.isAfter(DateTime.now().toUtc());

  /// Wie viele ganze Tage das Foto noch bleibt — mindestens 0.
  int daysLeft(DateTime now) {
    final left = expiresAt.difference(now.toUtc()).inDays;
    return left < 0 ? 0 : left;
  }

  factory FindPhoto.fromJson(Map<String, dynamic> json,
      {required String myUid}) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final find = json['finds'] as Map<String, dynamic>?;
    final spot = find?['spots'] as Map<String, dynamic>?;
    final userId = json['user_id'] as String;
    return FindPhoto(
      id: json['id'] as String,
      findId: json['find_id'] as String,
      userId: userId,
      key: json['key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      isOwn: userId == myUid,
      username: profile?['username'] as String?,
      avatar: profile?['avatar'] as int? ?? 0,
      species: find?['species'] as String?,
      foundOn: find?['found_on'] == null
          ? null
          : DateTime.parse(find!['found_on'] as String),
      spotId: find?['spot_id'] as String?,
      spotName: spot?['name'] as String?,
    );
  }
}
