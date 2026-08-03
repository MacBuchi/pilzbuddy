import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../rain_layer.dart';

/// Blatt zur Wahl der Regenebene (#156).
///
/// Hinter einem Knopf statt als dauerhafte Leiste — dieselbe Begründung
/// wie beim Filter-Blatt: Die Karte ist der Inhalt, und eine Leiste über
/// ihr kostet auf jedem Bildschirm Höhe, auch bei allen, die nie Regen
/// einblenden.
Future<void> showRainLayerSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _RainLayerSheet(),
    );

class _RainLayerSheet extends ConsumerWidget {
  const _RainLayerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(rainLayerProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        // Höchstens zwei Drittel: Die Karte soll hinter dem Blatt sichtbar
        // bleiben, damit man die Wirkung der Wahl sofort sieht.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.66,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Regen', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                // Kein Urteil, sondern Messwerte — die Ampel kommt erst,
                // wenn sie sich an echten Funden bewährt hat.
                'Messwerte des Deutschen Wetterdienstes. Wie viel Regen '
                'gefallen ist und wann — den Rest weißt du besser.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // Einzeilig, und die Erläuterung steht nur zur
                  // gewählten Ebene darunter: Mit Untertitel an jedem
                  // Eintrag rutschte „Letzte 30 Tage" auf kleinen
                  // Bildschirmen aus dem Blatt — ausgerechnet der
                  // Eintrag, für den es dieses Blatt gibt.
                  for (final layer in RainLayer.values)
                    ListTile(
                      // Von Hand statt RadioListTile: Dessen `groupValue`
                      // und `onChanged` sind zugunsten eines
                      // RadioGroup-Vorfahren abgekündigt, den das in CI
                      // gepinnte Flutter noch nicht kennt. Ein Häkchen
                      // tut hier dasselbe.
                      leading: Icon(
                        layer == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: layer == current
                            ? AppColors.friendBlue
                            : theme.hintColor,
                      ),
                      title: Text(layer.label),
                      selected: layer == current,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      onTap: () =>
                          ref.read(rainLayerProvider.notifier).state = layer,
                    ),
                  if (current != RainLayer.off) ...[
                    const Divider(height: 16),
                    _Details(layer: current),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Daten: Deutscher Wetterdienst',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Was die gewählte Ebene zeigt, wo sie gilt, und ihre Legende.
class _Details extends ConsumerWidget {
  const _Details({required this.layer});

  final RainLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final url = rainLegendUrl(layer);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(layer.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(layer.coverage, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          if (url != null)
            DecoratedBox(
              // Heller Grund unter der Legende: Der DWD liefert sie mit
              // schwarzer Schrift auf Weiß — im dunklen Thema wäre sie
              // sonst ein weißer Block mit unlesbarem Rand.
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image(
                  image: ref.read(rainImageProviderFactory)(url),
                  height: 220,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  // Die Legende kommt aus dem Netz wie die Ebene selbst.
                  // Ohne Empfang gibt es beides nicht — dann ein Satz
                  // statt eines kaputten Bildsymbols.
                  errorBuilder: (context, error, stack) => Text(
                    'Legende nicht geladen',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
