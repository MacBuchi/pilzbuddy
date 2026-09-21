// Der Reiter „Statistik" (#509) — bis 1.160.0 der untere Teil des
// Profils.
//
// **Umgezogen, nicht verdoppelt.** Zwei Orte mit derselben Aussage
// laufen auseinander; das Profil ist für das Konto da, nicht für die
// Auswertung. Gerechnet wird in `spot_stats.dart`, hier steht nur die
// Anzeige.
//
// **Gezählt werden nur EIGENE Funde** (`ownFinds`). Die Liste nebenan
// zeigt die Buddy-Einträge, weil sie den ORT beschreibt; eine
// Statistik, die fremde Funde mitzählt, behauptete fremde Ausbeute als
// eigene.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/axis_scale.dart';
import '../../../core/season_curves.dart' show kMonthNames;
import '../../../core/widgets/mushroom_icon.dart';
import '../../../core/widgets/season_bars.dart';
import '../../../models/find.dart';
import '../../../models/spot.dart';
import '../spot_providers.dart';
import '../spot_stats.dart';

class SpotStatsView extends ConsumerWidget {
  const SpotStatsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spots = ref.watch(mySpotListProvider);
    final today = ref.watch(todayProvider);
    final finds = [for (final s in spots) ...s.ownFinds];
    final revisited = spots.where((s) => s.ownFinds.length > 1).length;

    if (finds.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine eigenen Funde — sobald du einen einträgst, '
            'steht hier dein Jahr. 🍄',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _StatTile(label: 'Spots', value: spots.length.toString()),
            const SizedBox(width: 12),
            _StatTile(label: 'Funde', value: finds.length.toString()),
            const SizedBox(width: 12),
            _StatTile(
                label: 'Mehrfach\nbesucht', value: revisited.toString()),
          ],
        ),
        const SizedBox(height: 20),
        _SeasonToDate(finds: finds, today: today),
        const SizedBox(height: 20),
        _FindsPerYearChart(finds: finds),
        const SizedBox(height: 20),
        _MonthlyFinds(finds: finds, today: today),
        const SizedBox(height: 20),
        _TopSpecies(finds: finds),
        const SizedBox(height: 20),
        _BlankShare(spots: spots),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Das laufende Jahr gegen das vorige, beide bis zum heutigen Tag.
class _SeasonToDate extends StatelessWidget {
  const _SeasonToDate({required this.finds, required this.today});

  final List<Find> finds;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final season = seasonToDate(finds, today);
    final artWord = season.species == 1 ? 'Art' : 'Arten';
    // Ohne Vorjahr KEIN erfundener Vergleich: „0 im Vorjahr" läse sich
    // wie ein schlechtes Vorjahr, dabei gab es die App da noch nicht.
    final compare = season.lastFinds == 0
        ? 'Im Vorjahr steht für diesen Zeitraum nichts.'
        : 'Im Vorjahr waren es bis zum selben Tag ${season.lastFinds}.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saison ${season.year}',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${season.finds} Funde, ${season.species} $artWord',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(compare,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}

class _FindsPerYearChart extends StatelessWidget {
  const _FindsPerYearChart({required this.finds});

  final List<Find> finds;

  @override
  Widget build(BuildContext context) {
    final years = findsPerYear(finds);
    final maxCount =
        years.map((y) => y.count).reduce((a, b) => a > b ? a : b).toDouble();
    final barColor = Theme.of(context).colorScheme.primary;
    final maxY = maxCount * 1.2;
    final step = yAxisStep(maxY);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Funde pro Jahr',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  barGroups: [
                    for (final year in years)
                      BarChartGroupData(x: year.year, barRods: [
                        BarChartRodData(
                          toY: year.count.toDouble(),
                          color: barColor,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ]),
                  ],
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: step,
                        getTitlesWidget: (value, meta) =>
                            showsYAxisLabel(value, step)
                                ? Text(value.toInt().toString(),
                                    style:
                                        Theme.of(context).textTheme.bodySmall)
                                : const SizedBox.shrink(),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(value.toInt().toString(),
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                    ),
                  ),
                  // Ohne festes Intervall zieht fl_chart die Linien in einem
                  // eigenen Raster — sie lägen dann neben den Beschriftungen.
                  gridData: FlGridData(
                      drawVerticalLine: false, horizontalInterval: step),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zwölf Balken: die eigenen Funde über alle Jahre, Monat für Monat.
///
/// **Bewusst dasselbe Widget wie die Saisonkurve im Reiter „Pilze".**
/// Wer wissen will, ob er zu früh losgeht, legt seinen Jahresgang neben
/// den gemeldeten — das geht nur, wenn beide gleich aussehen. Die vier
/// Jahreszeitenbalken davor konnten es nicht: Der Herbstbalken war immer
/// der längste, und mehr stand nie drin.
class _MonthlyFinds extends StatelessWidget {
  const _MonthlyFinds({required this.finds, required this.today});

  final List<Find> finds;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = findsPerMonth(finds);
    final peak = counts.reduce((a, b) => a > b ? a : b);
    final best = counts.indexOf(peak);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mein Jahresgang', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SeasonBars(
              months: scaledToHundred(counts),
              currentMonth: today.month - 1,
            ),
            const SizedBox(height: 8),
            Text(
                'Stärkster Monat: ${kMonthNames[best]} mit $peak '
                '${peak == 1 ? 'Fund' : 'Funden'}.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}

class _TopSpecies extends StatelessWidget {
  const _TopSpecies({required this.finds});

  final List<Find> finds;

  @override
  Widget build(BuildContext context) {
    final top = topSpecies(finds);
    if (top.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top-Arten', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in top.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    MushroomIcon.forSpecies(entry.name, size: 24),
                    const SizedBox(width: 6),
                    Expanded(child: Text(entry.name)),
                    Text('${entry.count}×',
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wie viele der eingetragenen Besuche leer ausgingen (#211).
///
/// Steht bewusst als Satz und nicht als Diagramm da: Es ist EINE Zahl,
/// und sie sagt etwas über die Buchführung, nicht über den Wald. Wer
/// keine Leergänge einträgt, sieht hier nichts — eine Quote von 0 %
/// behauptete sonst, es sei nie etwas umsonst gewesen.
class _BlankShare extends StatelessWidget {
  const _BlankShare({required this.spots});

  final List<Spot> spots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = blankShare(spots);
    if (share.blanks == 0) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Besuche', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
                'An ${share.blanks} von ${share.visits} eingetragenen '
                'Besuchen war nichts da.',
                style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
