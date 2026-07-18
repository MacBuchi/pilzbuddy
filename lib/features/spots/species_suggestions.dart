/// Vorschläge für das Pilzart-Feld: eigene Arten zuerst, dann bekannte
/// Arten; case-insensitive Contains-Match, dedupliziert.
List<String> suggestSpecies(
  String query,
  List<String> own,
  List<String> builtin, {
  int limit = 6,
}) {
  final q = query.trim().toLowerCase();
  final result = <String>[];
  final seen = <String>{};

  void addMatches(Iterable<String> source) {
    for (final name in source) {
      if (result.length >= limit) return;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      if (q.isEmpty || key.contains(q)) {
        result.add(name);
        seen.add(key);
      }
    }
  }

  addMatches(own);
  addMatches(builtin);
  return result;
}

/// Leitet aus Funden (bereits nach „neueste zuerst" sortiert) die Liste der
/// eigenen Arten ab — zuletzt benutzt zuerst, case-insensitiv dedupliziert.
List<String> ownSpeciesFromSortedNames(Iterable<String?> speciesNewestFirst) {
  final result = <String>[];
  final seen = <String>{};
  for (final name in speciesNewestFirst) {
    if (name == null) continue;
    final trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    final key = trimmed.toLowerCase();
    if (seen.add(key)) result.add(trimmed);
  }
  return result;
}
