import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/widgets/mushroom_icon.dart';
import '../../../core/mushroom_species.dart';
import '../../../core/season_curves.dart';
import '../../ampel/ampel_model.dart';
import '../../ampel/ampel_providers.dart' show ampelPreviewEnabledProvider;
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
    final seasonCount = ref.watch(seasonSpotCountProvider);
    final monthName = kMonthNames[ref.watch(currentMonthProvider) - 1];

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
            // `dense` seit dem dritten Schalter (#414): Drei Zeilen zu
            // 72 dp kosteten der Artenliste 216 dp, und im 600-dp-Fenster
            // blieb ihr damit weniger als eine Bildschirmzeile. Die Liste
            // scrollt zwar, aber was man scrollen muss, findet man
            // seltener.
            SwitchListTile(
              dense: true,
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
              dense: true,
              value: filter.onlyAmpel,
              onChanged: ampelHits.isEmpty ? null : notifier.setOnlyAmpel,
              title: const Text('Nur wo die Ampel günstig steht'),
              subtitle: Text(ampelHits.isEmpty
                  ? 'Gerade an keinem deiner Spots'
                  : '${ampelHits.length} deiner Spots · experimentell'),
            ),
            // Die Gruppen-Chips (Betreiber, 2026-09-12: „Macht es
            // vielleicht auch Sinn, die Klassen als Chips im Ampel-Filter
            // aus-/abzuwählen? … Default sollte alles an sein.").
            //
            // Sie stehen HIER und nicht im Ebenen-Blatt, obwohl sie auch
            // die Fläche betreffen: Ein Filter muss sich auf der Karte
            // melden (#154), und das tut nur, was in `describe()` steht.
            // Nur wenn die Ampel überhaupt rechnet: Ohne die Vorschau
            // gibt es weder Fläche noch Nachlauf, die Chips hätten also
            // nichts zu bewirken — und das Blatt ist knapp. Die
            // Artenliste hat hier seit #414 weniger als eine
            // Bildschirmzeile; ein wirkungsloser Block nähme ihr die
            // nächste.
            if (ref.watch(ampelPreviewEnabledProvider))
              const _AmpelClassChips(),
            // Reine Tabellenarbeit — die Saisonkurven liegen im Binary
            // (#414). Deshalb steht hier kein „experimentell": Der
            // Schalter behauptet nichts über diesen Wald, er sagt nur,
            // wann die Art üblicherweise gemeldet wird.
            SwitchListTile(
              dense: true,
              value: filter.onlySeason,
              onChanged:
                  seasonCount == 0 ? null : notifier.setOnlySeason,
              title: const Text('Nur was jetzt Saison hat'),
              subtitle: Text(seasonCount == 0
                  ? 'Im $monthName hat keine deiner Arten Saison'
                  : '$seasonCount '
                      '${seasonCount == 1 ? 'Fundstelle' : 'Fundstellen'} '
                      'im $monthName'),
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

/// Für welche Pilzgruppen die Ampel sprechen soll.
///
/// **Ab Werk sind alle an** (Betreiberauflage), und genau dieser Zustand
/// ist der leere Satz in [SpotFilter.classes] — die Chips zeigen ihn als
/// „alle ausgewählt", ohne dass der Filter sich als aktiv meldet.
///
/// Die letzte gewählte Gruppe steht als DEAKTIVIERTER Chip da, statt bei
/// einem Tipp nichts zu tun: Ein Bedienelement, das folgenlos bleibt,
/// liest sich als Fehler. Die Zeile darunter sagt zusätzlich, warum.
class _AmpelClassChips extends ConsumerWidget {
  const _AmpelClassChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chosen = ref.watch(spotFilterProvider).classes;
    final notifier = ref.read(spotFilterProvider.notifier);
    // Leer heißt alle — dieselbe Auflösung wie `ampelClassesOf`, nur für
    // die Anzeige. Die Chips sind dann alle angehakt.
    final selected =
        chosen.isEmpty ? ampelClasses.keys.toSet() : chosen;
    final last = selected.length == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Die Zeile ist nicht Zierde: Eine Gruppe HEISST „Pfifferling",
          // und weiter unten steht die Art „Pfifferling" in der Liste.
          // Ohne diesen Satz stünde dasselbe Wort zweimal im selben
          // Blatt und meinte zweierlei.
          Text(
            'Für welche Gruppen die Ampel spricht — auch auf der Fläche:',
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
