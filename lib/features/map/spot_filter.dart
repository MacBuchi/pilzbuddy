import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mushroom_species.dart';
import '../../models/spot.dart';
import '../spots/spot_providers.dart';

/// Was die Karte gerade zeigt (Issue #154).
///
/// Bewusst nur für diese Sitzung: Ein vergessener Filter versteckt Spots,
/// und im Wald vor einer Fundstelle zu stehen, die die App nicht zeigt, ist
/// der teurere Fehler. Nach dem Start liegt wieder alles auf der Karte —
/// anders als beim Offline-Schalter (#145), der nichts verbirgt.
class SpotFilter {
  const SpotFilter({this.species = const {}, this.onlyMine = false});

  /// Nur Spots mit einem Fund einer dieser Arten. **Leer = alle Arten** —
  /// nicht „keine". Ein Filter, der nichts durchlässt, wäre auf der Karte
  /// nicht von „nichts gefunden" zu unterscheiden.
  final Set<String> species;

  /// Freundes-Spots ausblenden.
  final bool onlyMine;

  bool get isActive => species.isNotEmpty || onlyMine;

  SpotFilter copyWith({Set<String>? species, bool? onlyMine}) => SpotFilter(
        species: species ?? this.species,
        onlyMine: onlyMine ?? this.onlyMine,
      );
}

class SpotFilterNotifier extends Notifier<SpotFilter> {
  @override
  SpotFilter build() => const SpotFilter();

  /// Art an-/abwählen. Verglichen wird über die Hauptbezeichnung, damit
  /// dieselbe Art nicht zweimal in der Menge landen kann.
  void toggleSpecies(String species) {
    final key = canonicalSpecies(species) ?? species;
    final next = {...state.species};
    if (!next.remove(key)) next.add(key);
    state = state.copyWith(species: next);
  }

  /// „Alle Arten": hebt die Artenauswahl auf, lässt „Nur meine" stehen.
  void clearSpecies() => state = state.copyWith(species: const {});

  void setOnlyMine(bool value) => state = state.copyWith(onlyMine: value);

  void clear() => state = const SpotFilter();
}

final spotFilterProvider =
    NotifierProvider<SpotFilterNotifier, SpotFilter>(SpotFilterNotifier.new);

/// Passt der Spot zum Filter?
///
/// Die Art wird über **alle** Funde geprüft, nicht nur über den letzten:
/// Wer sehen will, wo er Pfifferlinge gefunden hat, meint jede Fundstelle
/// mit einem solchen Fund — auch die, an der zuletzt etwas anderes stand.
/// (Das Marker-Bild zeigt weiterhin den letzten Fund; die beiden Fragen
/// sind verschieden.)
/// Verglichen wird über die Hauptbezeichnung: Ein Spot, der vor der
/// Vereinheitlichung als „Totentrompete" angelegt wurde, gehört zur
/// „Herbsttrompete" — sonst wäre er unauffindbar, obwohl er dieselbe Art
/// meint.
/// Mehrere Arten wirken als ODER: gezeigt wird, was zu **einer** von ihnen
/// passt. Ein UND wäre eine andere Frage („wo habe ich beides gefunden") und
/// bei zwei Arten meist die leere Karte.
bool matchesSpotFilter(Spot spot, SpotFilter filter) {
  if (filter.onlyMine && !spot.isOwn) return false;
  if (filter.species.isEmpty) return true;
  final wanted = {
    for (final s in filter.species) canonicalSpecies(s)?.toLowerCase(),
  };
  return spot.finds
      .any((f) => wanted.contains(canonicalSpecies(f.species)?.toLowerCase()));
}

List<Spot> applySpotFilter(List<Spot> spots, SpotFilter filter) =>
    [for (final spot in spots) if (matchesSpotFilter(spot, filter)) spot];

/// Eine Art mit der Zahl der Spots, an denen sie vorkommt.
typedef SpeciesTally = ({String name, int spots});

/// Arten der übergebenen Spots, häufigste zuerst, bei Gleichstand
/// alphabetisch. Ein Spot zählt je Art nur einmal, egal wie oft dort
/// gefunden wurde — gezählt werden Fundstellen, nicht Funde.
///
/// Zusammengefasst wird über die Hauptbezeichnung, damit ältere Funde unter
/// einem Zweitnamen nicht als eigene Art danebenstehen. Eigene Arten der
/// Nutzer bleiben, wie sie getippt wurden; bei mehreren Schreibweisen
/// gewinnt die erste.
List<SpeciesTally> speciesTally(List<Spot> spots) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final spot in spots) {
    final seen = <String>{};
    for (final find in spot.finds) {
      final name = canonicalSpecies(find.species);
      if (name == null) continue;
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      labels[key] ??= name;
    }
  }
  final tally = [
    for (final entry in counts.entries)
      (name: labels[entry.key]!, spots: entry.value),
  ];
  tally.sort((a, b) {
    final byCount = b.spots.compareTo(a.spots);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });
  return tally;
}

/// Die Spots, die die Karte zeichnet — nach Herkunft getrennt, weil sie in
/// verschiedenen Ebenen liegen.
final visibleSpotsProvider =
    Provider<({List<Spot> mine, List<Spot> friends})>((ref) {
  final filter = ref.watch(spotFilterProvider);
  final mine = ref.watch(mySpotListProvider);
  final friends =
      ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[];
  return (
    mine: applySpotFilter(mine, filter),
    friends: applySpotFilter(friends, filter),
  );
});

/// Auswahlliste des Filter-Blatts.
///
/// Zählt über die Spots, die der *übrige* Filter zulässt: Steht „Nur meine
/// Spots", passen die Zahlen zu dem, was die Karte danach zeigt. Die eigene
/// Artenwahl fließt nicht ein — sonst bliebe nur noch die gewählte Art
/// übrig und es gäbe keinen Weg zu einer anderen.
final filterSpeciesProvider = Provider<List<SpeciesTally>>((ref) {
  final onlyMine = ref.watch(spotFilterProvider).onlyMine;
  final mine = ref.watch(mySpotListProvider);
  final friends =
      ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[];
  return speciesTally([...mine, if (!onlyMine) ...friends]);
});
