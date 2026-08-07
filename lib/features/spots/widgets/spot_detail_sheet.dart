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
import 'species_season_section.dart';
import 'spot_forest_section.dart';
import 'spot_rain_section.dart';

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

  /// „Herbsttrompete · auch: Totentrompete" — oder `null`, wenn die Art
  /// unbekannt ist oder keine Zweitnamen hat.
  String? _synonymLine(Spot spot) {
    final species = spot.lastFind?.species;
    final synonyms = synonymsOf(species);
    if (synonyms.isEmpty) return null;
    return '${canonicalSpecies(species)} · auch: ${synonyms.join(', ')}';
  }

  void _showError(BuildContext context, String action, Object error,
      StackTrace stackTrace) {
    logError(action, error, stackTrace);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyError(error))));
  }

  /// Öffnet das Eingabeblatt und schreibt, was zurückkommt. [blank] macht
  /// daraus „Nichts gefunden" (#211) — derselbe Weg, weil sich nur das
  /// Blatt unterscheidet, nicht das Schreiben.
  Future<void> _addFinds(BuildContext context, WidgetRef ref, Spot spot,
      {bool blank = false}) async {
    final ownSpecies = ref.read(ownSpeciesProvider);
    final finds = await showAddFindSheet(
      context,
      // Der letzte EIGENE Fund, nicht der letzte überhaupt: Am
      // Freundes-Spot soll nicht dessen Art im Formular vorstehen.
      lastFind: spot.lastOwnFind,
      ownSpecies: ownSpecies,
      fallbackSpecies: ownSpecies.firstOrNull,
      blank: blank,
    );
    if (finds == null) return;
    try {
      await ref
          .read(mySpotsProvider.notifier)
          .addFinds(spotId: spot.id, finds: finds);
    } catch (e, stackTrace) {
      if (context.mounted) {
        _showError(
            context, blank ? 'Leergang eintragen' : 'Fund eintragen', e,
            stackTrace);
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
    final mySpots = ref.watch(mySpotListProvider);
    final friendSpots =
        ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[];
    final spot = [...mySpots, ...friendSpots]
        .where((s) => s.id == spotId)
        .firstOrNull;
    if (spot == null) return const SizedBox.shrink();

    final dateFormat = DateFormat('d.M.y');
    return ConstrainedBox(
      // Der Regenabschnitt hat das Blatt über die Bildschirmhöhe hinaus
      // wachsen lassen. Zwei Änderungen statt einer Kürzung: eine
      // Obergrenze, damit die Karte dahinter sichtbar bleibt (dieselbe
      // Begründung wie im Filter- und Regen-Blatt), und Scrollen, damit
      // nichts abgeschnitten wird, was jemand lesen will.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        child: Padding(
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
          // Zweitnamen der zuletzt gefundenen Art. Gespeichert ist die
          // Hauptbezeichnung; wer die Stelle als „Totentrompete" angelegt
          // hat, findet hier wieder, dass es dieselbe Art ist.
          if (_synonymLine(spot) case final line?)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(line,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          if (spot.entriesSorted.isEmpty)
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
                  // Leergänge stehen mit in der Liste: Sie gehören zur
                  // Besuchshistorie des Spots („am 12.9. war nichts da").
                  // Gedämpft und mit anderem Zeichen, damit die Liste auf
                  // einen Blick zeigt, was ein Fund war und was nicht.
                  for (final find in spot.entriesSorted)
                    ListTile(
                      dense: true,
                      leading: find.blank
                          ? Icon(Icons.search_off,
                              color: Theme.of(context).disabledColor)
                          : MushroomIcon.forSpecies(find.species,
                              fallbackSeed: find.id),
                      title: Text(
                        find.label,
                        style: find.blank
                            ? TextStyle(color: Theme.of(context).hintColor)
                            : null,
                      ),
                      subtitle: Text([
                        dateFormat.format(find.foundOn),
                        if (find.note != null && find.note!.isNotEmpty)
                          find.note!,
                        // Fremde Funde nennen ihren Eintrager (#190) —
                        // unmarkiert heißt: meiner.
                        if (!find.isOwn)
                          'von ${find.authorUsername ?? 'einem Pilzfreund'}',
                      ].join(' – ')),
                      trailing: find.isOwn
                          ? null
                          : MushroomAvatar(index: find.authorAvatar, size: 22),
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
          ],
          // Auch am Freundes-Spot (#190): Wer den Spot sehen darf, darf
          // dort eigene Funde eintragen — die RLS zieht dieselbe Grenze.
          // Freigabe-Schalter und Löschen bleiben dagegen beim Besitzer.
          //
          // „Nichts gefunden" steht bewusst gleichberechtigt daneben und
          // nicht im Fund-Blatt versteckt (#211): Es ist der Eintrag, den
          // man macht, wenn man gerade enttäuscht ist — er muss ohne
          // Suchen erreichbar sein. Zurückhaltender Stil, weil er
          // seltener gemeint ist als der Fund.
          //
          // Zwei lange deutsche Beschriftungen nebeneinander sind eng.
          // Nachgemessen bis 320 dp und Schriftskalierung 1,3: Material
          // bricht die Beschriftung dann auf zwei Zeilen um, statt
          // überzulaufen — ein Überlauf ist hier also kein Risiko, und
          // deshalb steht auch kein Test dafür.
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addFinds(context, ref, spot),
                  icon: const Icon(Icons.add),
                  label: const Text('Fund eintragen'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addFinds(context, ref, spot, blank: true),
                  icon: const Icon(Icons.search_off, size: 18),
                  label: const Text('Nichts gefunden'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
          // Ganz unten, nicht oben: Die Fundhistorie ist der Inhalt des
          // Blatts, Saison und Regen sind die Zusatzfrage „ist der Spot
          // dran?". Oben stünden sie über der Antwort, für die man das
          // Blatt geöffnet hat.
          //
          // Die Art vor dem Wetter: Sie gehört zur Fundliste darüber,
          // und ihre Kurve steht ohne Netz sofort da — der Regen kommt
          // je nach Empfang später oder gar nicht.
          SpeciesSeasonSection(species: spot.lastFind?.species),
          // Der Waldtyp zwischen Saison und Wetter: Er gehört wie die
          // Saison zur Frage „was für eine Stelle ist das", und er steht
          // ohne Netz sofort da (Asset), während der Regen je nach
          // Empfang später kommt.
          SpotForestSection(lat: spot.lat, lon: spot.lng),
          SpotRainSection(lat: spot.lat, lon: spot.lng),
          SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
        ],
      ),
    ),
      ),
    );
  }
}
