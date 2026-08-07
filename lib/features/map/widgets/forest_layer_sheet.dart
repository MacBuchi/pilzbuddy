// Blatt zur Waldtypen-Ebene (#213).
//
// Hinter einem Knopf statt als dauerhafte Leiste — dieselbe Begründung
// wie bei Regen und Filter: Die Karte ist der Inhalt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../forest_data_providers.dart';
import '../rain_layer.dart';

Future<void> showForestLayerSheet(BuildContext context) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _ForestLayerSheet(),
    );

class _ForestLayerSheet extends ConsumerWidget {
  const _ForestLayerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(forestLayerEnabledProvider);
    final grid = ref.watch(forestGridProvider).valueOrNull;
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        // Höchstens zwei Drittel — die Karte soll hinter dem Blatt
        // sichtbar bleiben, damit man die Wirkung sofort sieht.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.66,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Waldtypen',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                // Der ehrliche Satz zur Auflösung: 250-m-Zellen zeigen
                // Richtungen, keine einzelnen Bestände. Wer den
                // Laubwaldstreifen am Bach sucht, braucht die Augen.
                'Laub-, Misch- und Nadelwald aus Satellitendaten '
                '(${grid == null ? 'DACH' : 'Stand ${grid.referenceYear}'}, '
                '250-m-Raster). Zeigt Richtungen, keine einzelnen Bestände.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            SwitchListTile(
              title: const Text('Waldtypen einblenden'),
              // Schaltet die Regenfläche ab (siehe onChanged): Zwei
              // halbtransparente Flächen übereinander sind unlesbar.
              subtitle: ref.watch(rainLayerProvider) != RainLayer.off
                  ? const Text('Blendet dafür die Regenebene aus.')
                  : null,
              value: enabled,
              onChanged: (value) {
                ref.read(forestLayerEnabledProvider.notifier).state = value;
                if (value) {
                  ref.read(rainLayerProvider.notifier).state = RainLayer.off;
                }
              },
            ),
            if (enabled) ...[
              const Divider(height: 16),
              const _Legend(),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                // Lizenzpflicht der Quelle — gehört hierher, nicht in
                // die Datenschutzerklärung: Die App verbindet sich
                // nirgendwohin, das Gitter liegt im APK.
                '© Europäische Union, Copernicus Land Monitoring Service',
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

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (colour, label) in [
            (AppColors.forestBroadleaf, 'Laubwald'),
            (AppColors.forestMixed, 'Mischwald'),
            (AppColors.forestConifer, 'Nadelwald'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(
                  width: 18,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(label, style: theme.textTheme.bodySmall),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Ohne Farbe: kein Wald.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ),
        ],
      ),
    );
  }
}
