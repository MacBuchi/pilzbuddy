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

  /// Geraten statt gefunden: Die normale Suche hat NICHTS geliefert, und
  /// dieser Vorschlag stammt aus dem Tippfehler-Ausgleich („Bofist" →
  /// „Riesenbovist"). Die Oberfläche muss das kenntlich machen — ein
  /// geratener Treffer, der aussieht wie ein gefundener, ist eine
  /// Behauptung über die Eingabe des Nutzers.
  final bool isGuess;

  const SpeciesSuggestion(this.name,
      {required this.isOwn,
      this.group,
      this.matchedSynonym,
      this.isGuess = false});
}

/// Vorschläge für das Pilzart-Feld: eigene Arten zuerst, dann bekannte
/// Arten; Contains-Match über [foldSpeciesName], dedupliziert. Eigene Arten
/// bekommen ihre Gruppe per Lookup (sofern bekannt).
///
/// Zweitnamen werden mitgesucht, aber nicht angeboten: Ein Treffer auf
/// „Herrenpilz" ergibt den Vorschlag „Steinpilz" (mit [matchedSynonym]),
/// und die Deduplizierung läuft über die Hauptbezeichnung — sonst stünden
/// bei „stein" gleich drei Zeilen für denselben Pilz.
///
/// Findet der Vergleich gar nichts, übernimmt [_guesses] — siehe dort.
List<SpeciesSuggestion> suggestSpecies(
  String query,
  List<String> own,
  List<KnownSpecies> builtin, {
  int limit = 6,
}) {
  final q = foldSpeciesName(query);
  final result = <SpeciesSuggestion>[];
  final seen = <String>{};

  bool matches(String name) => q.isEmpty || foldSpeciesName(name).contains(q);

  for (final name in own) {
    if (result.length >= limit) return result;
    final canonical = canonicalSpecies(name) ?? name;
    final key = foldSpeciesName(canonical);
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
    final key = foldSpeciesName(canonical);
    if (seen.contains(key) || !matches(species.name)) continue;
    seen.add(key);
    result.add(SpeciesSuggestion(canonical,
        isOwn: false,
        group: groupFor(canonical) ?? species.group,
        matchedSynonym: _synonymHit(species.name, canonical)));
  }
  if (result.isEmpty) return _guesses(q, own, builtin, limit);
  return result;
}

/// Der getippte Name, falls er nicht die Hauptbezeichnung ist.
String? _synonymHit(String typed, String canonical) =>
    typed.toLowerCase() == canonical.toLowerCase() ? null : typed;

/// Der Tippfehler-Ausgleich: der beste Treffer, wenn es keinen gab.
///
/// Läuft **nur**, wenn die normale Suche leer ausging — er ist ein
/// Rückfall, keine zweite Meinung. Angeboten wird ausschließlich der
/// geringste gefundene Abstand: Wer „Steinpiltz" tippt, will die drei
/// Steinpilze sehen und nicht dahinter noch alles, was zufällig auch in
/// die Nähe passt.
List<SpeciesSuggestion> _guesses(
  String q,
  List<String> own,
  List<KnownSpecies> builtin,
  int limit,
) {
  final maxDistance = speciesTypoTolerance(q.length);
  if (maxDistance < 0) return const [];

  final best = <String, (int, SpeciesSuggestion)>{};
  void consider(String typed, {required bool isOwn, SpeciesGroup? group}) {
    final distance = nearContainsDistance(q, foldSpeciesName(typed));
    if (distance > maxDistance) return;
    final canonical = canonicalSpecies(typed) ?? typed;
    final key = foldSpeciesName(canonical);
    final existing = best[key];
    if (existing != null && existing.$1 <= distance) return;
    best[key] = (
      distance,
      SpeciesSuggestion(canonical,
          isOwn: isOwn,
          group: groupFor(canonical) ?? group,
          matchedSynonym: _synonymHit(typed, canonical),
          isGuess: true)
    );
  }

  for (final name in own) {
    consider(name, isOwn: true);
  }
  for (final species in builtin) {
    consider(species.name, isOwn: false, group: species.group);
  }
  if (best.isEmpty) return const [];

  final closest =
      best.values.map((e) => e.$1).reduce((a, b) => a < b ? a : b);
  return [
    for (final entry in best.values)
      if (entry.$1 == closest) entry.$2,
  ].take(limit).toList();
}

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
