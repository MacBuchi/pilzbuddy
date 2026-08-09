// Blatt zur Waldtypen-Ebene (#213).
//
// Hinter einem Knopf statt als dauerhafte Leiste — dieselbe Begründung
// wie bei Regen und Filter: Die Karte ist der Inhalt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings.dart';
import '../../ampel/ampel_map_providers.dart'
    show ampelLayerEnabledProvider;
import '../forest_block_providers.dart';
import '../forest_data_providers.dart';
import '../forest_grid.dart';
import 'map_legend.dart';

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
                'Waben ≈ 250 m). Zeigt Richtungen, keine einzelnen Bestände.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            // Scrollbar wie im Regen-Blatt: Mit Checkliste und
            // Legenden-Schalter passt das Blatt sonst nicht mehr auf
            // kleine Schirme.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  SwitchListTile(
                    title: const Text('Waldtypen einblenden'),
                    // Seit #232 OHNE Regen-Abschaltung: Die Teil-Ebenen
                    // unten machen die Kombination lesbar — wer Regen
                    // über Wald will, lässt nur die Klasse stehen, die
                    // ihn interessiert.
                    value: enabled,
                    onChanged: (value) {
                      ref.read(forestLayerEnabledProvider.notifier).state =
                          value;
                      // Die Ampel IST die Waldfläche in anderen Farben
                      // — ohne Wald hätte sie nichts zu malen.
                      if (!value) {
                        ref
                            .read(ampelLayerEnabledProvider.notifier)
                            .state = false;
                      }
                    },
                  ),
                  if (enabled) ...[
                    const Divider(height: 16),
                    const _ClassChecklist(),
                    const Divider(height: 16),
                    // Der Schalter IST die Zustimmung (#253), wie beim
                    // Regenverlauf: Der Text nennt die Kosten, mehr
                    // Dialog braucht es nicht. Persistent — einmal
                    // zustimmen, nicht jede Wanderung neu.
                    SwitchListTile(
                      dense: true,
                      title: const Text('Feine Waben (≈ 100 m) nachladen'),
                      subtitle: const Text(
                          'Holt fürs sichtbare Gebiet ein feineres Gitter '
                          'aus dem Netz — je Gebiet rund 1 MB, bleibt '
                          'gespeichert. Kommt erst nah dran (Maßstab um '
                          '1 km); weiter draußen zeigt die eingebaute '
                          'Karte (≈ 250 m) dasselbe Bild. Ohne Empfang '
                          'gilt sie ohnehin.'),
                      value: ref.watch(forestFineEnabledProvider),
                      onChanged: (value) async {
                        ref
                            .read(forestFineEnabledProvider.notifier)
                            .state = value;
                        await ref
                            .read(settingsProvider)
                            .setForestFineEnabled(value);
                      },
                    ),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Legende in Karte anzeigen'),
                      value: ref.watch(mapLegendEnabledProvider),
                      onChanged: (value) => ref
                          .read(mapLegendEnabledProvider.notifier)
                          .set(value),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                // Lizenzpflicht der Quelle — gehört hierher, nicht in
                // die Datenschutzerklärung: Das Gitter liegt im APK,
                // und die feinen Blöcke (#253) kommen von den
                // GitHub-Releases, die dort längst stehen.
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

/// Die drei Klassen als Teil-Ebenen (#231): Häkchen statt bloßer
/// Legende — abgewählte Klassen verschwinden von der Karte. Der
/// Farbchip macht die Zeile zugleich zur Legende des Blatts.
class _ClassChecklist extends ConsumerWidget {
  const _ClassChecklist();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(forestClassesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (forestClass, label) in const [
          (ForestClass.broadleaf, 'Laubwald'),
          (ForestClass.mixed, 'Mischwald'),
          (ForestClass.conifer, 'Nadelwald'),
        ])
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Container(
              width: 18,
              height: 12,
              decoration: BoxDecoration(
                color: forestClassColor(forestClass)
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            title: Text(label, style: theme.textTheme.bodyMedium),
            value: selected.contains(forestClass),
            onChanged: (checked) {
              final next = {...selected};
              if (checked == true) {
                next.add(forestClass);
              } else {
                next.remove(forestClass);
              }
              ref.read(forestClassesProvider.notifier).state = next;
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text('Ohne Farbe: kein Wald.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor)),
        ),
      ],
    );
  }
}
