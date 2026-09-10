// Das Unterwegs-Blatt (#347): die zwei Dinge, die man ANSCHALTET, bevor
// man losgeht — die Pilztour und das Standort-Teilen.
//
// Sie gehören zusammen, weil sie dieselbe Frage beantworten („ich bin
// draußen"), und sie haben dieselbe Eigenschaft: Beide laufen weiter,
// wenn man das Telefon einsteckt, und beide will man hinterher wieder
// aus haben.
//
// **Warum Karten mit Schaltern statt zweier Listenzeilen.** Genau wegen
// dieser Eigenschaft: Es sind DAUERZUSTÄNDE, keine Befehle. Eine
// Listenzeile heißt „tu das jetzt" und muss deshalb ihre Beschriftung
// umschreiben, sobald etwas läuft („Pilztour starten" ⇄ „Pilztour
// beenden") — man liest also einen Befehl und muss daraus rückwärts
// schließen, was gerade der Fall ist. Ein Schalter zeigt den Zustand
// selbst, und die Überschrift darf stehen bleiben.
//
// **Jede Zeile hat jetzt ihr eigenes Symbol.** Der Knopf auf der Karte
// steht für BEIDE Funktionen und trägt deshalb den Weg mit dem Pilz;
// hier drin wird getrennt, und kein Symbol muss mehr zwei Dinge
// gleichzeitig sagen: das Körbchen für die Tour, der gestrichelte Pin
// in Buddy-Blau fürs Teilen (gestrichelt, weil es bis zu einer Uhrzeit
// läuft und dann von selbst aufhört).
//
// **Der Ausgang bleibt einen Tipp weit weg.** Läuft eine Tour, steht ihr
// Ausgang ZUSÄTZLICH in der Spalte — nicht anstelle dieses Knopfs. Der
// erste Entwurf machte „Unterwegs" bei laufender Tour selbst zum
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('Unterwegs',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          _TripCard(
            icon: const MushroomBasketIcon(size: 24),
            colour: AppColors.forestGreen,
            // Die Überschrift bleibt stehen, der Schalter trägt den
            // Zustand. Vorher hieß dieselbe Zeile mal „Pilztour starten"
            // und mal „Pilztour beenden" — man musste aus dem Befehl
            // erschließen, was gerade läuft.
            title: 'Pilztour',
            subtitle: tour == null
                ? 'Zeichnet deinen Weg auf und schlägt hinterher die '
                    'Leergänge vor'
                : 'Seit ${_time.format(tour.startedAt.toLocal())} Uhr · '
                    '${tour.points.length} Punkte',
            value: tour != null,
            onTap: () => Navigator.of(context).pop(TripAction.tour),
          ),
          const SizedBox(height: 10),
          _TripCard(
            icon: const SharePinIcon(size: 24),
            colour: AppColors.friendBlue,
            title: 'Standort mit Buddies teilen',
            subtitle: isSharing && shareUntil != null
                ? 'Läuft bis ${_time.format(shareUntil.toLocal())} Uhr'
                : 'Deine Buddys sehen dich live auf ihrer Karte',
            value: isSharing,
            onTap: () => Navigator.of(context).pop(TripAction.share),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Eine der beiden Karten: Symbol, Text, Schalter.
///
/// **Der Schalter ist eine ANZEIGE, kein zweites Bedienelement.** Er
/// hört auf denselben Tipp wie die Karte (`onTap` an beiden), statt
/// eigenes `onChanged` zu haben. Zwei getrennte Trefferflächen wären
/// hier ein Versprechen, das die Wege dahinter nicht halten: Das
/// Standort-Teilen fragt nach einer Dauer, die Tour beendet sich über
/// ein Blatt mit Leergang-Vorschlägen. Ein Schalter, der bei „an"
/// stillschweigend ein Blatt öffnet, wäre kein Schalter.
class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.icon,
    required this.colour,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
  });

  final Widget icon;
  final Color colour;
  final String title;
  final String subtitle;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colour.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: IconTheme(
                      data: IconThemeData(color: colour),
                      child: icon,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      Text(subtitle,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.hintColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // `IgnorePointer`, damit der Tipp an die Karte
                // durchgeht: Der Schalter sagt den Zustand, die Karte
                // führt ihn aus.
                IgnorePointer(
                  child: Switch(
                    value: value,
                    activeThumbColor: Colors.white,
                    activeTrackColor: colour,
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
