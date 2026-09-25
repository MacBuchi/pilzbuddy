import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../coach/coach.dart';
import '../../help/tab_tours.dart';
import '../../../core/app_colors.dart';
import '../../../core/errors.dart';
import '../../../core/geo.dart' show formatMeters;
import '../../../core/mushroom_species.dart';
import '../../../core/photo_providers.dart';
import '../../../core/species_edibility.dart';
import '../../../core/widgets/mushroom_avatar.dart';
import '../../../core/widgets/mushroom_icon.dart';
import '../../friends/buddy_alias.dart';
import '../../profile/profile_providers.dart';
import '../../../models/find.dart';
import '../../../models/spot.dart';
import '../find_offset.dart';
import '../spot_navigation.dart';
import '../spot_providers.dart';
import 'add_find_sheet.dart';
import 'edit_find_sheet.dart';
import 'edit_spot_sheet.dart';
import 'find_photo_strip.dart';
import 'ampel_section.dart';
import '../../ampel/ampel_scan.dart' show scanSpeciesOf;
import 'species_season_section.dart';
import 'spot_forest_section.dart';
import 'spot_rain_section.dart';
import '../../../core/read_after_write.dart';
import '../../inat/inat_report_flow.dart';
import '../../../data/find_report_repository.dart';
import '../../inat/inat_find_status.dart';
import '../../inat/inat_providers.dart';

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

  /// Die BEKANNTEN Arten des Spots, je einmal, in der Reihenfolge von
  /// [scanSpeciesOf] — dieselbe Liste wie Ampel und Saison. Eigene
  /// Freitext-Arten fallen weg: Für sie gibt es keine Seite.
  List<String> _knownSpeciesOf(Spot spot) {
    final seen = <String>{};
    return [
      for (final raw in scanSpeciesOf(spot))
        if (knownSpeciesFor(raw) case final known?)
          if (seen.add(known.name)) known.name,
    ];
  }

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
    // Leergänge haben nichts zu melden — und brauchen deshalb auch den
    // Blick in Konto und Baumartenkarte nicht.
    final inat = blank ? null : await inatOfferFor(ref, spot);
    if (!context.mounted) return;
    final result = await showAddFindSheet(
      context,
      spotAt: spot.position,
      // Der letzte EIGENE Fund, nicht der letzte überhaupt: Am
      // Freundes-Spot soll nicht dessen Art im Formular vorstehen.
      lastFind: spot.lastOwnFind,
      ownSpecies: ownSpecies,
      // Der erste Fund an einer Vormerkung: die erwartete Art steht
      // schon da (#499).
      fallbackSpecies:
          spot.expectedSpecies.firstOrNull ?? ownSpecies.firstOrNull,
      blank: blank,
      // Ein wartender Spot schickt seinen Fund sicher in den Korb —
      // dort gäbe es für das Foto keinen Weg, also gar nicht anbieten.
      pickPhoto: spot.pending ? null : ref.read(photoPickerProvider),
      preparePhoto: spot.pending ? null : ref.read(photoPreparerProvider),
      inat: inat,
    );
    if (result == null) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (:fresh, :ids) = await ref
          .read(mySpotsProvider.notifier)
          .addFinds(spotId: spot.id, finds: result.finds);
      final photo = result.photo;
      if (photo != null) {
        await shareFreshFindPhoto(ref, messenger, ids: ids, photo: photo);
      }
      if (result.inat case final draft?) {
        await reportFreshFindToInat(ref, messenger,
            ids: ids, find: result.finds.first, spot: spot, draft: draft);
      }
      if (photo != null || result.inat != null) return;
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
      BuildContext context, WidgetRef ref, Find find, Spot spot) async {
    final result = await showEditFindSheet(
      context,
      find: find,
      spot: spot,
      ownSpecies: ref.read(ownSpeciesProvider),
    );
    if (result == null || !context.mounted) return;
    // Das Blatt entscheidet, der Aufrufer führt aus — wie beim Löschen.
    if (result.navigate) {
      if (find.position case final position?) {
        await _navigateToPoint(context, position.lat, position.lng,
            '${spot.displayName} – ${find.label}');
      }
      return;
    }
    try {
      if (result.delete) {
        await ref.read(mySpotsProvider.notifier).deleteFind(find.id);
      } else if (result.changed case final changed?) {
        final moved = result.position != null &&
            result.position != find.position;
        // Eine verlegte Fundstelle fragt, ob Spot und alle Fundstellen
        // mitgehen (#475) — Vorgabe Nein. Vielleicht war der Spot von
        // Anfang an falsch, und diese Stelle ist die richtige.
        final withSpot = moved && await _askMoveFindWithSpot(context);
        if (moved && !context.mounted) return;
        if (withSpot) {
          await ref.read(mySpotsProvider.notifier).moveFindWithSpot(
                spot: spot,
                findId: find.id,
                find: changed,
                lat: result.position!.lat,
                lng: result.position!.lng,
              );
        } else {
          await ref
              .read(mySpotsProvider.notifier)
              .updateFind(
                  findId: find.id, find: changed, position: result.position);
        }
      }
    } catch (e, stackTrace) {
      if (context.mounted) {
        _showError(context, result.delete ? 'Fund löschen' : 'Fund ändern', e,
            stackTrace);
      }
    }
  }

  /// Übergibt den Spot an eine Navi-App (#367).
  ///
  /// Gemeldet wird nur, was der Nutzer sonst nicht sieht: Klappt der
  /// App-Wähler auf, steht die andere App im Vordergrund und eine
  /// SnackBar hinter ihr wäre für niemanden. Die beiden Rückfälle
  /// dagegen sehen ohne Meldung aus wie ein Knopf, der nichts tut.
  Future<void> _navigateTo(BuildContext context, Spot spot) =>
      _navigateToPoint(context, spot.lat, spot.lng, spot.displayName);

  /// Derselbe Weg für den Spot und für einen einzelnen Fund (#373).
  ///
  /// Der Knopf im Blattkopf bleibt beim SPOT: Ihn heimlich auf den
  /// jüngsten Fund zu richten hieße, dass ein Knopf mit dem Spot-Namen
  /// woandershin führt — und sein Ziel mit jedem neuen Fund wanderte.
  Future<void> _navigateToPoint(
          BuildContext context, double lat, double lng, String label) =>
      navigateToPoint(context, lat: lat, lng: lng, label: label);

  /// Öffnet das Korrektur-Blatt für Name und Stelle (#466).
  ///
  /// Nur für EIGENE, bereits übertragene Spots verdrahtet. Beides ist
  /// eine Grenze, die woanders gezogen ist, und die Oberfläche darf
  /// nicht anbieten, was dahinter scheitert: `spots_owner_all` lässt nur
  /// den Besitzer schreiben, und einem Spot, der noch im Ausgangskorb
  /// wartet, fehlt die Server-id, auf die das Update zeigen müsste.
  Future<void> _edit(
      BuildContext context, WidgetRef ref, Spot spot) async {
    final edited = await showEditSpotSheet(
      context,
      name: spot.name,
      position: spot.position,
      // Nur eine Vormerkung bietet die erwarteten Arten an (#499).
      expectedSpecies: spot.isPlanned ? spot.expectedSpecies : null,
      ownSpecies: ref.read(ownSpeciesProvider),
    );
    if (edited == null || !context.mounted) return;
    // Der Spot rückt, und es gibt Fundstellen mit eigener Position:
    // mitnehmen oder nicht (#475)? Ohne solche Stellen gibt es nichts
    // zu fragen — dann ist „nur den Spot" dasselbe wie „alles".
    final moved = edited.position != spot.position;
    final hasPositions = spot.finds.any((f) => f.position != null);
    bool? withFinds = false;
    if (moved && hasPositions) {
      withFinds = await _askMoveSpotWithFinds(context, spot);
      if (withFinds == null || !context.mounted) return;
    }
    try {
      final notifier = ref.read(mySpotsProvider.notifier);
      final fresh = withFinds
          ? await notifier.moveSpotWithFinds(
              spotId: spot.id,
              name: edited.name,
              lat: edited.position.latitude,
              lng: edited.position.longitude,
            )
          : await notifier.editSpot(
              spotId: spot.id,
              name: edited.name,
              lat: edited.position.latitude,
              lng: edited.position.longitude,
              // Nur der Spot rückt: Die Fundstellen stehen neu zu ihm,
              // eine frühere Bestätigung gilt nicht mehr.
              resetOffsetConfirmation: moved,
              expectedSpecies: edited.expectedSpecies,
            );
      // Wie beim Eintragen: Die Quittung ist normalerweise das Blatt
      // selbst — Name und Entfernungen stehen danach neu da. Nur wenn
      // die Liste nicht neu laden konnte, braucht es den Satz, sonst
      // sähe die unveränderte Anzeige nach einem Fehlschlag aus.
      if (!fresh && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Spot geändert$staleAfterWriteHint'),
        ));
      }
    } catch (e, stackTrace) {
      if (context.mounted) _showError(context, 'Spot ändern', e, stackTrace);
    }
  }

  /// „Fundstellen mitnehmen?" beim Verlegen des Spots (#475). `null`
  /// heißt abgebrochen — dann wird gar nichts geschrieben.
  Future<bool?> _askMoveSpotWithFinds(BuildContext context, Spot spot) {
    final own = spot.finds.where((f) => f.isOwn && f.position != null).length;
    final foreign = spot.finds.where((f) => !f.isOwn && f.position != null).length;
    final measured = spot.finds
        .any((f) => f.isOwn && (f.position?.measured ?? false));
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fundstellen mitnehmen?'),
        content: Text([
          '$own ${own == 1 ? 'Fundstelle hat' : 'Fundstellen haben'} eine '
              'eigene Position. Mitnehmen heißt: Sie gelten danach am '
              'neuen Spot, ihre eigene Position entfällt.',
          if (measured)
            'Darunter sind gemessene Positionen — die gehen dabei verloren.',
          if (foreign > 0)
            '$foreign ${foreign == 1 ? 'Fundstelle' : 'Fundstellen'} von '
                'Buddys ${foreign == 1 ? 'bleibt' : 'bleiben'} in jedem '
                'Fall, wo ${foreign == 1 ? 'sie ist' : 'sie sind'}.',
        ].join(' ')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nur den Spot'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Spot und alle Fundstellen'),
          ),
        ],
      ),
    );
  }

  /// „Alle Fundstellen und den Spot mitverschieben?" beim Verlegen einer
  /// Fundstelle (#475). Vorgabe Nein — Wegwischen heißt Nein.
  Future<bool> _askMoveFindWithSpot(BuildContext context) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spot mitverschieben?'),
        content: const Text(
            'Nur diese Fundstelle rückt an die neue Position. Oder soll '
            'der Spot samt allen deinen Fundstellen dorthin — falls der '
            'Spot von Anfang an falsch lag? Dann gelten alle deine '
            'Fundstellen am Spot; Fundstellen von Buddys bleiben, wo sie '
            'sind.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nur diese Fundstelle'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Spot und alle Fundstellen'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// „So gewollt" (#475): nimmt die Warnung vom Spot.
  Future<void> _confirmOffset(
      BuildContext context, WidgetRef ref, Spot spot) async {
    try {
      await ref.read(mySpotsProvider.notifier).confirmOffset(spot.id);
    } catch (e, stackTrace) {
      if (context.mounted) {
        _showError(context, 'Fundstellen bestätigen', e, stackTrace);
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
    // Die eigenen Meldungen an iNaturalist (#553). Ohne Application ID
    // leer, ohne dass etwas abgefragt wird (`inatAvailableProvider`).
    final inatReports = ref.watch(myFindReportsProvider).valueOrNull ??
        const <String, FindReport>{};
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
                unknown: isUnknownSpecies(spot.lastFind?.species),
                group: groupFor(spot.lastFind?.species),
                species: spot.lastFind?.species,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(spot.displayName,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                onPressed: () => _navigateTo(context, spot),
                icon: const Icon(Icons.directions_outlined),
                tooltip: 'In Navi-App öffnen',
              ),
              // Ein wartender Spot lässt sich nicht ändern — ihm fehlt
              // die Server-id (#267). Der Löschen-Knopf daneben kann es
              // trotzdem: Der nimmt dann den Auftrag zurück.
              if (spot.isOwn && !spot.pending)
                CoachAnchor(
                  id: SpotsCoach.sheetEdit,
                  child: IconButton(
                    onPressed: () => _edit(context, ref, spot),
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    tooltip: 'Spot bearbeiten',
                  ),
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
                      : 'Gefunden von ${ref.watch(buddyNamesViewProvider).of(spot.ownerId, spot.ownerUsername, fallback: 'einem Buddy')}',
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
          // **Der Weg zur Artseite** (seit 1.168.0). Hier steht jemand
          // mit dem Pilz — und Einstufung, Verwechslungspartner und
          // Bildpaare standen bis dahin nur im Reiter, den man aufsuchen
          // musste. Ein Chip je bekannter Art des Spots; die giftigen
          // tragen ihr Zeichen. Das Blatt schließt vorher: Es liegt über
          // dem Karten-Zweig, und die Artseite gehört in einen anderen.
          if (_knownSpeciesOf(spot) case final names when names.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final name in names)
                    ActionChip(
                      key: ValueKey('species-chip-$name'),
                      visualDensity: VisualDensity.compact,
                      avatar: (edibilityFor(name)?.level.warnsInList ?? false)
                          ? Icon(Icons.warning_amber_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.error)
                          : const Icon(Icons.menu_book_outlined, size: 16),
                      label: Text(name),
                      tooltip: 'Zur Art: $name',
                      onPressed: () {
                        // Router VOR dem Schließen greifen — danach ist
                        // der Kontext des Blatts nicht mehr eingehängt.
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.go('/pilze/${Uri.encodeComponent(name)}');
                      },
                    ),
                ],
              ),
            ),
          // Vorgemerkt (#499): noch kein Eintrag. Die erwarteten Arten
          // stehen hier, weil sie sonst nirgends stünden — der Marker
          // trägt keine Art, die Liste unten ist leer.
          if (spot.isOwn && spot.isPlanned)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.bookmark_border,
                      size: 18, color: Theme.of(context).hintColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      spot.expectedSpecies.isEmpty
                          ? 'Vorgemerkt — noch kein Fund.'
                          : 'Vorgemerkt für ${spot.expectedSpecies.join(', ')} '
                              '— noch kein Fund.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          // Fundstellen weit vom Spot (#475): „!" im Kreis, solange der
          // Besitzer es nicht bestätigt hat; danach dieselbe Zeile als
          // Auskunft. Am Buddy-Spot nur die Auskunft — bestätigen kann
          // dort niemand, und ein Knopf, der scheitert, ist keiner.
          if (driftingFinds(spot) case final drifting when drifting.isNotEmpty)
            _DriftLine(
              spot: spot,
              drifting: drifting,
              dateFormat: dateFormat,
              onConfirm: spot.isOwn && !spot.pending && spotDriftUnconfirmed(spot)
                  ? () => _confirmOffset(context, ref, spot)
                  : null,
            ),
          // Fundfotos an diesem Spot (#532) — eigene und die der Buddys,
          // solange sie laufen. Über der Liste, weil ein Bild zeigt, was
          // die Zeile darunter nur benennt. Leer heißt unsichtbar.
          FindPhotoStrip(spotId: spot.id),
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
                      key: ValueKey('find-row-${find.id}'),
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
                        // Wo genau dieser Eintrag lag (#373) — der
                        // Unterschied zwischen „drei Funde an einem
                        // Spot" und „drei Funde, und ich weiß welcher
                        // wo war". Fehlt die Stelle, fehlt auch das
                        // Element: Die Zeile sieht dann aus wie immer.
                        ?findPositionLabel(find, spot),
                        if (find.note != null && find.note!.isNotEmpty)
                          find.note!,
                        // Fremde Funde nennen ihren Eintrager (#190) —
                        // unmarkiert heißt: meiner.
                        if (!find.isOwn)
                          'von ${ref.watch(buddyNamesViewProvider).of(find.authorId, find.authorUsername, fallback: 'einem Buddy')}',
                        // Wartet noch auf die Übertragung (#267). Der
                        // Eintrag zählt trotzdem überall mit — er ist
                        // passiert; nur ändern lässt er sich nicht.
                        if (find.pending) 'wartet auf Verbindung',
                        // Der Stand einer Meldung an iNaturalist (#553).
                        // Nur eigene Meldungen — die Policy gibt keine
                        // fremden heraus.
                        ?inatStatusLine(inatReports[find.id]),
                      ].join(' – ')),
                      // Eigene Einträge lassen sich antippen und
                      // korrigieren (#240); der Stift sagt das. Fremde
                      // zeigen weiter ihren Eintrager und bleiben stumm
                      // — die RLS zieht dieselbe Grenze. Wartende auch:
                      // Zum Ändern bräuchte es eine id, die der Server
                      // noch gar nicht vergeben hat.
                      onTap: find.isOwn && !find.pending
                          ? () => _editFind(context, ref, find, spot)
                          : null,
                      trailing: find.pending
                          ? Icon(Icons.schedule,
                              size: 18, color: Theme.of(context).hintColor)
                          : find.isOwn
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Foto teilen (#532) — nur am eigenen
                                    // Fund, nicht am Leergang (der hat
                                    // nichts zu zeigen) und nicht am
                                    // wartenden (der hat keine id, an
                                    // der ein Foto hängen könnte).
                                    InatFindButton(find: find, spot: spot),
                                    if (!find.blank)
                                      IconButton(
                                        key: shareFindPhotoKey(find.id),
                                        tooltip: 'Foto teilen',
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(Icons.add_a_photo_outlined,
                                            size: 20,
                                            color: Theme.of(context).hintColor),
                                        onPressed: () =>
                                            shareFindPhoto(context, ref, find),
                                      ),
                                    Icon(Icons.edit_outlined,
                                        size: 18,
                                        color: Theme.of(context).hintColor),
                                  ],
                                )
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
                  'Diesen Spot nicht mit Buddys teilen – auch wenn das Teilen global an ist.'),
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
          CoachAnchor(
            id: SpotsCoach.sheetEntries,
            child: Row(
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
          // **Dieselbe Artenliste wie der Banner-Nachlauf**
          // (`scanSpeciesOf`): Sonst könnte das Banner wegen einer Art
          // anschlagen, über die das Blatt darunter schweigt.
          AmpelSection(
              lat: spot.lat, lon: spot.lng, species: scanSpeciesOf(spot)),
          // Dieselbe Artenliste wie die Ampel darüber — sonst sagte das
          // Blatt über dieselbe Fundstelle zwei verschiedene Dinge.
          SpeciesSeasonSection(species: scanSpeciesOf(spot)),
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

/// Die Zeile zu Fundstellen weit vom Spot (#475).
///
/// Unbestätigt: „!" im Kreis in Orange — dasselbe Zeichen wie das
/// Abzeichen am Marker — und der Knopf „So gewollt".
/// Bestätigt: Info-Symbol, derselbe Text mit „bestätigt" — die Auskunft
/// bleibt, nur der Vorwurf geht. Der Text nennt jede Stelle mit Datum,
/// Eintrag und Versatz, weiteste zuerst; die Zahl 100 m ist
/// `kFindFixMaxOffsetM`, dieselbe Grenze wie beim Eintragen.
class _DriftLine extends StatelessWidget {
  const _DriftLine({
    required this.spot,
    required this.drifting,
    required this.dateFormat,
    required this.onConfirm,
  });

  final Spot spot;
  final List<Find> drifting;
  final DateFormat dateFormat;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unconfirmed = spotDriftUnconfirmed(spot);
    final n = drifting.length;
    final details = [
      for (final find in drifting)
        '${dateFormat.format(find.foundOn)} ${find.label} '
            '${findPositionLabel(find, spot)}',
    ].join(', ');
    final text = '$n ${n == 1 ? 'Fundstelle liegt' : 'Fundstellen liegen'} '
        'über ${formatMeters(kFindFixMaxOffsetM)} vom Spot entfernt: $details'
        '${unconfirmed ? '' : ' — bestätigt'}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                unconfirmed ? Icons.error_outline : Icons.info_outline,
                size: 18,
                color: unconfirmed ? AppColors.warningAmber : theme.hintColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          if (onConfirm != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onConfirm,
                child: const Text('So gewollt'),
              ),
            ),
        ],
      ),
    );
  }
}
