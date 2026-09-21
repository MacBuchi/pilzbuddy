import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../spots/widgets/species_collector.dart';
import 'spot_position_field.dart';
import '../../../core/app_colors.dart';
import '../../../data/spot_repository.dart';

/// Ergebnis des Anlege-Formulars.
///
/// [finds] statt einzelner Fund-Felder seit #211: An einem Ort stehen oft
/// mehrere Arten, und wer sie einzeln einträgt, legt sonst fünf Meter
/// weiter den nächsten Spot an.
class NewSpotData {
  final String? name;
  final List<NewFind> finds;

  /// Wo der Spot wirklich hinsoll (#407).
  ///
  /// Bis 1.123.0 gab das Blatt nur Name und Funde zurück, und die
  /// Aufrufer nahmen ihre EIGENE Koordinate — die des Fadenkreuzes.
  /// Damit war jede Verschiebung im Blatt wirkungslos, und genau das
  /// wäre der stille Fehler: gespeichert wird woanders als gezeigt.
  final LatLng position;

  /// Erwartete Arten einer Vormerkung (#499) — dann ist [finds] leer.
  final List<String> expectedSpecies;

  const NewSpotData(
      {this.name,
      required this.finds,
      required this.position,
      this.expectedSpecies = const []});
}

/// Bottom-Sheet zum schnellen Anlegen eines Spots. Alle Felder optional,
/// Datum ist mit heute vorbelegt — Fadenkreuz platzieren + „Speichern"
/// reicht.
///
/// `defaultSpecies` bleibt bewusst leer, wo nichts über die Art bekannt
/// ist: Ein neuer Spot ist meist eine andere Art als der zuletzt gemeldete,
/// und eine falsche Vorbelegung muss jedes Mal gelöscht werden (Issue
/// #155). Gesetzt wird sie nur, wenn die Art aus dem Punktnamen eines
/// Imports hervorgeht.
Future<NewSpotData?> showAddSpotSheet(
  BuildContext context,
  LatLng position, {
  List<String> ownSpecies = const [],
  String? defaultSpecies,
  String? initialName,
  DateTime? initialFoundOn,
}) {
  return showModalBottomSheet<NewSpotData>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddSpotSheet(
      position: position,
      ownSpecies: ownSpecies,
      defaultSpecies: defaultSpecies,
      initialName: initialName,
      initialFoundOn: initialFoundOn,
    ),
  );
}

class _AddSpotSheet extends StatefulWidget {
  const _AddSpotSheet({
    required this.position,
    required this.ownSpecies,
    this.defaultSpecies,
    this.initialName,
    this.initialFoundOn,
  });

  final LatLng position;
  final List<String> ownSpecies;
  final String? defaultSpecies;

  /// Vorbelegter Spot-Name (z. B. Punktname aus einem GPX-Import).
  final String? initialName;

  /// Vorbelegtes Funddatum (z. B. Zeitstempel aus einem GPX-Import).
  final DateTime? initialFoundOn;

  @override
  State<_AddSpotSheet> createState() => _AddSpotSheetState();
}

class _AddSpotSheetState extends State<_AddSpotSheet> {
  /// Die Stelle, die gerade gilt — anfangs das Fadenkreuz.
  late LatLng _position = widget.position;

  late final _nameController =
      TextEditingController(text: widget.initialName ?? '');
  final _noteController = TextEditingController();
  late DateTime _foundOn = widget.initialFoundOn ?? DateTime.now();

  /// Letzter Stand aus dem Sammler, vorbelegt wie dessen erste Zeile.
  late List<SpeciesEntry> _entries = [
    (species: widget.defaultSpecies, count: null),
  ];

  /// „Nur vormerken" (#499): kein Fund, die Arten sind Erwartung.
  bool _planned = false;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _foundOn,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _foundOn = picked);
  }

  void _save() {
    final note =
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    Navigator.of(context).pop(NewSpotData(
      position: _position,
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      // Datum und Notiz gelten für alle Arten, die hier zusammenkommen.
      // Vorgemerkt: KEIN Fund — auch nicht der artlose, den der Sammler
      // sonst meldet. Die Arten werden zur Erwartung; Anzahl und Datum
      // haben dort keine Bedeutung.
      finds: _planned
          ? const []
          : [
              for (final entry in _entries)
                NewFind(
                  species: entry.species,
                  count: entry.count,
                  foundOn: _foundOn,
                  note: note,
                ),
            ],
      expectedSpecies: _planned
          ? [
              for (final entry in _entries)
                if (entry.species case final s? when s.isNotEmpty) s,
            ]
          : const [],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d.M.y');
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
                const Icon(Icons.add_location_alt, color: AppColors.forestGreen),
                const SizedBox(width: 8),
                Text('Neuer Pilz-Spot',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            SpotPositionField(
              initial: widget.position,
              onChanged: (at) => _position = at,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'z. B. Fichtenhang am Bach',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SpeciesCollector(
              ownSpecies: widget.ownSpecies,
              initialSpecies: widget.defaultSpecies,
              onChanged: (entries) => _entries = entries,
              // Ein Datum hat eine Erwartung nicht.
              trailing: _planned
                  ? const SizedBox.shrink()
                  : OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(dateFormat.format(_foundOn)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            // Vormerken (#499): Bis 1.158.0 legte jeder neue Spot einen
            // Fund an — notfalls ohne Art, mit heutigem Datum. Wer eine
            // Stelle nur für später notiert, hatte keinen Weg. Der
            // Schalter steht UNTER den Arten: Über ihnen schöbe er die
            // Vorschlagsliste unter den Falz (im Flow-Test gemessen).
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _planned,
              onChanged: (value) => setState(() => _planned = value),
              title: const Text('Nur vormerken, noch kein Fund'),
              subtitle: Text(_planned
                  ? 'Die Arten oben sind Erwartung, kein Fund — die '
                      'Ampel spricht trotzdem für sie.'
                  : 'Aus: Der Spot bekommt gleich einen Fund.'),
            ),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }
}
