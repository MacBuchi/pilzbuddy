import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/spot_repository.dart';
import '../../../models/find.dart';
import '../../../models/spot.dart';
import '../find_offset.dart';
import 'count_field.dart';
import 'species_field.dart';

/// Was im Korrektur-Blatt entschieden wurde: ein geänderter Eintrag oder
/// der Wunsch, ihn zu löschen. Wer das Blatt abbricht, bekommt `null` —
/// wie beim Anlege-Blatt schreibt der Aufrufer, nicht das Blatt.
typedef FindEdit = ({NewFind? changed, bool delete, bool navigate});

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
/// **Die Fundstelle (#373) steht hier nur da, sie lässt sich nicht
/// ändern.** Sie ist eine MESSUNG, keine Angabe: Art, Anzahl, Datum und
/// Notiz hat jemand aufgeschrieben und darf sie korrigieren; einen
/// GPS-Fix zwei Tage später vom Sofa aus richtigzustellen hieße, eine
/// Messung durch eine Erinnerung zu ersetzen. Eine falsche Stelle wird
/// gelöscht und neu eingetragen — dieselbe Antwort wie oben.
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
        .pop((changed: null, delete: true, navigate: false));
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
            // Nur Auskunft, kein Feld: Die Stelle ist eine Messung und
            // wird nicht korrigiert — siehe Kopfkommentar.
            if (findPositionLabel(widget.find, widget.spot)
                case final where?)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 30),
                child: Text('Lag $where.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
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
                    .pop((changed: null, delete: false, navigate: true)),
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
