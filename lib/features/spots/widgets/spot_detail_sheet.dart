import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

  void _showError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aktion fehlgeschlagen. Internet verfügbar?')));
  }

  Future<void> _addFind(BuildContext context, WidgetRef ref, Spot spot) async {
    final data = await showAddFindSheet(context, lastFind: spot.lastFind);
    if (data == null) return;
    try {
      await ref.read(mySpotsProvider.notifier).addFind(
            spotId: spot.id,
            species: data.species,
            count: data.count,
            foundOn: data.foundOn,
            note: data.note,
          );
    } catch (_) {
      if (context.mounted) _showError(context);
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
    } catch (_) {
      if (context.mounted) _showError(context);
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
              Icon(
                Icons.location_on,
                color: spot.isOwn ? const Color(0xFF2E7D32) : Colors.blue,
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
          if (!spot.isOwn)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Spot von ${spot.ownerUsername ?? 'einem Freund'}',
                  style: Theme.of(context).textTheme.bodySmall),
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
                } catch (_) {
                  if (context.mounted) _showError(context);
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
