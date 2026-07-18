import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/find.dart';
import 'species_field.dart';

class NewFindData {
  final String? species;
  final int? count;
  final DateTime foundOn;
  final String? note;

  const NewFindData({this.species, this.count, required this.foundOn, this.note});
}

/// Sheet für den Wiederbesuch: Art und Anzahl sind mit dem letzten Fund
/// vorbelegt (Fallback: global zuletzt benutzte Art), Datum ist heute —
/// zwei Taps genügen.
Future<NewFindData?> showAddFindSheet(
  BuildContext context, {
  Find? lastFind,
  List<String> ownSpecies = const [],
  String? fallbackSpecies,
}) {
  return showModalBottomSheet<NewFindData>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddFindSheet(
      lastFind: lastFind,
      ownSpecies: ownSpecies,
      fallbackSpecies: fallbackSpecies,
    ),
  );
}

class _AddFindSheet extends StatefulWidget {
  const _AddFindSheet({
    this.lastFind,
    this.ownSpecies = const [],
    this.fallbackSpecies,
  });

  final Find? lastFind;
  final List<String> ownSpecies;
  final String? fallbackSpecies;

  @override
  State<_AddFindSheet> createState() => _AddFindSheetState();
}

class _AddFindSheetState extends State<_AddFindSheet> {
  late final TextEditingController _speciesController;
  late final TextEditingController _noteController;
  int? _count;
  DateTime _foundOn = DateTime.now();

  @override
  void initState() {
    super.initState();
    _speciesController = TextEditingController(
        text: widget.lastFind?.species ?? widget.fallbackSpecies ?? '');
    _noteController = TextEditingController();
    _count = widget.lastFind?.count;
  }

  @override
  void dispose() {
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
    Navigator.of(context).pop(NewFindData(
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
                const Text('🍄', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text('Fund eintragen',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
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
