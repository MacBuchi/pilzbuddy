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

import '../../../core/app_colors.dart';
import '../../../core/mushroom_species.dart';
import '../../../core/season_curves.dart';

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
          _Bars(months: entry.curve.months, currentMonth: month),
          const SizedBox(height: 8),
          Text(
            _sentence(entry.name, entry.curve),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 2),
        Text(
          // **Einmal unter allen Kurven.** Die Quelle gilt den Daten,
          // nicht der Art; unter jedem Diagramm wiederholt wäre sie
          // Lärm. Genommen wird die erste — bei mehreren Kurven ist der
          // Satz für alle derselbe.
          _source(curves.first.curve),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.hintColor, fontSize: 11),
        ),
      ],
    );
  }

  /// Der Satz über den Balken. Er nennt IMMER die Art — nie „die Pilze" —
  /// und bleibt beim Melden: „wird gemeldet", nicht „wächst".
  static String _sentence(String name, SeasonCurve curve) {
    // **Drei verschiedene Aussagen, drei verschiedene Sätze.**
    //
    // GEBORGT wiegt schwerer als ein Sammelbegriff und wird deshalb
    // zuerst geprüft: Bei „Rotkappe" umfasst der eingetragene NAME
    // mehrere Arten, die Kurve gehört also dem, was dasteht. Beim
    // Igelstachelbart meint der Name genau eine Art, und die Kurve
    // kommt von ihren Verwandten — wer das nicht liest, hält 1147
    // Meldungen über Stachelbärte für 1147 Meldungen über diesen Pilz.
    final borrowed = curve.borrowedFrom;
    final subject = borrowed != null
        ? '$name (Saison nach verwandten Arten: $borrowed)'
        : curve.isGenus
            // Ein Sammelbegriff ist keine Art. Wer „Rotkappe" einträgt,
            // meint je nach Wald eine andere — das gehört in den Satz,
            // sonst liest sich die Kurve genauer, als sie ist.
            ? '$name (mehrere ähnliche Arten)'
            : name;
    if (curve.isFlat) {
      return '$subject wird das ganze Jahr über etwa gleich häufig '
          'gemeldet — die Jahreszeit sagt hier wenig.';
    }
    final peak = curve.peakLabel;
    final run = curve.peakMonths;
    if (peak == null || run == null) return '';
    // „im April", aber „von August bis September" — mit einer einzigen
    // Präposition wird eines von beiden falsch.
    final preposition = run.length == 1 ? 'im' : 'von';
    return '$subject wird am häufigsten $preposition $peak gemeldet.';
  }

  /// Woher die Zahlen kommen und was sie NICHT sind.
  ///
  /// Der zweite Halbsatz ist der wichtige: Die Kurve ist gegen den
  /// allgemeinen Meldeeifer verrechnet (ohne das trüge jede Art denselben
  /// Herbstberg), sie ist also relativ zur Pilzsaison — und sie beschreibt
  /// Meldungen, nicht das Wetter dieses Jahres.
  static String _source(SeasonCurve curve) =>
      'Aus ${curve.observations} Beobachtungen in Deutschland, Österreich '
      'und der Schweiz (GBIF), verrechnet gegen den allgemeinen '
      'Meldeeifer. Das beschreibt frühere Jahre, nicht dieses.';
}

/// Zwölf Balken, einer je Monat, der laufende hervorgehoben.
///
/// Von Hand statt mit fl_chart: Es gibt keine Achse, keine Skala und
/// nichts zu skalieren — die Werte sind bereits auf 0…100 normiert. Ein
/// Diagrammpaket brächte hier Konfiguration statt Ersparnis.
class _Bars extends StatelessWidget {
  const _Bars({required this.months, required this.currentMonth});

  final List<int> months;
  final int currentMonth;

  static const _height = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < 12; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _height,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        // Ein Wert von 0 bekommt trotzdem eine dünne
                        // Linie: Die leere Spalte soll als „fast nie"
                        // lesbar sein und nicht als Lücke im Diagramm.
                        heightFactor: (months[index] / 100).clamp(0.04, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: index == currentMonth
                                ? AppColors.forestGreen
                                : AppColors.forestGreen.withValues(alpha: 0.35),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kMonthLetters[index],
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: index == currentMonth
                          ? AppColors.forestGreen
                          : theme.hintColor,
                      fontWeight: index == currentMonth
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
