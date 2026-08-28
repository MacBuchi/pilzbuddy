// Blatt zur Höhenlinien-Ebene.
//
// Hinter einem Knopf statt als dauerhafte Leiste — dieselbe Begründung
// wie bei Wald, Regen und Filter: Die Karte ist der Inhalt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../elevation_contour_providers.dart';
import '../elevation_providers.dart';
import 'map_legend.dart';

Future<void> showTerrainLayerSheet(BuildContext context) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _TerrainLayerSheet(),
    );

class _TerrainLayerSheet extends ConsumerWidget {
  const _TerrainLayerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(contourLayerEnabledProvider);
    // Das Gitter wird hier zum ersten Mal angefasst — im Blatt, nicht
    // beim App-Start (Begründung am FAB in map_screen.dart). Wer das
    // Blatt öffnet, will die Ebene; dafür darf es 3,4 MB kosten.
    final grid = ref.watch(elevationGridProvider);
    final missing = grid.hasValue && grid.valueOrNull == null;
    final drawn = ref.watch(contourEquidistanceProvider);
    final theme = Theme.of(context);
    final tooFarOut = ref.watch(contourTooFarOutProvider);

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
              child: Text('Höhenlinien',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                // Der ehrliche Satz zur Auflösung, wie ihn das
                // Wald-Blatt für seine 250-m-Waben hat. Er nennt beides:
                // was die Ebene kann und wo sie zu Recht nichts zeigt.
                // Ohne den zweiten Teil sieht eine leere Karte in der
                // Lüneburger Heide nach einem Fehler aus.
                'Geländehöhe aus dem Copernicus-Höhenmodell, auf denselben '
                'Waben wie die Waldtypen (≈ 270 m, Stufen von 20 m). '
                'Zeigt Hang, Mulde und Kuppe — keine einzelne '
                'Geländekante. Im Flachland bleibt die Karte fast leer, '
                'weil es dort nichts zu zeigen gibt.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  SwitchListTile(
                    title: const Text('Höhenlinien einblenden'),
                    subtitle: Text(switch ((enabled, tooFarOut, drawn)) {
                      // Kein verschwundener Knopf, sondern ein Satz: Das
                      // Höhengitter ist mitgeliefert, es fehlt also nur,
                      // wenn beim Auspacken etwas schiefging.
                      _ when missing =>
                        'Das Höhengitter lässt sich nicht laden — ohne '
                            'es gibt es keine Höhenlinien',
                      (false, _, _) => 'Aus',
                      // Der Fall, den man sonst für einen Fehler hielte:
                      // Ebene an, Karte leer. Er gehört benannt.
                      (true, true, _) =>
                        'Erst näher dran — bei diesem Maßstab lägen die '
                            'Linien hier so dicht, dass sie eine '
                            'Schraffur wären',
                      (true, false, final int metres) =>
                        'Alle $metres m; die kräftigen Linien tragen ihre '
                            'Höhe',
                      (true, false, null) => 'Wird gerechnet …',
                    }),
                    value: enabled && !missing,
                    onChanged: missing
                        ? null
                        : (value) => ref
                            .read(contourLayerEnabledProvider.notifier)
                            .set(value),
                  ),
                  if (enabled)
                    SwitchListTile(
                      dense: true,
                      title: const Text('Legende in Karte anzeigen'),
                      value: ref.watch(mapLegendEnabledProvider),
                      onChanged: (value) => ref
                          .read(mapLegendEnabledProvider.notifier)
                          .set(value),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                // Lizenzpflicht der Quelle — gehört hierher, nicht in
                // die Datenschutzerklärung: Das Gitter liegt im APK,
                // die Ebene baut keine einzige Verbindung auf.
                '© Europäische Union, Copernicus DEM GLO-90 — '
                'gerechnet auf dem Gerät, ohne Verbindung',
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
