import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/spot_repository.dart';
import '../../../models/find.dart';
import '../../../models/find_position.dart';
import 'find_position_field.dart';
import 'species_collector.dart';

/// Sheet für den Wiederbesuch: Art und Anzahl sind mit dem letzten Fund
/// vorbelegt (Fallback: global zuletzt benutzte Art), Datum ist heute —
/// zwei Taps genügen. Mehrere Arten sammelt [SpeciesCollector] ein.
///
/// Mit [blank] wird daraus das Blatt für „Nichts gefunden" (#211): kein
/// Artfeld, keine Anzahl, kein Sammler — nur Datum und Notiz. Der Leergang
/// ist eine Aussage über den ORT, nicht über eine Art; die Datenbank hält
/// das mit einem Constraint fest (`finds_blank_leer`, Patch 015).
Future<List<NewFind>?> showAddFindSheet(
  BuildContext context, {
  required LatLng spotAt,
  Find? lastFind,
  List<String> ownSpecies = const [],
  String? fallbackSpecies,
  bool blank = false,
}) {
  return showModalBottomSheet<List<NewFind>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddFindSheet(
      spotAt: spotAt,
      lastFind: lastFind,
      ownSpecies: ownSpecies,
      fallbackSpecies: fallbackSpecies,
      blank: blank,
    ),
  );
}

class _AddFindSheet extends StatefulWidget {
  const _AddFindSheet({
    required this.spotAt,
    this.lastFind,
    this.ownSpecies = const [],
    this.fallbackSpecies,
    this.blank = false,
  });

  /// Der Ort des Spots — Bezugspunkt der Fundstellen-Wahl (#373). Bis
  /// dahin kannte das Blatt den Spot gar nicht.
  final LatLng spotAt;

  final Find? lastFind;
  final List<String> ownSpecies;
  final String? fallbackSpecies;
  final bool blank;

  @override
  State<_AddFindSheet> createState() => _AddFindSheetState();
}

class _AddFindSheetState extends State<_AddFindSheet> {
  final _noteController = TextEditingController();
  DateTime _foundOn = DateTime.now();

  /// Der letzte Stand aus dem Sammler. Vorbelegt mit dem, was der Sammler
  /// selbst als erste Zeile zeigt — sonst ginge ein „Speichern" ohne jede
  /// Berührung des Feldes mit leeren Händen aus.
  late List<SpeciesEntry> _entries = [
    (species: widget.lastFind?.species ?? widget.fallbackSpecies,
     count: widget.lastFind?.count),
  ];

  @override
  void dispose() {
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

  /// `null` heißt „am Spot" — der Normalfall und das Verhalten von vor
  /// #373.
  FindPosition? _position;

  void _save() {
    final note =
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    // Datum, Notiz und Fundstelle gelten für alle Zeilen. Jede Zeile
    // bekommt sie eingetragen und bleibt damit für sich vollständig —
    // darauf bauen GPX-Export und die Sicht der Buddys auf. Bei der
    // Stelle ist das auch inhaltlich richtig: Wer drei Arten auf einmal
    // einträgt, stand dabei an EINEM Ort.
    Navigator.of(context).pop(widget.blank
        ? [NewFind.blank(foundOn: _foundOn, note: note, position: _position)]
        : [
            for (final entry in _entries)
              NewFind(
                species: entry.species,
                count: entry.count,
                foundOn: _foundOn,
                note: note,
                position: _position,
              ),
          ]);
  }

  @override
  Widget build(BuildContext context) {
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
                if (widget.blank)
                  const Icon(Icons.search_off, size: 22)
                else
                  const Text('🍄', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(widget.blank ? 'Nichts gefunden' : 'Fund eintragen',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            if (widget.blank) ...[
              const SizedBox(height: 8),
              Text(
                'Hält fest, dass du hier warst und nichts stand. Zählt nicht '
                'als Fund — hilft aber, die Vorhersage zu lernen.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            if (widget.blank)
              dateButton
            else
              SpeciesCollector(
                ownSpecies: widget.ownSpecies,
                initialSpecies:
                    widget.lastFind?.species ?? widget.fallbackSpecies,
                initialCount: widget.lastFind?.count,
                trailing: dateButton,
                onChanged: (entries) => _entries = entries,
              ),
            const SizedBox(height: 12),
            // Auch im Leergang-Modus: „Ich war hier und da stand nichts"
            // ist die Aussage, die am stärksten an einem Ort hängt —
            // `finds_blank_leer` verbietet Art und Anzahl, nicht den Ort.
            FindPositionField(
              spotAt: widget.spotAt,
              onChanged: (position) => _position = position,
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
