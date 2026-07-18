import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../spots/widgets/species_field.dart';

/// Ergebnis des Anlege-Formulars.
class NewSpotData {
  final String? name;
  final String? species;
  final int? count;
  final DateTime foundOn;
  final String? note;

  const NewSpotData({
    this.name,
    this.species,
    this.count,
    required this.foundOn,
    this.note,
  });
}

/// Bottom-Sheet zum schnellen Anlegen eines Spots. Alle Felder optional,
/// Datum ist mit heute vorbelegt, Pilzart mit der zuletzt benutzten Art —
/// Fadenkreuz platzieren + „Speichern" reicht.
Future<NewSpotData?> showAddSpotSheet(
  BuildContext context,
  LatLng position, {
  List<String> ownSpecies = const [],
  String? defaultSpecies,
}) {
  return showModalBottomSheet<NewSpotData>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddSpotSheet(
      position: position,
      ownSpecies: ownSpecies,
      defaultSpecies: defaultSpecies,
    ),
  );
}

class _AddSpotSheet extends StatefulWidget {
  const _AddSpotSheet({
    required this.position,
    required this.ownSpecies,
    this.defaultSpecies,
  });

  final LatLng position;
  final List<String> ownSpecies;
  final String? defaultSpecies;

  @override
  State<_AddSpotSheet> createState() => _AddSpotSheetState();
}

class _AddSpotSheetState extends State<_AddSpotSheet> {
  final _nameController = TextEditingController();
  late final TextEditingController _speciesController =
      TextEditingController(text: widget.defaultSpecies ?? '');
  final _noteController = TextEditingController();
  int? _count;
  DateTime _foundOn = DateTime.now();

  @override
  void dispose() {
    _nameController.dispose();
    _speciesController.dispose();
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
    Navigator.of(context).pop(NewSpotData(
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      species: _speciesController.text.trim().isEmpty
          ? null
          : _speciesController.text.trim(),
      count: _count,
      foundOn: _foundOn,
      note:
          _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
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
                const Icon(Icons.add_location_alt, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Text('Neuer Pilz-Spot',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.position.latitude.toStringAsFixed(5)}, '
              '${widget.position.longitude.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
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
            SpeciesField(
              controller: _speciesController,
              ownSpecies: widget.ownSpecies,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Anzahl',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: _count == null || _count == 0
                              ? null
                              : () => setState(() =>
                                  _count = _count! > 1 ? _count! - 1 : null),
                          icon: const Icon(Icons.remove),
                        ),
                        Text(_count?.toString() ?? '–',
                            style: Theme.of(context).textTheme.titleMedium),
                        IconButton(
                          onPressed: () =>
                              setState(() => _count = (_count ?? 0) + 1),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(dateFormat.format(_foundOn)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                  ),
                ),
              ],
            ),
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
          ],
        ),
      ),
    );
  }
}
