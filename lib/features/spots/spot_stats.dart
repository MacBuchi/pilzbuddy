// Die Zahlen hinter dem Reiter „Statistik" (#509) — ohne Widgets, damit
// sie prüfbar sind.
//
// **Gezählt werden nur EIGENE Funde.** Seit #190 können Buddies an
// geteilten Spots eintragen, und deren Funde sind nicht meine Statistik.
// Die Liste nebenan zeigt sie trotzdem — sie beschreibt den Ort, nicht
// meine Ausbeute. Wer hier eine Funktion ergänzt, füttert sie aus
// `Spot.ownFinds` (Funde) oder `Spot.ownEntries` (Besuche), nie aus
// `spot.finds`.
//
// Bis 1.160.0 stand das alles im Profil (`profile_screen.dart`).
import '../../core/mushroom_species.dart';
import '../../models/find.dart';
import '../../models/spot.dart';

/// Häufigste Arten über alle Funde, mit Stückzahl — anders als
/// `speciesTally` (Karte) zählt das die Funde selbst, nicht die Spots.
///
/// Zusammengefasst wird über die Hauptbezeichnung. Bis 1.37.0 steckte das im
/// Widget und gruppierte über den rohen String: „steinpilz" und „Steinpilz"
/// standen getrennt untereinander, Zweitnamen sowieso.
List<({String name, int count})> topSpecies(List<Find> finds) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final f in finds) {
    final name = canonicalSpecies(f.species);
    if (name == null) continue;
    final key = name.toLowerCase();
    counts[key] = (counts[key] ?? 0) + (f.count ?? 1);
    labels[key] ??= name;
  }
  final top = [
    for (final e in counts.entries) (name: labels[e.key]!, count: e.value),
  ];
  top.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });
  return top;
}

/// Funde je Kalenderjahr, aufsteigend.
List<({int year, int count})> findsPerYear(List<Find> finds) {
  final byYear = <int, int>{};
  for (final f in finds) {
    byYear[f.foundOn.year] = (byYear[f.foundOn.year] ?? 0) + 1;
  }
  final years = byYear.keys.toList()..sort();
  return [for (final year in years) (year: year, count: byYear[year]!)];
}

/// Eigene Funde je Monat über ALLE Jahre, Index 0 = Januar.
///
/// **Ersetzt seit 1.160.0 die vier Jahreszeiten-Balken.** Zwölf Monate
/// sind nicht nur feiner: Sie stehen in derselben Form wie die
/// gemeldete Saison im Reiter „Pilze" (`SeasonBars`), und damit lässt
/// sich das eigene Jahr gegen das gemeldete legen. Vier Jahreszeiten
/// konnten das nicht — der Herbstbalken war immer der längste.
List<int> findsPerMonth(List<Find> finds) {
  final counts = List<int>.filled(12, 0);
  for (final f in finds) {
    counts[f.foundOn.month - 1]++;
  }
  return counts;
}

/// Rechnet Monatszahlen auf die 0…100-Skala, die `SeasonBars` erwartet.
/// Ohne einen einzigen Fund bleibt alles null.
List<int> scaledToHundred(List<int> counts) {
  final peak = counts.fold(0, (a, b) => a > b ? a : b);
  if (peak == 0) return List<int>.filled(counts.length, 0);
  return [for (final c in counts) (c * 100 / peak).round()];
}

/// Das laufende Jahr gegen das vorige — beide nur bis zum heutigen Tag.
///
/// **Bis zum selben Tag, nicht ganze Jahre.** Im September gegen ein
/// volles Vorjahr zu vergleichen hieße, gegen zwei zusätzliche
/// Herbstmonate anzutreten; der Rückstand wäre garantiert und die Zahl
/// wertlos. [today] kommt von außen, damit ein Test im Dezember nicht
/// anders ausgeht als im September.
({int year, int finds, int species, int lastFinds, int lastSpecies})
    seasonToDate(List<Find> finds, DateTime today) {
  var thisYear = 0;
  var lastYear = 0;
  final thisSpecies = <String>{};
  final lastSpecies = <String>{};
  for (final f in finds) {
    if (!_untilDayOfYear(f.foundOn, today)) continue;
    final name = canonicalSpecies(f.species)?.toLowerCase();
    if (f.foundOn.year == today.year) {
      thisYear++;
      if (name != null) thisSpecies.add(name);
    } else if (f.foundOn.year == today.year - 1) {
      lastYear++;
      if (name != null) lastSpecies.add(name);
    }
  }
  return (
    year: today.year,
    finds: thisYear,
    species: thisSpecies.length,
    lastFinds: lastYear,
    lastSpecies: lastSpecies.length,
  );
}

/// Liegt [date] im Jahresverlauf vor oder auf dem Tag von [today]?
/// Verglichen über Monat und Tag, damit Schaltjahre nichts verschieben.
bool _untilDayOfYear(DateTime date, DateTime today) =>
    date.month < today.month ||
    (date.month == today.month && date.day <= today.day);

/// Wie viele der eigenen Besuche leer ausgingen (#211).
///
/// Ein Besuch ist ein eigener EINTRAG — Fund oder Leergang. Die Zahl
/// sagt damit nur etwas über die Besuche, die auch eingetragen wurden;
/// die Ampel-Validierung (#199) lebt von genau dieser Buchführung.
({int visits, int blanks}) blankShare(List<Spot> spots) {
  var visits = 0;
  var blanks = 0;
  for (final spot in spots) {
    for (final entry in spot.ownEntries) {
      visits++;
      if (entry.blank) blanks++;
    }
  }
  return (visits: visits, blanks: blanks);
}
