// Die Auswahl, wenn die Ampel an MEHREREN eigenen Spots günstig steht
// (#345).
//
// **Warum es dieses Blatt gibt.** „An 7 Spots stünde die Ampel günstig"
// ist kein Ausnahmefall: Die eigenen Spots liegen in derselben Region und
// bekommen dasselbe Wetter — eine gute Regenlage macht sie im Zweifel
// alle auf einmal günstig. Bis 1.103.0 öffnete das Banner den
// bestbewerteten und schaltete sich bis Mitternacht stumm; die anderen
// sechs waren damit für den Tag verloren. Die Zahl im Bannertext war eine
// Aussage, zu der es keinen Weg gab.
//
// **Warum eine Liste und keine Karte auf alle sieben.** Naheliegend wäre,
// die Kamera auf das umschließende Rechteck zu setzen. Nur sieht man dann
// nicht, WELCHE der sichtbaren Marker die Treffer sind — die eigenen
// Spots stehen alle da, günstig oder nicht. Und die Kartenfassade kann
// heute `move(center, zoom)`; ein Bbox-Fit wäre eine neue Methode in
// beiden Engines.
//
// Das Blatt entscheidet nichts: Es gibt den gewählten Spot zurück, der
// Aufrufer springt und öffnet. So bleibt der Sprungbefehl an einer
// Stelle.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/widgets/mushroom_icon.dart';
import '../../../models/spot.dart';
import '../../ampel/ampel_scan.dart';

/// Zeigt [hits] zur Auswahl und liefert den angetippten Spot — `null`,
/// wenn das Blatt weggewischt wurde.
Future<Spot?> showAmpelHitsSheet(BuildContext context, List<AmpelHit> hits) {
  return showModalBottomSheet<Spot>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AmpelHitsSheet(hits: hits),
  );
}

class _AmpelHitsSheet extends ConsumerWidget {
  const _AmpelHitsSheet({required this.hits});

  final List<AmpelHit> hits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      // Wie das Spot-Blatt und „Was ist hier?": gedeckelt, damit die Karte
      // dahinter sichtbar bleibt — und scrollbar, weil die Liste bei
      // vielen eigenen Spots lang wird.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.circle,
                        size: 14, color: AppColors.ampelStrong),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Ampel günstig an ${hits.length} Spots',
                          style: theme.textTheme.titleLarge),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Der Vorbehalt steht EINMAL oben und nicht je Zeile: Alle
                // Einträge tragen dieselbe Stufe, eine Wiederholung in
                // sieben Zeilen wäre Lärm. Die volle Herkunft der Formel
                // steht im Spot-Blatt, das ein Tipp öffnet.
                Text(
                  'Bewertet Bedingungen, nicht Vorkommen — experimentell. '
                  'Bester zuerst.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: hits.length,
              itemBuilder: (context, index) {
                final spot = hits[index].spot;
                return ListTile(
                  // Dieselbe Sprache wie die Listenzeilen sonst: das
                  // Pilz-Symbol der zuletzt gefundenen ART (`lastFind` ist
                  // leergangsfrei — ein „nichts gefunden" hat keine Art,
                  // die man zeichnen könnte).
                  leading: MushroomIcon.forSpecies(
                    spot.lastFind?.species,
                    fallbackSeed: spot.id,
                  ),
                  title: Text(spot.displayName),
                  trailing: const Icon(Icons.map_outlined, size: 20),
                  onTap: () => Navigator.of(context).pop(spot),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
