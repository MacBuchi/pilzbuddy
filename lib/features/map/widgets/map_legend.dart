// Die Legende auf der Karte — für ALLE aktiven Ebenen (#231).
//
// **Warum sie sein muss:** Seit 1.46.0 zeichnet die App die Summen in
// eigenen Farben. Ohne Legende bedeutet ein grüner Fleck genau nichts —
// der Betreiber hat es am 2026-08-04 als Erstes bemängelt, und er hatte
// recht: Im Ebenen-Blatt steht die Erklärung zwar, aber wer die Karte
// ansieht, hat das Blatt zu. Mit der Waldebene (#213) galt dasselbe
// gleich noch einmal — seither ist die Karte hier EINE Karte für beide
// Ebenen statt zweier Kärtchen, die sich um die Ecke drängeln.
//
// **Warum sie klein bleibt:** Die Karte ist der Inhalt. Deshalb links
// UNTEN (dort ist der einzige freie Rand; rechts stehen die Knöpfe, oben
// die Banner), nur bei aktiver Ebene, und ohne Beschriftung jeder
// einzelnen Stufe. Das X schaltet die persistente Einstellung
// [Settings.mapLegendEnabled] aus; wieder an geht sie im Ebenen-Blatt
// („Legende in Karte anzeigen").
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/errors.dart';
import '../../../core/settings.dart';
import '../forest_data_providers.dart';
import '../forest_grid.dart';
import '../rain_data_providers.dart';
import '../rain_fill.dart';
import '../rain_layer.dart';

/// Muster wie `MapLongPressEnabledNotifier`: Zustand springt sofort,
/// Speichern läuft nach, ein Fehler beim Merken wird nur protokolliert —
/// die Karte darf an einer Einstellung nie scheitern.
class MapLegendEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).mapLegendEnabled;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setMapLegendEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Karten-Legende merken', e, stackTrace);
    }));
  }
}

final mapLegendEnabledProvider =
    NotifierProvider<MapLegendEnabledNotifier, bool>(
        MapLegendEnabledNotifier.new);

class MapLegend extends ConsumerWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(mapLegendEnabledProvider)) return const SizedBox.shrink();

    final rainLayer = ref.watch(rainLayerProvider);
    // Regen-Sektion nur zu den eigenen Farben — beim Radar und im
    // Rückfall liegt das DWD-Bild in DWD-Farben auf der Karte, dafür
    // wäre diese Skala schlicht falsch; die richtige steht im Blatt.
    final showRain = rainLayer != RainLayer.off &&
        ref.watch(rainPaintProvider(rainLayer)) != RainPaint.dwd;
    final forestClasses = ref.watch(forestClassesProvider);
    final showForest = ref.watch(forestLayerEnabledProvider) &&
        forestClasses.isNotEmpty &&
        ref.watch(forestGridProvider).valueOrNull != null;
    if (!showRain && !showForest) return const SizedBox.shrink();

    return Padding(
      // Über dem Maßstab, der unten links sitzt.
      padding: const EdgeInsets.only(left: 12, bottom: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cream.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showRain) _RainSection(layer: rainLayer),
                  if (showRain && showForest) const SizedBox(height: 6),
                  if (showForest) _ForestSection(classes: forestClasses),
                ],
              ),
              // Das X merkt sich die Entscheidung (persistent); zurück
              // geht es über den Schalter im Ebenen-Blatt.
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  tooltip: 'Legende ausblenden',
                  icon: const Icon(Icons.close, color: AppColors.barkBrown),
                  onPressed: () =>
                      ref.read(mapLegendEnabledProvider.notifier).set(false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RainSection extends ConsumerWidget {
  const _RainSection({required this.layer});

  final RainLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = rainLevelsFor(layer);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          layer.label,
          // Grün wie die anderen Überschriften seit dem
          // Betreiber-Vorschlag 2026-08-05; die Ticks darunter bleiben
          // barkBrown — Text auf Cream, beide Themen.
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, _) in levels.indexed)
              Container(
                width: 16,
                height: 9,
                color: AppColors.rainLine(index).withAlpha(rainFillAlpha),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Nur die Enden der Skala. Jede Stufe zu beziffern hieße
            // acht Zahlen auf 130 Bildpunkten — die stünden
            // übereinander, und die genauen Werte stehen ohnehin an den
            // Bandgrenzen in der Karte.
            Text('${levels.first}', style: _tick(theme)),
            SizedBox(width: 16.0 * levels.length - 34),
            Text('${levels.last}+ mm', style: _tick(theme)),
          ],
        ),
      ],
    );
  }
}

/// Die eingeblendeten Waldklassen — nur die gewählten (#231): Eine
/// Legende, die Farben erklärt, die gerade gar nicht auf der Karte
/// liegen, wäre eine kleine Lüge.
class _ForestSection extends StatelessWidget {
  const _ForestSection({required this.classes});

  final Set<ForestClass> classes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Waldtypen',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 3),
        for (final (forestClass, label) in const [
          (ForestClass.broadleaf, 'Laub'),
          (ForestClass.mixed, 'Misch'),
          (ForestClass.conifer, 'Nadel'),
        ])
          if (classes.contains(forestClass))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 9,
                    color: forestClassColor(forestClass)
                        .withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: _tick(theme)),
                ],
              ),
            ),
      ],
    );
  }
}

TextStyle? _tick(ThemeData theme) => theme.textTheme.labelSmall
    ?.copyWith(color: AppColors.barkBrown, fontSize: 9);

/// Die Farbe einer Waldklasse — EINE Stelle für Blatt, Legende und
/// Fläche, damit nichts auseinanderläuft.
Color forestClassColor(ForestClass forestClass) => switch (forestClass) {
      ForestClass.broadleaf => AppColors.forestBroadleaf,
      ForestClass.mixed => AppColors.forestMixed,
      ForestClass.conifer => AppColors.forestConifer,
      ForestClass.none => AppColors.forestGreen, // nie gezeichnet
    };
