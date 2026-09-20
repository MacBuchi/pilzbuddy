// „Im Umkreis gemeldet" (#467) — der Abschnitt im „Was ist hier?"-Blatt,
// der die GBIF-Meldungen rund um einen Punkt aufzählt.
//
// Das ist die Verwendung, die die Messung selbst empfohlen hat
// (`docs/gbif-fundorte-messung.md`): Sie braucht keine Flächendeckung,
// und sie wird mit jeder Meldung besser statt gröber. Die Liste sagt
// „in dieser Gegend gemeldet", nicht „an dieser Stelle" — eine Meldung
// zählt, wenn ihre Fläche in den Umkreis reicht (`GbifFinds.around`).
//
// Bewusst OHNE Filter: Das Blatt beschreibt den Ort, nicht die Auswahl.
// Wer nur eine Art sehen will, liest die Zeile dieser Art.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gbif_fill.dart' show gbifClassColour;
import '../../ampel/ampel_model.dart' show ampelClassFor, ampelClassKeyOf;
import '../gbif_finds_providers.dart';

/// Der Umkreis der Liste. 5 km, weil das die Größe ist, in der die
/// Messung überhaupt Aussagen fand — und weil ein Sammler das als
/// „hier in der Gegend" liest.
const gbifAroundRadiusM = 5000.0;

/// Mehr Zeilen zeigt der Abschnitt nicht; der Rest steht als Zahl.
const gbifAroundMaxRows = 8;

class GbifAroundSection extends ConsumerWidget {
  const GbifAroundSection({super.key, required this.lat, required this.lon});

  final double lat;
  final double lon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Beobachten ist laden — und hier ist das gewollt: Das Blatt wird
    // bewusst geöffnet, 0,6 MB einmal je App-Lauf sind dafür in
    // Ordnung. Am Knopf oder in der Legende stünde das nicht.
    final findsAsync = ref.watch(gbifFindsProvider);
    final finds = findsAsync.valueOrNull;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);

    final Widget body;
    if (finds == null) {
      body = Text(
          findsAsync.hasValue
              ? 'Die Fundorte lassen sich nicht laden.'
              : 'Fundorte werden gelesen …',
          style: hint);
    } else {
      final rows = finds.around(lat, lon, radiusM: gbifAroundRadiusM);
      if (rows.isEmpty) {
        body = Text(
            'Keine Meldung im Umkreis von 5 km — das heißt nur, dass hier '
            'niemand gemeldet hat.',
            style: hint);
      } else {
        final shown = rows.take(gbifAroundMaxRows).toList();
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: gbifClassColour(() {
                          final klass = ampelClassFor(row.species);
                          return klass == null ? null : ampelClassKeyOf(klass);
                        }())
                            .withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(row.species,
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      '${row.observations}×'
                      '${row.newestYear == null ? '' : ' · zuletzt ${row.newestYear}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (rows.length > shown.length)
              Text('… und ${rows.length - shown.length} weitere Arten',
                  style: hint),
          ],
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 18),
              const SizedBox(width: 6),
              Text('Im Umkreis von 5 km gemeldet (GBIF)',
                  style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.only(left: 24), child: body),
        ],
      ),
    );
  }
}
