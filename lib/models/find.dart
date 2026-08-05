class Find {
  final String id;
  final String spotId;
  final String? species;
  final int? count;
  final DateTime foundOn;
  final String? note;
  final DateTime? createdAt;

  /// Wer den Fund eingetragen hat (Patch 014). `null` nur bei Zeilen aus
  /// dem Offline-Cache einer älteren App-Version — vor Patch 014 gab es
  /// keine fremden Funde, deshalb zählt `null` als eigener Fund.
  final String? authorId;
  final String? authorUsername;
  final int authorAvatar;

  /// Ob der Fund vom angemeldeten Nutzer stammt. Fremde Funde bekommen in
  /// der Fundliste eine Zuschreibung und bleiben aus Statistik, Art-
  /// Vorschlägen und GPX-Export heraus — sie sind Daten des Autors.
  final bool isOwn;

  const Find({
    required this.id,
    required this.spotId,
    this.species,
    this.count,
    required this.foundOn,
    this.note,
    this.createdAt,
    this.authorId,
    this.authorUsername,
    this.authorAvatar = 0,
    this.isOwn = true,
  });

  factory Find.fromJson(Map<String, dynamic> json,
      {required String currentUserId}) {
    final authorId = json['author_id'] as String?;
    final author = json['author'] as Map<String, dynamic>?;
    return Find(
      id: json['id'] as String,
      spotId: json['spot_id'] as String,
      species: json['species'] as String?,
      count: json['count'] as int?,
      foundOn: DateTime.parse(json['found_on'] as String),
      note: json['note'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      authorId: authorId,
      authorUsername: author?['username'] as String?,
      authorAvatar: author?['avatar'] as int? ?? 0,
      isOwn: authorId == null || authorId == currentUserId,
    );
  }

  /// Kurzbeschreibung wie "Steinpilz, 5 Stück" für Listen.
  String get label {
    final parts = <String>[
      if (species != null && species!.isNotEmpty) species!,
      if (count != null) '$count Stück',
    ];
    return parts.isEmpty ? 'Fund' : parts.join(', ');
  }
}
