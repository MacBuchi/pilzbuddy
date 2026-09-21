// Wann diese Art gemeldet wird — der Jahresgang aus GBIF-Funddaten.
//
// **Fakten, kein Urteil**, dieselbe Grenze wie beim Regenabschnitt
// darunter: Hier stehen Beobachtungen aus zwei Jahrzehnten, keine
// Vorhersage für dieses Wochenende. Der Text muss das sagen, nicht das
// Kleingedruckte — die Lehre aus den recherchierten Diensten
// (docs/pilzampel-konzept.md, „Ehrlichkeit im UI").
//
// Deshalb steht hier auch nirgends ein Prozentzeichen und keine Wertung.
// Die Balken sind ein relativer Jahresgang; ihre Höhe heißt „in diesem
// Monat wird die Art häufiger gemeldet als in jenem", sonst nichts.
//
// Kein Ladezustand, kein Fehlerfall: Die Zahlen liegen im Binary
// (`season_curves.g.dart`). Fehlt eine Kurve, fällt der Abschnitt ganz
// weg — wie `stationLine` es vormacht, statt einen Platzhalter zu zeigen.
import 'package:flutter/material.dart';

import '../../../core/mushroom_species.dart';
import '../../../core/season_curves.dart';
import '../../../core/widgets/season_bars.dart';

class SpeciesSeasonSection extends StatelessWidget {
  const SpeciesSeasonSection({super.key, required this.species, this.today});

  /// Die Arten des Spots, jüngster Fund zuerst — dieselbe Liste, mit der
  /// auch die Ampel darüber rechnet (`scanSpeciesOf`).
  ///
  /// **Eine LISTE seit 1.140.0** (Betreiber, 2026-09-12: „Braucht es
  /// mehrere Saisonkurven, wenn mehrere Pilzarten an der gleichen
  /// Fundstelle eingetragen sind?"). Bis dahin stand hier die Art des
  /// LETZTEN Funds, während die Ampel darüber seit 1.138.0 schon eine
  /// Zeile je Art zeigte — an einer Stelle mit Pfifferlingen und
  /// Steinpilzen sagte das Blatt also zweimal etwas über zwei Pilze und
  /// einmal über einen.
  final List<String?> species;

  /// Nur für Tests: Ohne Angabe zählt der heutige Monat.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    // Jede Art einmal, in der Reihenfolge der Liste, und nur die mit
    // einer belastbaren Kurve.
    final seen = <String>{};
    final curves = <({String name, SeasonCurve curve})>[];
    for (final entry in species) {
      final curve = seasonCurveFor(entry);
      if (curve == null) continue;
      final name = canonicalSpecies(entry)!;
      if (!seen.add(name)) continue;
      curves.add((name: name, curve: curve));
    }
    if (curves.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final month = (today ?? DateTime.now()).month - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(
            curves.length == 1
                ? 'Wann diese Art gemeldet wird'
                : 'Wann diese Arten gemeldet werden',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary)),
        for (final entry in curves) ...[
          const SizedBox(height: 8),
          SeasonBars(months: entry.curve.months, currentMonth: month),
          const SizedBox(height: 8),
          Text(
            seasonSentence(entry.name, entry.curve),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 2),
        Text(
          // **Einmal unter allen Kurven.** Die Quelle gilt den Daten,
          // nicht der Art; unter jedem Diagramm wiederholt wäre sie
          // Lärm. Genommen wird die erste — bei mehreren Kurven ist der
          // Satz für alle derselbe.
          seasonSourceLine(curves.first.curve),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.hintColor, fontSize: 11),
        ),
      ],
    );
  }
}
