// Aufräumen, was sich schon überlagert (#215).
//
// Die Rückfrage beim Anlegen verhindert NEUE Doppelungen; was vorher
// entstanden ist, liegt weiter auf der Karte übereinander. Hier steht es
// als Liste, Paar für Paar, mit einer Entscheidung je Paar — kein
// „alles zusammenführen"-Knopf: Welcher Name bleibt, weiß nur der
// Betreiber, und die Aktion ist nicht umkehrbar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../models/spot.dart';
import 'nearby_spots.dart';
import 'spot_providers.dart';

class SpotCleanupScreen extends ConsumerWidget {
  const SpotCleanupScreen({super.key});

  Future<void> _merge(BuildContext context, WidgetRef ref,
      {required Spot into, required Spot from}) async {
    final findCount = from.entriesSorted.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spots zusammenführen?'),
        content: Text(
            '${findCount == 1 ? 'Der Eintrag' : 'Alle $findCount Einträge'} '
            'von „${from.displayName}" wandert${findCount == 1 ? '' : 'n'} zu '
            '„${into.displayName}". Danach gibt es „${from.displayName}" '
            'nicht mehr.\n\n'
            'Das lässt sich nicht rückgängig machen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Zusammenführen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(mySpotsProvider.notifier)
          .mergeSpots(intoId: into.id, fromId: from.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Zusammengeführt zu „${into.displayName}" 🍄')));
      }
    } catch (e, stackTrace) {
      logError('Spots zusammenführen', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairs = overlappingPairs(ref.watch(mySpotListProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('Dicht beieinander')),
      body: pairs.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Diese Fundorte liegen weniger als '
                  '${kNearbySpotMeters.round()} m auseinander — im Wald ist '
                  'das dieselbe Stelle. Du kannst sie zu einem machen.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final pair in pairs)
                  _PairCard(
                    pair: pair,
                    onMerge: (into, from) =>
                        _merge(context, ref, into: into, from: from),
                  ),
              ],
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🍄', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              'Nichts aufzuräumen — deine Fundorte liegen alle weit genug '
              'auseinander.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({required this.pair, required this.onMerge});

  final SpotPair pair;
  final void Function(Spot into, Spot from) onMerge;

  String _line(Spot spot) {
    final count = spot.entriesSorted.length;
    return '${spot.displayName} · '
        '${count == 1 ? '1 Eintrag' : '$count Einträge'}';
  }

  @override
  Widget build(BuildContext context) {
    final mergeable = canMerge(pair);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${pair.meters.round()} m auseinander',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(_line(pair.a)),
            Text(_line(pair.b)),
            const SizedBox(height: 10),
            if (mergeable)
              // Beide Richtungen ausgeschrieben statt einer stillen Regel,
              // welcher Spot gewinnt: Der Name ist oft die ganze
              // Information, und raten wäre hier nicht umkehrbar.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => onMerge(pair.a, pair.b),
                    child: Text('In „${pair.a.displayName}"'),
                  ),
                  OutlinedButton(
                    onPressed: () => onMerge(pair.b, pair.a),
                    child: Text('In „${pair.b.displayName}"'),
                  ),
                ],
              )
            else
              Text(
                'Hier hat ein Pilz-Buddy eingetragen. Seine Funde könnten '
                'nicht mitwandern und gingen verloren — deshalb bleibt '
                'dieses Paar, wie es ist.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
