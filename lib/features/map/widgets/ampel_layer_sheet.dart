// Das Pilzampel-Blatt: Schalter, Grenzen, Kosten.
//
// **Warum es das jetzt gibt.** Der Schalter der Ampel-Fläche wohnte bis
// hierher im REGEN-Blatt, und der Pfeil in der Ebenen-Zeile führte
// ebenfalls dorthin. Das war eine Erbschaft: In der ersten Fassung war
// die Ampel ein Modus des Regens. Seit 1.76.0 färbt sie ausschließlich
// die WALDwaben — sie ist ein Modus der Waldfläche, und der Regen ist
// nur noch eine ihrer beiden Zutaten. Wer dem Pfeil folgte, landete
// seither bei der falschen Ebene und fand einen Schalter, der zu einer
// anderen Zeile gehörte.
//
// **Warum die Grenzen hier stehen und nicht in der Zeile.** Die
// Einschränkungen sind lang und sie sind wichtig — nur Deutschland,
// bewertet Bedingungen statt Vorkommen, im Gebirge unsicher, beim ersten
// Mal knapp 2 MB. In der Zeile stünde davon nichts oder alles: nichts
// wäre unehrlich, alles machte die Zeile zum Absatz. Die Zeile trägt
// deshalb die Aussage und die Nebenwirkung, das Blatt die Grenzen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../ampel/ampel_map_providers.dart';

Future<void> showAmpelLayerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _AmpelLayerSheet(),
  );
}

class _AmpelLayerSheet extends ConsumerWidget {
  const _AmpelLayerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        // Wie die Nachbarblätter gedeckelt: Man soll die Wirkung eines
        // Schalters sofort auf der Karte sehen.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Text('Pilzampel',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.ampelStrong.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      child: Text('experimentell',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.ampelStrong,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Text(
                'Lässt die Waldwaben dort leuchten, wo die Bedingungen für '
                'Steinpilz & Co. gerade stimmen.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  SwitchListTile(
                    title: const Text('Ampel-Fläche auf der Karte'),
                    // Dieselbe Nebenwirkung wie in der Ebenen-Zeile, und
                    // aus demselben Grund benannt: Ohne Waldebene hätte
                    // das Leuchten nichts, worauf es liegen könnte.
                    subtitle: const Text('Schaltet die Waldtypen mit an und '
                        'holt sich die Wetterdaten vom Spot (beim ersten '
                        'Mal knapp 2 MB).'),
                    value: ref.watch(ampelLayerEnabledProvider),
                    // Die Kette mit den Nebenwirkungen steht EINMAL, in
                    // `ampel_map_providers.dart` — das Ebenen-Blatt ruft
                    // dieselbe. Zwei Kopien wären zwei Antworten auf
                    // denselben Schalter.
                    onChanged: (value) => setAmpelLayerEnabled(ref, value),
                  ),
                  const Divider(height: 16),
                  const _Limit(
                    icon: Icons.public_off,
                    title: 'Nur Deutschland',
                    text: 'Die Regensummen kommen vom Deutschen '
                        'Wetterdienst und enden an der Grenze. Außerhalb '
                        'bleibt die Waldwabe schlicht Wald.',
                  ),
                  const _Limit(
                    icon: Icons.terrain,
                    title: 'Im Gebirge unsicher',
                    text: 'Die Temperatur kommt von der nächsten '
                        'Wetterstation, und die kann Hunderte Höhenmeter '
                        'tiefer oder höher stehen. Die App rechnet sie auf '
                        'die Wabenhöhe um — aber eine Umrechnung ist keine '
                        'Messung.',
                  ),
                  // Der wichtigste Satz des Blattes, und er steht
                  // zuletzt, weil er den Rest einordnet: Die
                  // Rückwärtsvalidierung ist in der Arten-Kontrolle
                  // durchgefallen (`docs/pilzampel-validierung.md`).
                  // Deshalb spricht auch das Banner im Konjunktiv. Wer
                  // die Fläche anschaltet, soll wissen, was sie ist —
                  // ein Versuch, keine Auskunft.
                  const _Limit(
                    icon: Icons.science_outlined,
                    title: 'Bewertet Bedingungen, nicht Vorkommen',
                    text: 'Sie sagt, wo Regen und Temperatur gerade '
                        'passen — nicht, wo Pilze stehen. An echten '
                        'Funden hat sich das Modell bisher nicht '
                        'bewährt.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Datenbasis: Deutscher Wetterdienst, Werte verändert',
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

/// Eine Grenze der Aussage — Symbol, Überschrift, ein Satz.
class _Limit extends StatelessWidget {
  const _Limit({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: AppColors.barkBrown),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(text),
    );
  }
}
