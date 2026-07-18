class Find {
  final String id;
  final String spotId;
  final String? species;
  final int? count;
  final DateTime foundOn;
  final String? note;

  const Find({
    required this.id,
    required this.spotId,
    this.species,
    this.count,
    required this.foundOn,
    this.note,
  });

  factory Find.fromJson(Map<String, dynamic> json) => Find(
        id: json['id'] as String,
        spotId: json['spot_id'] as String,
        species: json['species'] as String?,
        count: json['count'] as int?,
        foundOn: DateTime.parse(json['found_on'] as String),
        note: json['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'spot_id': spotId,
        'species': species,
        'count': count,
        'found_on':
            '${foundOn.year.toString().padLeft(4, '0')}-${foundOn.month.toString().padLeft(2, '0')}-${foundOn.day.toString().padLeft(2, '0')}',
        'note': note,
      };

  /// Kurzbeschreibung wie "Steinpilz, 5 Stück" für Listen.
  String get label {
    final parts = <String>[
      if (species != null && species!.isNotEmpty) species!,
      if (count != null) '$count Stück',
    ];
    return parts.isEmpty ? 'Fund' : parts.join(', ');
  }
}
