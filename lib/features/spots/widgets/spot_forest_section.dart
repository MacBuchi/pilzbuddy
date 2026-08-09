// „Wald hier" im Spot-Blatt (#213): eine Zeile aus dem Waldtypen-Gitter.
//
// Fakt, keine Wertung — dieselbe stehende Regel wie bei Saison und Regen:
// Eine Ampel kommt erst, wenn sie sich an echten Funden bewährt hat.
// Diese Zeile ist zugleich der Baustein, den die Pilzampel später
// abfragt (#158, zweiter Teil).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/forest_block_providers.dart';
import '../../map/forest_grid.dart';

class SpotForestSection extends ConsumerWidget {
  const SpotForestSection({super.key, required this.lat, required this.lon});

  final double lat;
  final double lon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Die kombinierte Sicht (#253): feine Wabe, wo ein Block geladen
    // ist, sonst das Asset — je Antwort, nicht je App-Lauf.
    final grid = ref.watch(forestViewProvider);
    // Kein Gitter oder außerhalb der Abdeckung: nichts — eine Zeile
    // „keine Daten" an jedem Spot außerhalb DACHs wäre Lärm (dieselbe
    // Entscheidung wie beim Regen).
    final forestClass = grid?.classAt(lat, lon);
    if (grid == null || forestClass == null) return const SizedBox.shrink();

    final share = grid.shareAt(lat, lon);
    final text = switch (forestClass) {
      // „Kein Wald" wird gezeigt: Am Wiesenrand-Spot ist das eine
      // ehrliche Auskunft über die Wabe, kein Fehler — und die
      // Wabengröße steht dabei, weil sie die Aussage bemisst.
      ForestClass.none =>
        'kein Wald (Wabe ≈ ${grid.usesFineAt(lat, lon) ? 100 : 250} m)',
      ForestClass.broadleaf => 'überwiegend Laubwald'
          '${share == null ? '' : ' ($share % Nadel)'}',
      ForestClass.mixed =>
        'Mischwald${share == null ? '' : ' ($share % Nadel)'}',
      ForestClass.conifer => 'überwiegend Nadelwald'
          '${share == null ? '' : ' ($share % Nadel)'}',
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.forest_outlined,
              size: 18, color: Theme.of(context).hintColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Wald hier: $text · Stand ${grid.referenceYearAt(lat, lon)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
