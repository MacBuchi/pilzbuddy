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

  /// „Nichts gefunden" (Patch 015, Issue #211): ein Besuch ohne Fund. Trägt
  /// weder Art noch Anzahl — die Aussage gilt dem Ort. Solche Einträge
  /// zählen NIRGENDS als Fund; wer über Funde auswertet, nimmt die Zugänge
  /// aus [Spot], die sie schon aussieben.
  final bool blank;

  /// Wartet dieser Eintrag noch auf die Übertragung (#267)? Dann kommt er
  /// aus dem Ausgangskorb auf dem Gerät und hat noch keine Server-id —
  /// [id] trägt die vom Gerät vergebene Kennung. Er zählt überall mit
  /// (er ist passiert), nur ändern und löschen geht nicht: Dafür gibt es
  /// nichts, was der Server kennt.
  final bool pending;

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
    this.blank = false,
    this.pending = false,
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
      // Fehlt die Spalte, ist die Zeile älter als Patch 015 — und älter
      // als „nichts gefunden" heißt: ein echter Fund.
      blank: json['blank'] as bool? ?? false,
    );
  }

  /// Kurzbeschreibung wie "Steinpilz, 5 Stück" für Listen.
  String get label {
    if (blank) return 'Nichts gefunden';
    final parts = <String>[
      if (species != null && species!.isNotEmpty) species!,
      if (count != null) '$count Stück',
    ];
    return parts.isEmpty ? 'Fund' : parts.join(', ');
  }
}
