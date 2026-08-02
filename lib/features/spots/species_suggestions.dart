import '../../core/mushroom_species.dart';

/// Ein Vorschlag für das Pilzart-Feld. [name] ist immer die
/// Hauptbezeichnung — das ist auch, was gespeichert wird.
class SpeciesSuggestion {
  final String name;
  final bool isOwn;
  final SpeciesGroup? group;

  /// Der Zweitname, über den dieser Vorschlag gefunden wurde. Wer
  /// „Totentrompete" tippt und „Herbsttrompete" angeboten bekommt, muss
  /// sehen, warum — sonst sieht es aus, als hätte die App die Eingabe
  /// verschluckt.
  final String? matchedSynonym;

  const SpeciesSuggestion(this.name,
      {required this.isOwn, this.group, this.matchedSynonym});
}

/// Vorschläge für das Pilzart-Feld: eigene Arten zuerst, dann bekannte
/// Arten; case-insensitive Contains-Match, dedupliziert. Eigene Arten
/// bekommen ihre Gruppe per Lookup (sofern bekannt).
///
/// Zweitnamen werden mitgesucht, aber nicht angeboten: Ein Treffer auf
/// „Herrenpilz" ergibt den Vorschlag „Steinpilz" (mit [matchedSynonym]),
/// und die Deduplizierung läuft über die Hauptbezeichnung — sonst stünden
/// bei „stein" gleich drei Zeilen für denselben Pilz.
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
    final canonical = canonicalSpecies(name) ?? name;
    final key = canonical.toLowerCase();
    if (seen.contains(key) || !matches(name)) continue;
    seen.add(key);
    result.add(SpeciesSuggestion(canonical,
        isOwn: true,
        group: groupFor(canonical),
        matchedSynonym: _synonymHit(name, canonical)));
  }
  for (final species in builtin) {
    if (result.length >= limit) return result;
    final canonical = species.sameAs ?? species.name;
    final key = canonical.toLowerCase();
    if (seen.contains(key) || !matches(species.name)) continue;
    seen.add(key);
    result.add(SpeciesSuggestion(canonical,
        isOwn: false,
        group: groupFor(canonical) ?? species.group,
        matchedSynonym: _synonymHit(species.name, canonical)));
  }
  return result;
}

/// Der getippte Name, falls er nicht die Hauptbezeichnung ist.
String? _synonymHit(String typed, String canonical) =>
    typed.toLowerCase() == canonical.toLowerCase() ? null : typed;

/// Leitet aus Funden (bereits nach „neueste zuerst" sortiert) die Liste der
/// eigenen Arten ab — zuletzt benutzt zuerst, case-insensitiv dedupliziert.
/// Zweitnamen aus älteren Funden werden dabei auf die Hauptbezeichnung
/// gebracht, damit dieselbe Art nicht zweimal vorgeschlagen wird.
List<String> ownSpeciesFromSortedNames(Iterable<String?> speciesNewestFirst) {
  final result = <String>[];
  final seen = <String>{};
  for (final name in speciesNewestFirst) {
    final canonical = canonicalSpecies(name);
    if (canonical == null) continue;
    if (seen.add(canonical.toLowerCase())) result.add(canonical);
  }
  return result;
}
