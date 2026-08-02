import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/widgets/mushroom_icon.dart';
import '../../../core/mushroom_species.dart';
import '../spot_filter.dart';

/// Blatt zum Filtern der Karte (Issue #154).
///
/// Hinter einem Knopf statt als dauerhafte Leiste: Die Karte ist der Inhalt,
/// und eine Chip-Zeile über ihr kostet auf jedem Bildschirm Höhe — auch bei
/// den vielen, die nie filtern.
Future<void> showSpotFilterSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _SpotFilterSheet(),
    );

class _SpotFilterSheet extends ConsumerWidget {
  const _SpotFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(spotFilterProvider);
    final species = ref.watch(filterSpeciesProvider);
    final notifier = ref.read(spotFilterProvider.notifier);

    return SafeArea(
      child: ConstrainedBox(
        // Höchstens zwei Drittel des Bildschirms: Die Karte soll hinter dem
        // Blatt sichtbar bleiben, damit man sieht, worauf man filtert.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.66,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Karte filtern',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  if (filter.isActive)
                    TextButton(
                      onPressed: () {
                        notifier.clear();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Zurücksetzen'),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              value: filter.onlyMine,
              onChanged: notifier.setOnlyMine,
              title: const Text('Nur meine Spots'),
              subtitle: const Text('Blendet die Spots deiner Freunde aus'),
            ),
            const Divider(height: 1),
            Flexible(
              child: species.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'Noch keine Funde mit Pilzart — trag bei einem '
                          'Fund die Art ein, dann lässt sich danach filtern.'),
                    )
                  // Bewusst ListTile mit Häkchen statt RadioListTile: Dessen
                  // `groupValue`/`onChanged` sind seit Flutter 3.32
                  // veraltet, und der Ersatz (RadioGroup) hängt an der
                  // Flutter-Version — die in CI ist eine andere als lokal.
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        _SpeciesTile(
                          label: 'Alle Arten',
                          selected: filter.species == null,
                          onTap: () => notifier.setSpecies(null),
                        ),
                        for (final entry in species)
                          _SpeciesTile(
                            label: entry.name,
                            subtitle: entry.spots == 1
                                ? '1 Fundstelle'
                                : '${entry.spots} Fundstellen',
                            selected: filter.species == entry.name,
                            onTap: () => notifier.setSpecies(entry.name),
                            leading: MushroomIcon(
                              seed: entry.name.hashCode,
                              size: 32,
                              group: groupFor(entry.name),
                              species: entry.name,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeciesTile extends StatelessWidget {
  const _SpeciesTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        selected: selected,
        leading: leading ?? const SizedBox(width: 32),
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: selected
            ? const Icon(Icons.check, color: AppColors.forestGreen)
            : null,
      );
}
