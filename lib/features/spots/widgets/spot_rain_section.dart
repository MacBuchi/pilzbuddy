// Der Regen an diesem Spot — Summen und der Verlauf der letzten 14 Tage.
//
// **Der eigentliche Grund, warum das Wertegitter auf dem Gerät liegt.**
// Die Frage „wie viel Regen an dieser Stelle" ist damit ein Feldzugriff:
// lokal, ohne Empfang, und ohne dass irgendjemand die Koordinate zu sehen
// bekommt. Eine Wetterabfrage je Spot wäre die Preisgabe der Fundstelle —
// der DWD beantwortet sie bereitwillig, und genau deshalb wird sie nicht
// gestellt.
//
// **Fakten, kein Urteil.** Hier stehen Messwerte und sonst nichts. Eine
// bewertende Ampel kommt erst, wenn die Rückwärtsprüfung an echten Funden
// zeigt, dass sie etwas taugt (Betreiberentscheidung 2026-08-03).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/app_colors.dart';
import '../../../core/settings.dart';
import '../../map/rain_data_providers.dart';
import '../../map/rain_stack.dart';

/// Die Fenster, die aus dem Stapel kommen. 30 Tage stehen daneben und
/// kommen aus dem W4-Gitter — dreißig Tagesraster wären 1,5 MB, und der
/// DWD rechnet diese Summe ohnehin selbst.
const _windows = [7, 14];

class SpotRainSection extends ConsumerWidget {
  const SpotRainSection({super.key, required this.lat, required this.lon});

  final double lat;
  final double lon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(rainCourseEnabledProvider);
    if (!enabled) return _Offer(onAccept: () => _accept(ref));

    final at = (lat: lat, lon: lon);
    final course = ref.watch(rainCourseProvider(at));
    final month = ref.watch(rainMonthAtProvider(at)).valueOrNull;

    return course.when(
      loading: () => const _Loading(),
      // Still: Ohne Empfang gibt es keinen Verlauf, und das ist im Wald
      // ein normaler Vorgang. Eine Fehlermeldung über etwas, das man
      // nicht angefordert hat, ist eine Störung.
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data == null || data.isEmpty) return const SizedBox.shrink();
        final rows = <({String label, int? mm})>[
          for (final window in _windows)
            (label: '$window Tage', mm: data.sumOfLast(window)),
          (label: '30 Tage', mm: month),
        ];
        // Kein einziger Wert heißt: Der Spot liegt außerhalb der Messung.
        // Dann fällt der ganze Abschnitt weg — eine Zeile „keine Daten"
        // bei jedem österreichischen Spot wäre Lärm.
        if (rows.every((row) => row.mm == null)) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 24),
            Text('Regen an diesem Spot',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final row in rows)
              if (row.mm case final mm?) _SumRow(label: row.label, mm: mm),
            const SizedBox(height: 10),
            _Course(course: data),
          ],
        );
      },
    );
  }

  Future<void> _accept(WidgetRef ref) async {
    ref.read(rainCourseEnabledProvider.notifier).state = true;
    await ref.read(settingsProvider).setRainCourseEnabled(true);
  }
}

/// Die Frage vor dem ersten Laden.
///
/// Dieselbe Zusage wie bei der Regenebene seit 1.45.0: Der Stapel kostet
/// beim ersten Mal rund 0,9 MB, und das gibt man im Wald nicht ungefragt
/// aus. Danach ist es eine Datei am Tag, und gefragt wird nicht mehr.
class _Offer extends StatelessWidget {
  const _Offer({required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text('Regen an diesem Spot',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Wie viel Regen hier gefallen ist und wann — Tag für Tag. '
          'Beim ersten Mal werden rund 0,9 MB geladen, danach täglich '
          'ein kleines Stück.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAccept,
          icon: const Icon(Icons.water_drop_outlined, size: 18),
          label: const Text('Regendaten laden'),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('Regendaten werden geladen …',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow({required this.label, required this.mm});

  final String label;
  final int mm;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: style)),
          Text('$mm mm',
              style: style?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Die Balken: ein Tag je Balken, ältester links.
///
/// Von Hand statt mit einem Diagramm-Paket — es sind vierzehn Rechtecke,
/// und das Projekt hat für die Jahresstatistik dieselbe Entscheidung
/// schon einmal getroffen.
class _Course extends StatelessWidget {
  const _Course({required this.course});

  final RainCourse course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = course.peak;
    final dry = course.daysSinceRain();
    final weekday = DateFormat('E', 'de');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 54,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in course.days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Ein trockener Tag bekommt einen Stummel statt
                        // gar nichts: Eine Lücke sähe aus wie ein
                        // fehlender Tag, und das ist etwas anderes.
                        Container(
                          height: peak == 0 || day.mm == null
                              ? 2
                              : 2 + 36 * day.mm! / peak,
                          decoration: BoxDecoration(
                            color: day.mm == null
                                ? theme.hintColor.withValues(alpha: 0.25)
                                : AppColors.friendBlue.withValues(
                                    alpha: day.mm == 0 ? 0.3 : 0.85),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(weekday.format(day.date).substring(0, 2),
                            style: theme.textTheme.labelSmall
                                ?.copyWith(fontSize: 9)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          // Der Satz, den eine Summe nicht sagen kann.
          switch (dry) {
            null => 'In diesen 14 Tagen kein nennenswerter Regen. '
                'Höchster Tageswert: $peak mm.',
            0 => 'Zuletzt gestern nennenswert geregnet '
                '(höchster Tageswert: $peak mm).',
            final days => 'Letzter nennenswerter Regen vor $days '
                '${days == 1 ? 'Tag' : 'Tagen'} '
                '(höchster Tageswert: $peak mm).',
          },
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 2),
        Text(
          // Woher, und bis wann. Beides gehört dazu: Das Tagesprodukt
          // endet gestern, nicht heute.
          'Tagessummen des Deutschen Wetterdienstes, bis '
          '${DateFormat('d.M.').format(course.newest!)} — nur Deutschland.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.hintColor, fontSize: 11),
        ),
      ],
    );
  }
}
