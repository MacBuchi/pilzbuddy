// „Wald hier" im Spot-Blatt (#213), seit #227 mit den Baumarten.
//
// Fakt, keine Wertung — dieselbe stehende Regel wie bei Saison und Regen:
// Eine Ampel kommt erst, wenn sie sich an echten Funden bewährt hat.
// Diese Zeile ist zugleich der Baustein, den die Pilzampel später
// abfragt (#158, zweiter Teil).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/forest_block_providers.dart';
import '../../map/forest_grid.dart';
import '../../map/forest_species.dart';
import '../../map/forest_species_providers.dart';

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

    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.forest_outlined,
                  size: 18, color: Theme.of(context).hintColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Wald hier: $text · Stand ${grid.referenceYearAt(lat, lon)}',
                  style: style,
                ),
              ),
            ],
          ),
          _SpeciesLine(
              lat: lat, lon: lon, isForest: forestClass != ForestClass.none,
              coniferPercent: share),
        ],
      ),
    );
  }
}

/// Die Artenzeile — gemessen in Deutschland (DLR) und der Schweiz (WSL),
/// geschätzt sonst (ForestPaths, #624), und nur wo etwas zu benennen ist.
///
/// Eigenes Widget, damit ein fehlendes Artengitter nur DIESE Zeile
/// kostet und nicht die Waldzeile darüber.
class _SpeciesLine extends ConsumerWidget {
  const _SpeciesLine({
    required this.lat,
    required this.lon,
    required this.isForest,
    required this.coniferPercent,
  });

  final double lat;
  final double lon;
  final bool isForest;
  final int? coniferPercent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measuredAsync = ref.watch(forestSpeciesGridProvider);
    // Erst die Antwort des DLR-Gitters abwarten: Während es lädt, sähe
    // es aus wie „schweigt", und das nächste Gitter würde an jedem
    // deutschen Spot mit ausgepackt (im Test so gefunden).
    if (measuredAsync.isLoading) return const SizedBox.shrink();
    final measured = measuredAsync.valueOrNull;
    final byte = measured?.byteAt(lat, lon);
    // Beobachten ist laden: Jedes weitere Gitter wird erst angefasst, wo
    // das vorige schweigt — ein Spot in Deutschland packt keins davon
    // aus, einer in der Schweiz nicht ForestPaths.
    final dlrSilent = byte == null || byte == speciesNoData;
    final swissAsync =
        dlrSilent ? ref.watch(forestSpeciesChGridProvider) : null;
    if (swissAsync?.isLoading ?? false) return const SizedBox.shrink();
    final swiss = swissAsync?.valueOrNull;
    final swissSilent = swiss?.at(lat, lon) == null;
    final fallback = dlrSilent && swissSilent
        ? ref.watch(forestSpeciesEuGridProvider).valueOrNull
        : null;
    final line = treeSpeciesLineAt(
      dlr: measured,
      swiss: swiss,
      forestPaths: fallback,
      lat: lat,
      lon: lon,
      coniferPercent: coniferPercent,
    );
    if (line == null) return const SizedBox.shrink();

    // Wo das Waldgitter „kein Wald" sagt, die Artenkarte aber Bäume
    // kennt, sind es Waldränder — gemessen 3,9 % der Zellen (#227).
    // Schweigen wäre dort schlechter als eine andere Formulierung: Eine
    // Eiche am Wiesenrand ist für einen Sammler ein Hinweis, kein
    // Widerspruch.
    final prefix = isForest ? 'Bäume' : 'Einzelne Bäume';
    // Jede Quelle sagt, was sie ist und was sie nicht sehen kann — sonst
    // läse sich „Fichte" als „hier keine Lärche" (#624). Die Schweizer
    // Karte kennt Lärche gar nicht.
    final source = switch (line.source) {
      TreeSpeciesSource.dlr => 'Stand ${line.referenceYear}',
      TreeSpeciesSource.swiss =>
        'Baumartenkarte Schweiz, Lärche nicht erfasst · '
            'Stand ${line.referenceYear}',
      TreeSpeciesSource.forestPaths =>
        'Satellitenschätzung, Lärche nicht erkennbar · '
            'Stand ${line.referenceYear}',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 24),
      child: Text(
        '$prefix: ${joinTreeNames(line.names)} · $source',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
