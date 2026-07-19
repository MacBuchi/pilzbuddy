import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors.dart';
import '../../../core/mushroom_species.dart';
import '../../../core/widgets/mushroom_avatar.dart';
import '../../../core/widgets/mushroom_icon.dart';
import '../../profile/profile_providers.dart';
import '../../../models/spot.dart';
import '../spot_providers.dart';
import 'add_find_sheet.dart';

/// Detail-Sheet für einen Spot: Fundhistorie, „Fund eintragen",
/// Freigabe-Ausschluss und Löschen.
Future<void> showSpotDetailSheet(BuildContext context, String spotId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _SpotDetailSheet(spotId: spotId),
  );
}

class _SpotDetailSheet extends ConsumerWidget {
  const _SpotDetailSheet({required this.spotId});

  final String spotId;

  void _showError(BuildContext context, String action, Object error,
      StackTrace stackTrace) {
    logError(action, error, stackTrace);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyError(error))));
  }

  Future<void> _addFind(BuildContext context, WidgetRef ref, Spot spot) async {
    final ownSpecies = ref.read(ownSpeciesProvider);
    final data = await showAddFindSheet(
      context,
      lastFind: spot.lastFind,
      ownSpecies: ownSpecies,
      fallbackSpecies: ownSpecies.firstOrNull,
    );
    if (data == null) return;
    try {
      await ref.read(mySpotsProvider.notifier).addFind(
            spotId: spot.id,
            species: data.species,
            count: data.count,
            foundOn: data.foundOn,
            note: data.note,
          );
    } catch (e, stackTrace) {
      if (context.mounted) {
        _showError(context, 'Fund eintragen', e, stackTrace);
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spot löschen?'),
        content: const Text(
            'Der Spot und alle seine Funde werden dauerhaft gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(mySpotsProvider.notifier).deleteSpot(spotId);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e, stackTrace) {
      if (context.mounted) {
        _showError(context, 'Spot löschen', e, stackTrace);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mySpots = ref.watch(mySpotsProvider).valueOrNull ?? const <Spot>[];
    final friendSpots =
        ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[];
    final spot = [...mySpots, ...friendSpots]
        .where((s) => s.id == spotId)
        .firstOrNull;
    if (spot == null) return const SizedBox.shrink();

    final dateFormat = DateFormat('d.M.y');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MushroomIcon(
                seed: stableSeed(spot.id),
                size: 30,
                friend: !spot.isOwn,
                group: groupFor(spot.lastFind?.species),
                species: spot.lastFind?.species,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(spot.displayName,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (spot.isOwn)
                IconButton(
                  onPressed: () => _delete(context, ref),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Spot löschen',
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                MushroomAvatar(
                  index: spot.isOwn
                      ? (ref.watch(myProfileProvider).valueOrNull?.avatar ?? 0)
                      : spot.ownerAvatar,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Text(
                  spot.isOwn
                      ? 'Dein Spot'
                      : 'Gefunden von ${spot.ownerUsername ?? 'einem Pilzfreund'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (spot.finds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                spot.isOwn
                    ? 'Noch keine Funde eingetragen.'
                    : 'Nur der Standort wurde geteilt.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final find in spot.findsSorted)
                    ListTile(
                      dense: true,
                      leading: const Text('🍄', style: TextStyle(fontSize: 20)),
                      title: Text(find.label),
                      subtitle: Text([
                        dateFormat.format(find.foundOn),
                        if (find.note != null && find.note!.isNotEmpty)
                          find.note!,
                      ].join(' – ')),
                    ),
                ],
              ),
            ),
          if (spot.isOwn) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Von Freigabe ausschließen'),
              subtitle: const Text(
                  'Diesen Spot nicht mit Freunden teilen – auch wenn das Teilen global an ist.'),
              value: spot.sharingExcluded,
              onChanged: (value) async {
                try {
                  await ref
                      .read(mySpotsProvider.notifier)
                      .setSharingExcluded(spot.id, value);
                } catch (e, stackTrace) {
                  if (context.mounted) {
                    _showError(
                        context, 'Freigabe umschalten', e, stackTrace);
                  }
                }
              },
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: () => _addFind(context, ref, spot),
              icon: const Icon(Icons.add),
              label: const Text('Fund eintragen'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
          SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
        ],
      ),
    );
  }
}
