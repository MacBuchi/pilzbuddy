// Die Legende auf der Karte.
//
// **Warum sie sein muss:** Seit 1.46.0 zeichnet die App die Summen in
// eigenen Farben. Ohne Legende bedeutet ein grüner Fleck genau nichts —
// der Betreiber hat es am 2026-08-04 als Erstes bemängelt, und er hatte
// recht: Im Regen-Blatt steht die Erklärung zwar, aber wer die Karte
// ansieht, hat das Blatt zu.
//
// **Warum sie klein bleibt:** Die Karte ist der Inhalt. Dieselbe Regel
// wie beim Filter- und Regen-Blatt — was dauerhaft über der Karte liegt,
// kostet jeden Bildschirm Höhe. Deshalb links UNTEN (dort ist der
// einzige freie Rand; rechts stehen die Knöpfe, oben die Banner), nur bei
// aktiver Regenebene, und ohne Beschriftung jeder einzelnen Stufe: Die
// Zahlen stehen in der Karte an den Bandgrenzen, hier steht nur, wohin
// die Skala läuft.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../rain_data_providers.dart';
import '../rain_fill.dart';
import '../rain_layer.dart';

class RainLegend extends ConsumerWidget {
  const RainLegend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(rainLayerProvider);
    // Nur zu den eigenen Farben. Beim Radar liegt das DWD-Bild in
    // DWD-Farben auf der Karte — dafür wäre diese Skala schlicht falsch,
    // und die richtige steht als Bild im Blatt.
    final ownColours =
        ref.watch(rainContoursProvider(layer)).value?.isNotEmpty ?? false;
    if (!ownColours) return const SizedBox.shrink();

    final levels = rainLevelsFor(layer);
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Padding(
        // Über dem Maßstab, der unten links sitzt.
        padding: const EdgeInsets.only(left: 12, bottom: 44),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.cream.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  layer.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.barkBrown,
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
                        color: AppColors.rainLine(index)
                            .withAlpha(rainFillAlpha),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nur die Enden der Skala. Jede Stufe zu beziffern
                    // hieße acht Zahlen auf 130 Bildpunkten — die stünden
                    // übereinander, und die genauen Werte stehen ohnehin
                    // an den Bandgrenzen in der Karte.
                    Text('${levels.first}',
                        style: _tick(theme)),
                    SizedBox(width: 16.0 * levels.length - 34),
                    Text('${levels.last}+ mm', style: _tick(theme)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle? _tick(ThemeData theme) => theme.textTheme.labelSmall
      ?.copyWith(color: AppColors.barkBrown, fontSize: 9);
}
