// Das Wetter an diesem Spot — Regensummen, der Verlauf der letzten
// 14 Tage und die Temperatur der nächsten Wetterstation.
//
// **Der eigentliche Grund, warum Gitter und Stationstabelle auf dem Gerät
// liegen.** Die Frage „wie war das Wetter an dieser Stelle" ist damit ein
// Feldzugriff: lokal, ohne Empfang, und ohne dass irgendjemand die
// Koordinate zu sehen bekommt. Eine Wetterabfrage je Spot wäre die
// Preisgabe der Fundstelle — der DWD beantwortet sie bereitwillig, und
// genau deshalb wird sie nicht gestellt.
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
import '../../map/spot_weather.dart';
import 'weather_chart.dart';

/// Die Fenster, die aus dem Stapel kommen. 30 Tage stehen daneben und
/// kommen aus dem W4-Gitter — dreißig Tagesraster wären 1,5 MB, und der
/// DWD rechnet diese Summe ohnehin selbst.
const _windows = [7, 14];

/// Die Stationszeile unter dem Diagramm — oder `null`, wenn keine
/// Station in Reichweite ist (Zeile weglassen statt Platzhalter).
///
/// Entfernung und Höhe stehen dabei, weil sie die Einordnung SIND: Die
/// Höhendifferenz ist der größte Fehlerbeitrag (~0,65 K je 100 m), und
/// herausrechnen lässt sie sich ohne Höhenmodell nicht.
String? stationLine(SpotTemperature? temperature) {
  if (temperature == null) return null;
  final air = temperature.air;
  final soil = temperature.soil;
  String describe(({WeatherStation station, double km}) pick) =>
      '${pick.station.name} (${pick.km.round()} km, '
      '${pick.station.height} m ü. NN';
  if (air != null && soil != null) {
    if (air.station.name == soil.station.name) {
      return 'Temperatur: Station ${describe(air)}).';
    }
    return 'Temperatur: ${describe(air)}, Luft) '
        'und ${describe(soil)}, Boden).';
  }
  if (air != null) return 'Lufttemperatur: Station ${describe(air)}).';
  if (soil != null) return 'Bodentemperatur: Station ${describe(soil)}).';
  return null;
}

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
    // `valueOrNull` mit Absicht: Die Temperatur soll das Blatt nie
    // aufhalten — kommt sie später oder gar nicht, stehen die Regenteile
    // längst da und die Linien fehlen eben.
    final temperature = ref.watch(spotTemperatureProvider(at)).valueOrNull;

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

        final peak = data.peak;
        final dry = data.daysSinceRain();
        final stations = stationLine(temperature);
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 24),
            Text('Wetter an diesem Spot',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            _SumTile(rows: [
              for (final row in rows)
                if (row.mm case final mm?) (label: row.label, mm: mm),
            ]),
            const SizedBox(height: 10),
            WeatherChart(course: data, temperature: temperature),
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 2),
            Text(
              // Woher, und bis wann. Beides gehört dazu: Das Tagesprodukt
              // endet gestern, nicht heute — und neben der Temperatur
              // steht, welches Instrument sie gemessen hat.
              'Tagessummen des Deutschen Wetterdienstes, bis '
              '${DateFormat('d.M.').format(data.newest!)} — nur '
              'Deutschland.${stations == null ? '' : ' $stations'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor, fontSize: 11),
            ),
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
/// Dieselbe Zusage wie bei der Regenebene seit 1.45.0: Stapel und
/// Stationstabelle kosten beim ersten Mal zusammen rund 1 MB, und das
/// gibt man im Wald nicht ungefragt aus. Danach ist es eine Datei am
/// Tag, und gefragt wird nicht mehr — EINE Zustimmung für das Wetter,
/// kein zweiter Dialog für die Temperatur.
class _Offer extends StatelessWidget {
  const _Offer({required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text('Wetter an diesem Spot',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 4),
        Text(
          'Wie viel Regen hier gefallen ist und wie warm es war — Tag '
          'für Tag. Beim ersten Mal wird rund 1 MB geladen, danach '
          'täglich ein kleines Stück.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAccept,
          icon: const Icon(Icons.water_drop_outlined, size: 18),
          label: const Text('Wetterdaten laden'),
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
            Text('Wetterdaten werden geladen …',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

/// Die Summen als Kachel im Stil der Auth-Mails (Betreiber-Vorschlag
/// 2026-08-05): Cream-Grund, runde Ecken, der Wert fett in Grün — er ist
/// die Aussage, die Beschriftung die Zugabe.
///
/// Grün über `colorScheme.primary`, nicht als rohes [AppColors.forestGreen]:
/// Das Theme ist daraus geseedet, und ein dunkles Thema bekäme sonst einen
/// zu dunklen Ton. Die Beschriftung dagegen fest [AppColors.barkBrown] —
/// die Kachel ist in jedem Thema hell, ein Theme-Grau wäre auf Cream
/// unlesbar (dasselbe Muster wie der Fußtext der Regen-Legende).
class _SumTile extends StatelessWidget {
  const _SumTile({required this.rows});

  final List<({String label, int mm})> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final row in rows)
            Expanded(
              child: Column(
                children: [
                  Text('${row.mm} mm',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      )),
                  const SizedBox(height: 2),
                  Text(row.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.barkBrown
                              .withValues(alpha: 0.7))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
