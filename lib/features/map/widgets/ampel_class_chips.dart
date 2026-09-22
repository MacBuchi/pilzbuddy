// Die Gruppen-Chips: für welche Ampel-Gruppen die Karte spricht.
//
// EIN Widget für zwei Blätter — den Kartenfilter (seit 1.142.0) und das
// Fundorte-Blatt (seit 1.155.0, Betreiber 2026-09-21: „Können wir auch
// hier Chips nutzen, um einzelne Teillayer auszublenden?"). Beide
// schreiben in DIESELBE Auswahl, `SpotFilter.classes`: Was hier eine
// Gruppe ausblendet, engt auch Ampel-Fläche und -Hinweis ein, und der
// Filter-Chip auf der Karte meldet es (#154). Ein zweiter, nur für die
// Scheiben geltender Wähler ließe Scheiben still verschwinden.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ampel/ampel_model.dart' show ampelClasses;
import '../gbif_fill.dart' show gbifClassColour;
import '../spot_filter.dart';

/// **Ab Werk sind alle an** (Betreiberauflage), und genau dieser Zustand
/// ist der leere Satz in [SpotFilter.classes] — die Chips zeigen ihn als
/// „alle ausgewählt", ohne dass der Filter sich als aktiv meldet.
///
/// Die letzte gewählte Gruppe steht als DEAKTIVIERTER Chip da, statt bei
/// einem Tipp nichts zu tun: Ein Bedienelement, das folgenlos bleibt,
/// liest sich als Fehler. Die Zeile darunter sagt zusätzlich, warum.
///
/// [intro] ist der Satz über den Chips — je Blatt ein anderer, weil er
/// sagt, was die Auswahl HIER bewirkt. Mit [withColours] trägt jeder
/// Chip den Farbpunkt seiner Gruppe aus der Fundorte-Tabelle.
/// Die Gruppen-Chips als Block.
///
/// **Benannt, seit der Filter eigene Chips hat** (1.181.0): „wie viele
/// `FilterChip` stehen im Blatt" trifft seither beide Sorten, und ein
/// Test, der die Gruppen zählen will, zählte die Filter mit.
const kAmpelClassChipsKey = ValueKey('ampel-klassen-chips');

class AmpelClassChips extends ConsumerWidget {
  const AmpelClassChips({
    super.key,
    required this.intro,
    this.withColours = false,
  });

  final String intro;
  final bool withColours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chosen = ref.watch(spotFilterProvider).classes;
    final notifier = ref.read(spotFilterProvider.notifier);
    // Leer heißt alle — dieselbe Auflösung wie `ampelClassesOf`, nur für
    // die Anzeige. Die Chips sind dann alle angehakt.
    final selected = chosen.isEmpty ? ampelClasses.keys.toSet() : chosen;
    final last = selected.length == 1;
    return Padding(
      key: kAmpelClassChipsKey,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            intro,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in ampelClasses.entries)
                FilterChip(
                  // Kompakt wie die Schalter darüber `dense` sind: Der
                  // Artenliste bleiben im 600-dp-Fenster ohnehin nur
                  // Zeilen, keine Bildschirme.
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: withColours
                      ? CircleAvatar(
                          backgroundColor: gbifClassColour(entry.key)
                              .withValues(alpha: 0.8),
                        )
                      : null,
                  label: Text(entry.value.name),
                  selected: selected.contains(entry.key),
                  onSelected: last && selected.contains(entry.key)
                      ? null
                      : (_) => notifier.toggleClass(entry.key),
                ),
            ],
          ),
          // Nur im Grenzfall eine zweite Zeile: Der deaktivierte Chip
          // allein sagt nicht, warum er sich nicht abwählen lässt.
          if (last) ...[
            const SizedBox(height: 6),
            Text(
              'Mindestens eine Gruppe bleibt an.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }
}
