// Rang und Spiegel im Profil (#276).
//
// Steht im Abschnitt „Teilen mit Freunden", direkt über dem Schalter —
// dort, wo die Entscheidung fällt, um die es geht.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import 'sharing_rank.dart';
import 'sharing_rank_providers.dart';

class SharingRankTile extends ConsumerWidget {
  const SharingRankTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final shared = ref.watch(mySharedSpotCountProvider);
    final title = ref.watch(mySharingTitleProvider);
    final next = nextSharingRank(shared);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.hub_outlined,
              color: title == null ? theme.hintColor : AppColors.forestGreen),
          // Ohne Titel steht hier eine EINLADUNG, keine Etikettierung.
          // „Frischling" oder gar „Schnorrer" wäre genau der Ton, den
          // dieses Feature vermeiden soll.
          title: Text(title ?? 'Noch kein Rang'),
          subtitle: Text(switch ((title, next)) {
            (null, final n?) =>
              'Teile deinen ersten Spot — dann bist du ${n.title}.',
            (_, final n?) => '$shared geteilt · noch ${n.from - shared} '
                'bis ${n.title}',
            _ => '$shared geteilt · höchster Rang erreicht',
          }),
        ),
        // Der Spiegel: der Ersatz für die verworfene Schranke. Er nimmt
        // niemandem etwas weg, er sagt nur, wie es steht — und nur, wenn
        // es wirklich schief steht.
        if (ref.watch(sharingMirrorProvider))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Du siehst ${ref.watch(seenBuddySpotCountProvider)} Spots von '
              'deinen Buddies und teilst selbst $shared.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
      ],
    );
  }
}
