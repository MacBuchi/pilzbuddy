import '../../core/mushroom_species.dart';

/// Ein Vorschlag für das Pilzart-Feld.
class SpeciesSuggestion {
  final String name;
  final bool isOwn;
  final SpeciesGroup? group;

  const SpeciesSuggestion(this.name, {required this.isOwn, this.group});
}

/// Vorschläge für das Pilzart-Feld: eigene Arten zuerst, dann bekannte
/// Arten; case-insensitive Contains-Match, dedupliziert. Eigene Arten
/// bekommen ihre Gruppe per Lookup (sofern bekannt).
List<SpeciesSuggestion> suggestSpecies(
  String query,
  List<String> own,
  List<KnownSpecies> builtin, {
  int limit = 6,
}) {
  final q = query.trim().toLowerCase();
  final result = <SpeciesSuggestion>[];
  final seen = <String>{};

  bool matches(String name) => q.isEmpty || name.toLowerCase().contains(q);

  for (final name in own) {
    if (result.length >= limit) return result;
    final key = name.toLowerCase();
    if (seen.contains(key) || !matches(name)) continue;
    seen.add(key);
    result.add(SpeciesSuggestion(name, isOwn: true, group: groupFor(name)));
  }
  for (final species in builtin) {
    if (result.length >= limit) return result;
    final key = species.name.toLowerCase();
    if (seen.contains(key) || !matches(species.name)) continue;
    seen.add(key);
    result.add(
        SpeciesSuggestion(species.name, isOwn: false, group: species.group));
  }
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
