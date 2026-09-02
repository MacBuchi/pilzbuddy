import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors.dart';
import '../../../core/mushroom_species.dart';
import '../../../core/widgets/mushroom_avatar.dart';
import '../../../core/widgets/mushroom_icon.dart';
import '../../profile/profile_providers.dart';
import '../../../models/find.dart';
import '../../../models/spot.dart';
import '../spot_providers.dart';
import 'add_find_sheet.dart';
import 'edit_find_sheet.dart';
import 'ampel_section.dart';
import 'species_season_section.dart';
import 'spot_forest_section.dart';
import 'spot_rain_section.dart';
import '../../../core/read_after_write.dart';

/// Wie viel Platz über dem Blatt frei bleibt — in logischen Pixeln.
///
/// Der Gegner ist die Statusleiste (24–40 dp je nach Gerät) und die
/// System-Geste, die von dort nach unten wischt. 96 dp lassen auf jedem
/// gemessenen Format genug Abstand, dass man nach dem Griff greifen
/// kann, ohne sie auszulösen — auf Pixel-7-Format bleiben 72 dp frei.
///
/// Bewusst eine feste Zahl und kein Anteil: Ein Anteil wird auf kleinen
/// Geräten klein, und dort ist die Statusleiste genauso hoch wie auf
/// großen.
const kSpotSheetTopClearance = 96.0;

/// Untergrenze, damit das Blatt auf einem sehr kurzen Schirm nicht zum
/// Streifen wird — dann lieber wenig Karte als kein Blatt.
const kSpotSheetMinHeight = 240.0;

/// Detail-Sheet für einen Spot: Fundhistorie, „Fund eintragen",
/// Freigabe-Ausschluss und Löschen.
Future<void> showSpotDetailSheet(BuildContext context, String spotId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Der Griff ist die Antwort auf „nach unten wischen zum Schließen"
    // (#351) — und die einzige, die trägt: Im scrollbaren Inhalt schluckt
    // der SingleChildScrollView jede Abwärtsgeste, gemessen sowohl beim
    // Schwung als auch beim langsamen Zug. Am Griff schließt beides. Ein
    // DraggableScrollableSheet könnte es überall, verlangt aber eine
    // feste Höhenfraktion — ein Spot ohne Funde stünde dann als
    // halbleeres Blatt da.
    showDragHandle: true,
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
      final fresh = await ref
          .read(mySpotsProvider.notifier)
          .addFinds(spotId: spot.id, finds: finds);
      // Nur im Ausnahmefall eine Meldung: Sonst trägt die Liste im Blatt
      // die Quittung selbst — sie steht direkt darunter. Konnte sie
      // nicht neu laden, steht dort nichts Neues, und ohne diesen Satz
      // sähe der Eintrag aus, als wäre er nicht angekommen.
      if (!fresh && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${blank ? 'Leergang' : 'Fund'} eingetragen 🍄'
              '$staleAfterWriteHint'),
        ));
      }
    } catch (e, stackTrace) {
      if (context.mounted) {
        _showError(
            context, blank ? 'Leergang eintragen' : 'Fund eintragen', e,
            stackTrace);
      }
    }
  }

  /// Öffnet das Korrektur-Blatt für einen eigenen Eintrag (#240) und
  /// führt aus, was von dort zurückkommt.
  ///
  /// Nur für eigene Einträge verdrahtet: `finds_author_all` erlaubt
  /// Ändern und Löschen ausschließlich dem Autor — was die Datenbank
  /// ohnehin ablehnt, darf die Oberfläche gar nicht erst anbieten.
  Future<void> _editFind(
      BuildContext context, WidgetRef ref, Find find) async {
    final result = await showEditFindSheet(
      context,
      find: find,
      ownSpecies: ref.read(ownSpeciesProvider),
    );
    if (result == null || !context.mounted) return;
    try {
      if (result.delete) {
        await ref.read(mySpotsProvider.notifier).deleteFind(find.id);
      } else if (result.changed case final changed?) {
        await ref
            .read(mySpotsProvider.notifier)
            .updateFind(findId: find.id, find: changed);
      }
    } catch (e, stackTrace) {
      if (context.mounted) {
        _showError(context, result.delete ? 'Fund löschen' : 'Fund ändern', e,
            stackTrace);
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Spot spot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(spot.pending ? 'Eintrag verwerfen?' : 'Spot löschen?'),
        content: Text(spot.pending
            // Es gibt nichts zu löschen — er ist nie beim Server
            // angekommen. Das gehört gesagt, sonst klingt „gelöscht"
            // nach mehr, als passiert ist.
            ? 'Dieser Spot wartet noch auf die Übertragung. Verwerfen '
                'heißt: Er wird nie gesendet und ist weg.'
            : 'Der Spot und alle seine Funde werden dauerhaft gelöscht.'),
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
    // `LayoutBuilder` statt `MediaQuery`: Nur die eingehenden
    // Constraints kennen den Platz, den das Blatt WIRKLICH hat. Der
    // Einzug der Statusleiste ist hier drinnen schon auf 0 verbraucht
    // (nachgemessen) — aus MediaQuery wäre er also gar nicht zu holen.
    return LayoutBuilder(builder: (context, outer) {
      final available = outer.maxHeight;
      return _body(context, ref, spot, dateFormat, available);
    });
  }

  Widget _body(BuildContext context, WidgetRef ref, Spot spot,
      DateFormat dateFormat, double available) {
    return ConstrainedBox(
      // Der Regenabschnitt hat das Blatt über die Bildschirmhöhe hinaus
      // wachsen lassen. Zwei Änderungen statt einer Kürzung: eine
      // Obergrenze, damit die Karte dahinter sichtbar bleibt (dieselbe
      // Begründung wie im Filter- und Regen-Blatt), und Scrollen, damit
      // nichts abgeschnitten wird, was jemand lesen will.
      //
      // **Kein Anteil der Bildschirmhöhe mehr** (#358, Korrektur an
      // #351): Das Blatt hängt am Navigator der HÜLLE und bekommt
      // deshalb den Body, nicht den Schirm — gemessen 810 dp von 914 auf
      // Pixel-7-Format, der Rest ist die Reiterleiste. Ein Anteil des
      // Schirms war damit ein Anteil der falschen Größe:
      //
      //   0,9 ohne Griff  → 823 dp Blatt in 810 dp Body → Oberkante 0 dp,
      //                     also WIRKLICH unter der Statusleiste (#351).
      //   0,8 mit Griff   → 779 dp in 810 dp → Oberkante 31 dp, bei einer
      //                     24 dp hohen Statusleiste also 7 dp Luft. Wer
      //                     nach dem Griff greift, öffnet die
      //                     Benachrichtigungsleiste (#358).
      //
      // Die frühere Zahl „135 dp Luft" in diesem Kommentar war falsch
      // gemessen: an einer nackten `MaterialApp` OHNE Reiterleiste, die
      // es in der App nicht gibt.
      //
      // Jetzt wird von dem abgezogen, was wirklich da ist — und in
      // Pixeln, weil der Gegner (die Statusleiste) auch in Pixeln misst
      // und nicht in Prozent.
      //
      // **Der Griff wird NICHT abgezogen.** Er steckt in den eingehenden
      // Constraints schon drin: gemessen 810 dp Body, davon kommen hier
      // 762 an — die Differenz ist genau er. Ihn hier noch einmal
      // abzuziehen kostete 48 dp Inhalt und gewönne nichts.
      constraints: BoxConstraints(
        maxHeight: math.max(
          kSpotSheetMinHeight,
          available - kSpotSheetTopClearance,
        ),
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
                  onPressed: () => _delete(context, ref, spot),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: spot.pending ? 'Eintrag verwerfen' : 'Spot löschen',
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
                        // Wartet noch auf die Übertragung (#267). Der
                        // Eintrag zählt trotzdem überall mit — er ist
                        // passiert; nur ändern lässt er sich nicht.
                        if (find.pending) 'wartet auf Verbindung',
                      ].join(' – ')),
                      // Eigene Einträge lassen sich antippen und
                      // korrigieren (#240); der Stift sagt das. Fremde
                      // zeigen weiter ihren Eintrager und bleiben stumm
                      // — die RLS zieht dieselbe Grenze. Wartende auch:
                      // Zum Ändern bräuchte es eine id, die der Server
                      // noch gar nicht vergeben hat.
                      onTap: find.isOwn && !find.pending
                          ? () => _editFind(context, ref, find)
                          : null,
                      trailing: find.pending
                          ? Icon(Icons.schedule,
                              size: 18, color: Theme.of(context).hintColor)
                          : find.isOwn
                              ? Icon(Icons.edit_outlined,
                                  size: 18,
                                  color: Theme.of(context).hintColor)
                              : MushroomAvatar(
                                  index: find.authorAvatar, size: 22),
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
          // Was „Nichts gefunden" bedeutet, erklärt sich nicht von selbst
          // (#350): „Fund ≠ Eintrag" ist eine Unterscheidung, die die App
          // erfunden hat, und CLAUDE.md führt sie als Fehlerquelle sogar
          // für uns selbst.
          //
          // **Nur am Spot ohne einen einzigen Eintrag**, also genau dort,
          // wo beide Knöpfe zum ersten Mal neu sind. Ein Dauerhinweis
          // wäre ab dem zwanzigsten Mal Lärm — und er stünde in einem
          // Blatt, dessen Höhe wir in #351 gerade begrenzt haben. Am
          // frischen Spot ist das Blatt kurz, die Zeile also gratis.
          if (spot.entriesSorted.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '„Nichts gefunden" hält fest, dass du da warst und nichts '
                'da war — das gehört zur Geschichte eines Spots genauso '
                'wie ein Fund.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ),
          // Ganz unten, nicht oben: Die Fundhistorie ist der Inhalt des
          // Blatts, Saison und Regen sind die Zusatzfrage „ist der Spot
          // dran?". Oben stünden sie über der Antwort, für die man das
          // Blatt geöffnet hat.
          //
          // Die Art vor dem Wetter: Sie gehört zur Fundliste darüber,
          // und ihre Kurve steht ohne Netz sofort da — der Regen kommt
          // je nach Empfang später oder gar nicht.
          // Die Ampel-Vorschau VOR den Fakten-Sektionen: Sie ist die
          // verdichtete Antwort auf „ist der Spot dran?" — existiert
          // aber nur hinter dem Experimentell-Schalter im Profil.
          AmpelSection(
              lat: spot.lat, lon: spot.lng, species: spot.lastFind?.species),
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
