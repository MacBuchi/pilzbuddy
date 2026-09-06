import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/widgets/mushroom_icon.dart';
import '../../../core/mushroom_species.dart';
import '../../ampel/ampel_scan.dart';
import '../spot_filter.dart';

/// Blatt zum Filtern der Karte (Issue #154).
///
/// Hinter einem Knopf statt als dauerhafte Leiste: Die Karte ist der Inhalt,
/// und eine Chip-Zeile über ihr kostet auf jedem Bildschirm Höhe — auch bei
/// den vielen, die nie filtern.
///
/// [onFit] rückt die gezeigten Spots ins Bild (#399). Es kommt als
/// Rückruf vom Karten-Screen und nicht aus einem Provider, weil dafür die
/// Kamera und die Fensterbreite gebraucht werden — beides gehört der
/// Karte, nicht dem Blatt. `null` heißt „noch nicht möglich": Solange die
/// Karte keinen Stillstand gemeldet hat, gibt es keine Auflösung, aus der
/// sich ein Zoom ableiten ließe.
Future<void> showSpotFilterSheet(BuildContext context, {VoidCallback? onFit}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SpotFilterSheet(onFit: onFit),
    );

class _SpotFilterSheet extends ConsumerWidget {
  const _SpotFilterSheet({this.onFit});

  final VoidCallback? onFit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(spotFilterProvider);
    final species = ref.watch(filterSpeciesProvider);
    final notifier = ref.read(spotFilterProvider.notifier);
    // Kein zusätzliches Laden: `MapBanners` beobachtet denselben Provider
    // ohnehin auf jedem Kartenaufbau, und ohne die drei Schalter im Profil
    // kehrt er um, bevor er ein Gitter anfasst (`ampel_scan.dart`).
    final ampelHits =
        ref.watch(ampelScanProvider).valueOrNull ?? const <AmpelHit>[];

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
                  // Der Zoom sitzt in der Kopfzeile und nicht als eigene
                  // Zeile: Gemessen kostete eine Zeile hier 72 dp, und die
                  // gehen der Artenliste ab — im 600-dp-Fenster blieben ihr
                  // 90 statt 220 dp. Er ist außerdem eine Aktion und keine
                  // Einstellung, gehört also ohnehin nach oben zu
                  // „Zurücksetzen" und nicht zwischen die Schalter.
                  IconButton(
                    onPressed: onFit == null
                        ? null
                        : () {
                            onFit!();
                            Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.zoom_out_map),
                    tooltip: onFit == null
                        ? 'Auf Auswahl zoomen — sobald die Karte steht'
                        : 'Auf Auswahl zoomen',
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
            // Nur wählbar, solange es überhaupt günstige Spots gibt (#399)
            // — ein Schalter, der auf eine leere Karte führt, wäre von
            // „kaputt" nicht zu unterscheiden. Und `onChanged: null` allein
            // ist keine Auskunft, deshalb sagt der Untertitel, WARUM:
            // „kein Fehler ohne Fehlermeldung".
            SwitchListTile(
              value: filter.onlyAmpel,
              onChanged: ampelHits.isEmpty ? null : notifier.setOnlyAmpel,
              title: const Text('Nur wo die Ampel günstig steht'),
              subtitle: Text(ampelHits.isEmpty
                  ? 'Gerade an keinem deiner Spots'
                  : '${ampelHits.length} deiner Spots · experimentell'),
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
                        // Bleibt oben stehen und ist angehakt, solange
                        // nichts gewählt ist: ein Tipp zurück auf „zeig
                        // alles", egal wie viele Arten angehakt sind.
                        _SpeciesTile(
                          label: 'Alle Arten',
                          selected: filter.species.isEmpty,
                          onTap: notifier.clearSpecies,
                        ),
                        for (final entry in species)
                          _SpeciesTile(
                            label: entry.name,
                            subtitle: entry.spots == 1
                                ? '1 Fundstelle'
                                : '${entry.spots} Fundstellen',
                            selected: filter.species.contains(entry.name),
                            onTap: () => notifier.toggleSpecies(entry.name),
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
