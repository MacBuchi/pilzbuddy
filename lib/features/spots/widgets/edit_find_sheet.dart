import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo.dart';

import '../../../data/spot_repository.dart';
import '../../../models/find.dart';
import '../../../models/find_position.dart';
import '../../../models/spot.dart';
import '../../map/widgets/mini_map.dart';
import '../find_offset.dart';
import 'count_field.dart';
import 'species_field.dart';

/// Was im Korrektur-Blatt entschieden wurde: ein geänderter Eintrag oder
/// der Wunsch, ihn zu löschen. Wer das Blatt abbricht, bekommt `null` —
/// wie beim Anlege-Blatt schreibt der Aufrufer, nicht das Blatt.
typedef FindEdit = ({
  NewFind? changed,
  /// Die Stelle, die gelten soll — `null` heißt „am Spot".
  /// Getrennt vom [changed], weil `updateFind` sie getrennt nimmt.
  FindPosition? position,
  bool delete,
  bool navigate,
});

/// Blatt zum Korrigieren eines EINZELNEN Eintrags (#240).
///
/// Bis hierher ließ sich ein Vertipper in der Art oder ein falsches Datum
/// nur beheben, indem man den ganzen Spot samt Historie löschte — man
/// vernichtete also mehr, als man retten wollte. Für die geplante
/// Pilzampel ist das mehr als Bequemlichkeit: Sie lernt aus genau dieser
/// Historie, und ein falscher Eintrag verzerrt das Profil dauerhaft
/// (`docs/pilzampel-konzept.md`).
///
/// **Ein eigenes Blatt und kein dritter Modus in `add_find_sheet.dart`:**
/// Das Anlege-Blatt sammelt MEHRERE Arten auf einmal ([SpeciesCollector]),
/// die Korrektur betrifft immer genau eine Zeile. Gemeinsam sind die
/// Bausteine ([SpeciesField], [CountField]), nicht das Blatt.
///
/// Ein Leergang zeigt kein Artfeld: Der Constraint `finds_blank_leer`
/// (Patch 015) verbietet Art und Anzahl dort. Umwandeln zwischen Fund und
/// Leergang gibt es bewusst nicht — das ist Löschen und neu eintragen.
///
/// **Die Fundstelle (#373) lässt sich ändern — aber nur, wenn sie
/// GEWÄHLT wurde** (#466). Die Grenze ist nicht das Feld, sondern seine
/// Herkunft, und `FindPosition.measured` sagt sie:
///
/// - Ein **gemessener** Fix bleibt unantastbar. Ihn zwei Tage später vom
///   Sofa aus richtigzustellen hieße, eine Messung durch eine Erinnerung
///   zu ersetzen. Er steht hier weiter nur als Auskunft da; wer ihn los
///   sein will, löscht den Eintrag und trägt ihn neu ein.
/// - Eine auf der Karte **gewählte** Stelle ist dagegen genau das, was
///   auch der Ort eines Spots ist: eine Angabe, keine Messung. Sie
///   korrigierbar zu machen und den Spot-Ort nicht wäre dieselbe
///   Aussage mit zwei Antworten.
///
/// **Kein „Meine Position" hier**, anders als im Eintragen-Blatt: Ein
/// Fix, den das Gerät JETZT nimmt, misst, wo man jetzt steht — nicht, wo
/// der Fund lag. Er würde aus einer Angabe eine falsche Messung machen,
/// also genau das, was die erste Regel verhindert.
///
/// Zurück zu „am Spot" geht ebenfalls nicht: Das ist das Entfernen einer
/// Aussage und nicht ihre Korrektur, und dafür bleibt es beim Löschen
/// und Neu-Eintragen.
Future<FindEdit?> showEditFindSheet(
  BuildContext context, {
  required Find find,
  required Spot spot,
  List<String> ownSpecies = const [],
}) {
  return showModalBottomSheet<FindEdit>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _EditFindSheet(find: find, spot: spot, ownSpecies: ownSpecies),
  );
}

class _EditFindSheet extends StatefulWidget {
  const _EditFindSheet(
      {required this.find, required this.spot, required this.ownSpecies});

  final Find find;

  /// Der Spot, zu dem der Eintrag gehört — Bezugspunkt für die Angabe,
  /// wo genau er lag (#373).
  final Spot spot;

  final List<String> ownSpecies;

  @override
  State<_EditFindSheet> createState() => _EditFindSheetState();
}

class _EditFindSheetState extends State<_EditFindSheet> {
  late final _speciesController =
      TextEditingController(text: widget.find.species ?? '');
  late final _noteController = TextEditingController(text: widget.find.note ?? '');
  late int? _count = widget.find.count;
  late DateTime _foundOn = widget.find.foundOn;

  /// Die Stelle, die gerade gilt. Vorbelegt mit der bestehenden — auch
  /// bei einer gemessenen, denn `updateFind` schreibt die Spalten seit
  /// #466 mit: Wer sie hier wegließe, löschte sie beim Speichern.
  late FindPosition? _position = widget.find.position;

  /// Darf die Stelle überhaupt angefasst werden? Genau dann, wenn es
  /// eine gibt und sie GEWÄHLT wurde — siehe Kopfkommentar. Ein Fund
  /// ohne eigene Stelle bekommt hier keine: Eine Stelle nachträglich zu
  /// erfinden ist nicht Korrigieren.
  bool get _movable => widget.find.position?.measured == false;

  /// Worauf die Wähl-Karte beim Öffnen schaut — einmal festgehalten,
  /// siehe die Begründung an ihrer Verwendung.
  late final LatLng? _startedAt = widget.find.position == null
      ? null
      : LatLng(widget.find.position!.lat, widget.find.position!.lng);

  void _onPicked(LatLng at) {
    // Bewusst `.picked`: Eine auf der Karte gewählte Stelle hat keinen
    // Messfehler, den man angeben könnte. Eine erfundene Zahl wäre
    // schlimmer als keine — und sie würde aus der Angabe eine Messung
    // machen, die man danach nicht mehr korrigieren dürfte.
    setState(() =>
        _position = FindPosition.picked(lat: at.latitude, lng: at.longitude));
  }

  /// Die Zeile unter der Karte. Sagt dasselbe wie im Eintragen-Blatt —
  /// Herkunft und Abstand zum Spot — und zusätzlich, wie weit man die
  /// Stelle gerade gerückt hat.
  String _positionDetail() {
    final position = _position!;
    final offset = distanceMeters(widget.spot.lat, widget.spot.lng,
        position.lat, position.lng);
    final start = widget.find.position!;
    final moved = distanceMeters(
        start.lat, start.lng, position.lat, position.lng);
    return [
      'Gewählte Stelle',
      '${formatMeters(offset)} vom Spot',
      // Erst ab einem Meter: Beim Schieben wackelt die Mitte um
      // Zentimeter, und „0 m verschoben" wäre eine Zahl, die nur
      // beschäftigt (wie im Spot-Blatt).
      if (moved >= 1) '${formatMeters(moved)} verschoben',
    ].join(' · ');
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _foundOn,
      firstDate: DateTime(2000),
      // Normalerweise heute. Trägt ein Eintrag ein späteres Datum (aus
      // einer GPX-Sicherung kann das kommen), wäre „heute" als Obergrenze
      // kleiner als das Startdatum — der Auswähler wirft dann.
      lastDate: _foundOn.isAfter(now) ? _foundOn : now,
    );
    if (picked != null) setState(() => _foundOn = picked);
  }

  void _save() {
    final note = _noteController.text.trim();
    final species = _speciesController.text.trim();
    Navigator.of(context).pop((
      changed: widget.find.blank
          ? NewFind.blank(
              foundOn: _foundOn, note: note.isEmpty ? null : note)
          : NewFind(
              species: species.isEmpty ? null : species,
              count: _count,
              foundOn: _foundOn,
              note: note.isEmpty ? null : note,
            ),
      // Getrennt vom `NewFind` durchgereicht, wie `updateFind` sie
      // nimmt: Dort ist sie ein eigener, `required` Parameter, damit
      // niemand sie versehentlich weglässt und damit löscht.
      position: _position,
      delete: false,
      navigate: false,
    ));
  }

  /// Löschen fragt nach — wie beim Spot (`spot_detail_sheet.dart`). Ein
  /// Fund ist unwiederbringlich weg, und die Zeile steht in einer Liste,
  /// in der man sich vergreifen kann.
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.find.blank ? 'Eintrag löschen?' : 'Fund löschen?'),
        content: Text(widget.find.blank
            ? 'Der Eintrag verschwindet dauerhaft aus der Historie des Spots.'
            : 'Der Fund verschwindet dauerhaft aus der Historie des Spots. '
                'Der Spot selbst bleibt.'),
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
    if (confirmed != true || !mounted) return;
    Navigator.of(context)
        .pop((changed: null, position: _position, delete: true, navigate: false));
  }

  @override
  Widget build(BuildContext context) {
    final blank = widget.find.blank;
    final dateButton = OutlinedButton.icon(
      onPressed: _pickDate,
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text(DateFormat('d.M.y').format(_foundOn)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (blank)
                  const Icon(Icons.search_off, size: 22)
                else
                  const Text('🍄', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(blank ? 'Leergang bearbeiten' : 'Fund bearbeiten',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            // Eine GEMESSENE Stelle bleibt Auskunft und wird nicht zum
            // Feld — siehe Kopfkommentar. Die Zeile steht bewusst auch
            // dann, wenn es nichts zu sagen gibt (`null`): Dann fehlt sie
            // ganz, statt eine leere Behauptung aufzumachen.
            if (!_movable)
              if (findPositionLabel(widget.find, widget.spot)
                  case final where?)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 30),
                  child: Text('Lag $where.',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            // Eine GEWÄHLTE Stelle bekommt dieselbe Karte, mit der sie
            // gewählt wurde (#373) — Ring auf der bisherigen Stelle,
            // Mitte ist die Wahl. Kein „Meine Position": Ein Fix von
            // jetzt misst, wo man jetzt steht.
            if (_movable) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Fundstelle',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 6),
              MiniMap(
                mode: MiniMapMode.pick,
                // NICHT `_position`: Gäbe man die gemeldete Mitte als
                // `center` zurück, schöbe die Karte sich unter dem
                // Finger selbst nach — dieselbe Falle wie im Spot- und
                // im Eintragen-Blatt.
                center: _startedAt!,
                reference: widget.spot.position,
                onCenterChanged: _onPicked,
              ),
              const SizedBox(height: 6),
              Text(_positionDetail(),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            if (blank)
              dateButton
            else ...[
              SpeciesField(
                controller: _speciesController,
                ownSpecies: widget.ownSpecies,
              ),
              const SizedBox(height: 12),
              CountField(
                count: _count,
                onChanged: (value) => setState(() => _count = value),
                trailing: dateButton,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            if (widget.find.position != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .pop((changed: null, position: _position, delete: false, navigate: true)),
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Zu diesem Fund navigieren'),
              ),
            ],
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: Text(blank ? 'Eintrag löschen' : 'Fund löschen'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
