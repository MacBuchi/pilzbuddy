// Das Unterwegs-Blatt (#347): die zwei Dinge, die man ANSCHALTET, bevor
// man losgeht — die Pilztour und das Standort-Teilen.
//
// Sie gehören zusammen, weil sie dieselbe Frage beantworten („ich bin
// draußen"), und sie haben dieselbe Eigenschaft: Beide laufen weiter,
// wenn man das Telefon einsteckt, und beide will man hinterher wieder
// aus haben.
//
// **Der Ausgang bleibt einen Tipp weit weg.** Läuft eine Tour, steht ihr
// Stopp-Knopf ZUSÄTZLICH in der Spalte — nicht anstelle dieses Knopfs.
// Der erste Entwurf machte „Unterwegs" bei laufender Tour selbst zum
// Stopp-Knopf; damit wäre das Standort-Teilen während einer Tour
// unerreichbar gewesen, und ein verstecktes Lang-Drücken ist keine
// Antwort darauf. Ein Knopf mehr in genau dem Modus, in dem man den
// Ausgang griffbereit haben will, ist der ehrlichere Tausch.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/app_colors.dart';
import '../../tour/tour_providers.dart';
import '../../tour/widgets/tour_icon.dart';
import '../live_share_providers.dart';

/// Was der Karten-Screen nach dem Blatt tun soll.
enum TripAction { tour, share }

Future<TripAction?> showTripSheet(BuildContext context) {
  return showModalBottomSheet<TripAction>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _TripSheet(),
  );
}

final _time = DateFormat('HH:mm');

class _TripSheet extends ConsumerWidget {
  const _TripSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tour = ref.watch(tourProvider);
    final shareUntil = ref.watch(myShareProvider).valueOrNull;
    final isSharing = ref.watch(isSharingProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('Unterwegs',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          ListTile(
            leading: tour == null
                ? const TourIcon()
                : const Icon(Icons.stop, color: AppColors.forestGreen),
            title: Text(
                tour == null ? 'Pilztour starten' : 'Pilztour beenden'),
            subtitle: Text(tour == null
                ? 'Zeichnet deinen Weg auf und schlägt hinterher die '
                    'Leergänge vor'
                : 'Seit ${_time.format(tour.startedAt.toLocal())} Uhr · '
                    '${tour.points.length} Punkte'),
            onTap: () => Navigator.of(context).pop(TripAction.tour),
          ),
          ListTile(
            leading: Icon(
              isSharing ? Icons.share_location : Icons.share_location_outlined,
              color: isSharing ? AppColors.friendBlue : null,
            ),
            title: Text(isSharing
                ? 'Standort-Teilen verwalten'
                : 'Standort mit Buddies teilen'),
            subtitle: Text(isSharing && shareUntil != null
                ? 'Läuft bis ${_time.format(shareUntil.toLocal())} Uhr'
                : 'Deine Buddys sehen dich live auf ihrer Karte'),
            onTap: () => Navigator.of(context).pop(TripAction.share),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
