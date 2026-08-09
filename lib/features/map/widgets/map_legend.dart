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
import 'package:latlong2/latlong.dart';

import '../../../core/app_colors.dart';
import '../../../core/errors.dart';
import '../../../core/settings.dart';
import '../../ampel/ampel_map_providers.dart';
import '../../ampel/ampel_model.dart';
import '../../ampel/ampel_providers.dart';
import '../forest_block_providers.dart';
import '../forest_data_providers.dart';
import '../forest_fill.dart'
    show ampelHighlightGuenstigAlpha, ampelHighlightVerhaltenAlpha;
import '../forest_grid.dart';
import '../rain_data_providers.dart';
import '../rain_fill.dart';
import '../rain_layer.dart';
import 'here_sheet.dart';

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

/// Die Kartenmitte beim letzten Kamera-Stillstand (#235) — gesetzt vom
/// Karten-Screen über [MapViewConfig.onCameraIdle], `null` bis zum
/// ersten Stillstand. BEWUSST nicht die laufende Kameraposition: Die
/// Fadenkreuz-Werte rechnen nur, wenn die Karte steht.
final mapIdleCenterProvider = StateProvider<LatLng?>((ref) => null);

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
    final combined = ref.watch(ampelForestCombinedProvider);
    final showAmpel = ref.watch(ampelPreviewEnabledProvider) &&
        (ref.watch(ampelLayerEnabledProvider) || combined);
    if (!showRain && !showForest && !showAmpel) {
      return const SizedBox.shrink();
    }

    // Die Fadenkreuz-Werte (#235): gerechnet an der Mitte des LETZTEN
    // Kamera-Stillstands — nicht an der laufenden Position, das wäre
    // eine Rechnung pro Frame während der Geste. Seit #253 über die
    // kombinierte Sicht: Liegt ein feiner Block unterm Fadenkreuz,
    // zählt der Kilometer auf 100-m-Waben.
    final center = ref.watch(mapIdleCenterProvider);
    final forest = ref.watch(forestViewProvider);
    final around = (showForest && center != null && forest != null)
        ? forest.broadleafFactorAround(center.latitude, center.longitude)
        : null;
    final rainMm = (showRain && center != null)
        ? ref
            .watch(rainGridProvider(rainLayer))
            .valueOrNull
            ?.mmAt(center.latitude, center.longitude)
        : null;
    // Das Pilzwetter am Fadenkreuz — dieselbe pure Rechnung wie im
    // Spot-Blatt, auf denselben zwei Providern.
    AmpelReading? ampelAt;
    if (showAmpel && center != null) {
      final at = (lat: center.latitude, lon: center.longitude);
      final course = ref.watch(rainCourseProvider(at));
      final temperature = ref.watch(spotTemperatureProvider(at));
      if (!course.isLoading && !temperature.isLoading) {
        ampelAt = ampelReadingFrom(
            course.valueOrNull, temperature.valueOrNull);
      }
    }

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
              // Tipp auf die Werte öffnet „Was ist hier?" (#245): Wer die
              // Zahl am Fadenkreuz liest, ist genau der, der als Nächstes
              // Verlauf und Temperatur wissen will. Nur die Skalen sind
              // antippbar — das X daneben behält seine eigene Aufgabe.
              //
              // Ohne Stillstand (`center == null`) gibt es nichts zu
              // zeigen: `onTap: null` lässt den Tipp dann an die Karte
              // durch, statt ein leeres Blatt zu öffnen.
              InkWell(
                onTap: center == null
                    ? null
                    : () => showHereSheet(context, center),
                borderRadius: BorderRadius.circular(6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showAmpel)
                      _AmpelSection(
                          reading: ampelAt,
                          palette: ref.watch(ampelPaletteProvider),
                          combined: combined),
                    if (showAmpel && showForest)
                      const SizedBox(height: 6),
                    if (showRain) _RainSection(layer: rainLayer, mm: rainMm),
                    if (showRain && showForest) const SizedBox(height: 6),
                    if (showForest)
                      _ForestSection(classes: forestClasses, around: around),
                  ],
                ),
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

/// Wo auf der Stufenskala ein Messwert liegt, als Anteil 0..1 — `null`
/// unterhalb der ersten Stufe (dort ist die Karte farblos, ein Strich
/// am Skalenanfang behauptete sonst „mindestens Stufe eins").
///
/// Innerhalb eines Bandes linear, oberhalb der letzten Stufe ans Ende
/// geklemmt — die Skala endet dort ohnehin mit „+".
double? rainMarkerFraction(int mm, List<int> levels) {
  if (levels.isEmpty || mm < levels.first) return null;
  for (var i = levels.length - 1; i >= 0; i--) {
    if (mm >= levels[i]) {
      if (i == levels.length - 1) return 1;
      final band = (mm - levels[i]) / (levels[i + 1] - levels[i]);
      return (i + band) / levels.length;
    }
  }
  return null;
}

/// Die Pilzwetter-Zeile der Legende: das Wort am Fadenkreuz plus die
/// zwei Farbchips — „ungünstig" hat bewusst keinen Chip, es ist auf der
/// Karte transparent („keine Stufe heißt aussichtslos").
class _AmpelSection extends StatelessWidget {
  const _AmpelSection(
      {required this.reading,
      required this.palette,
      required this.combined});

  final AmpelReading? reading;

  /// Dieselbe Familie, in der die Fläche malt — die Legende erklärt
  /// die Karte, nicht eine zweite Farbwelt.
  final AmpelPalette palette;

  /// Kombi-Ebene: Dann steht das Wetter nicht als eigene Fläche da,
  /// sondern in den leuchtenden WABEN — und die Chips zeigen genau die
  /// beiden Leuchtstärken, in denen die Karte sie malt.
  final bool combined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = reading?.level;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          switch (level) {
            null => combined
                ? 'Wald + Pilzwetter (experimentell) · Steinpilz & Co.'
                : 'Pilzwetter (experimentell) · Steinpilz & Co.',
            _ => '${combined ? 'Wald + Pilzwetter' : 'Pilzwetter'} '
                '(experimentell) · hier: ${ampelLevelWord(level)}',
          },
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (colour, opacity, word) in combined
                // In der Kombi leuchtet EINE Farbe in zwei Stärken —
                // genau die Werte, mit denen der Zeichner malt.
                ? [
                    (palette.highlight,
                        ampelHighlightVerhaltenAlpha / 255, 'verhalten'),
                    (palette.highlight,
                        ampelHighlightGuenstigAlpha / 255, 'günstig'),
                  ]
                : [
                    (palette.mild, 0.55, 'verhalten'),
                    (palette.strong, 0.55, 'günstig'),
                  ]) ...[
              Container(
                width: 12,
                height: 9,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: opacity),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 3),
              Text(word,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontSize: 9, color: AppColors.barkBrown)),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _RainSection extends ConsumerWidget {
  const _RainSection({required this.layer, required this.mm});

  final RainLayer layer;

  /// Der Wert am Fadenkreuz (#235) — `null` ohne Gitter oder außerhalb.
  final int? mm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = rainLevelsFor(layer);
    final theme = Theme.of(context);
    final barWidth = 16.0 * levels.length;
    final fraction = mm == null ? null : rainMarkerFraction(mm!, levels);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // Der Messwert direkt im Titel — die Zahl zum Strich unten.
          mm == null ? layer.label : '${layer.label} · hier $mm mm',
          // Grün wie die anderen Überschriften seit dem
          // Betreiber-Vorschlag 2026-08-05; die Ticks darunter bleiben
          // barkBrown — Text auf Cream, beide Themen.
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: barWidth,
          height: 11,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, _) in levels.indexed)
                      Container(
                        width: 16,
                        height: 9,
                        color: AppColors.rainLine(index)
                            .withAlpha(rainFillAlpha),
                      ),
                  ],
                ),
              ),
              // Der Strich zum Fadenkreuz-Wert (#235).
              if (fraction != null)
                Positioned(
                  key: const Key('legend-rain-marker'),
                  left: (fraction * barWidth).clamp(1.0, barWidth - 1) - 1,
                  top: -1,
                  child: Container(
                      width: 2, height: 13, color: AppColors.barkBrown),
                ),
            ],
          ),
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
            SizedBox(width: barWidth - 34),
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
/// Die Wald-Sektion als SKALA von Laub (links) nach Nadel (rechts) —
/// seit #235 mit dem Messstrich des Fadenkreuz-Umkreises direkt darauf.
/// Abgewählte Klassen (#231) bleiben als blasse Segmente stehen: Die
/// Skala ist die Achse des Laubfaktors, sie darf keine Lücken haben —
/// aber sie sagt ehrlich, welche Farben gerade NICHT auf der Karte
/// liegen.
class _ForestSection extends StatelessWidget {
  const _ForestSection({required this.classes, required this.around});

  final Set<ForestClass> classes;

  /// Ergebnis von [ForestGrid.broadleafFactorAround] am Fadenkreuz —
  /// `null` ohne Stillstand oder außerhalb der Abdeckung.
  final ({double? factor, double forestShare})? around;

  static const _segmentWidth = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const barWidth = _segmentWidth * 3;
    final factor = around?.factor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          switch (around) {
            null => 'Waldtypen',
            (factor: null, forestShare: _) => 'Waldtypen · 1 km: kein Wald',
            // Der Umkreis steht dabei: „Laubfaktor 0,43" ohne Bezugsgröße
            // liest sich wie eine Aussage über den Punkt unter dem
            // Fadenkreuz — gemeint ist die Umgebung.
            (:final factor?, :final forestShare) => 'Waldtypen · 1 km: '
                'Laubfaktor '
                '${factor.toStringAsFixed(2).replaceAll('.', ',')}'
                ' · Wald ${(forestShare * 100).round()} %',
          },
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: barWidth,
          height: 11,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final forestClass in const [
                      ForestClass.broadleaf,
                      ForestClass.mixed,
                      ForestClass.conifer,
                    ])
                      Container(
                        width: _segmentWidth,
                        height: 9,
                        color: forestClassColor(forestClass).withValues(
                            alpha:
                                classes.contains(forestClass) ? 0.55 : 0.15),
                      ),
                  ],
                ),
              ),
              // Der Messstrich (#235): Faktor 1 = Laub = linkes Ende.
              if (factor != null)
                Positioned(
                  key: const Key('legend-forest-marker'),
                  left:
                      ((1 - factor) * barWidth).clamp(1.0, barWidth - 1) - 1,
                  top: -1,
                  child: Container(
                      width: 2, height: 13, color: AppColors.barkBrown),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: barWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Laub', style: _tick(theme)),
              Text('Nadel', style: _tick(theme)),
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
