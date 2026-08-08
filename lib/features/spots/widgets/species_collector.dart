import 'package:flutter/material.dart';

import 'count_field.dart';
import 'species_field.dart';

/// Eine erfasste Zeile: Art und Anzahl, beide für sich optional.
typedef SpeciesEntry = ({String? species, int? count});

/// Artfeld + Anzahl + „weitere Art"-Sammler (#211).
///
/// An einem Spot stehen oft mehrere Arten. Vorher hieß das: Blatt
/// schließen, Knopf drücken, Blatt neu ausfüllen — für jede Art. Hier legt
/// „weitere Art" die ausgefüllte Zeile als Chip ab und macht das Feld frei.
///
/// **Ein** [SpeciesField] und nicht eines je Zeile: Das Feld bringt seine
/// eigene Chip-Reihe der zuletzt benutzten Arten, die Synonymzeile und die
/// Vorschlagskarte mit — drei Instanzen untereinander zeigten die
/// Artenchips dreifach und könnten drei Vorschlagslisten gleichzeitig
/// aufklappen.
///
/// Meldet über [onChanged] **alle** Zeilen: die abgelegten und die gerade
/// ausgefüllte. Wer nur eine Art einträgt, muss „weitere Art" also nie
/// anfassen. Der Elternteil hält die letzte Meldung und baut daraus beim
/// Speichern seine Einträge.
class SpeciesCollector extends StatefulWidget {
  const SpeciesCollector({
    super.key,
    required this.ownSpecies,
    required this.onChanged,
    required this.trailing,
    this.initialSpecies,
    this.initialCount,
  });

  final List<String> ownSpecies;
  final ValueChanged<List<SpeciesEntry>> onChanged;

  /// Steht in der Zeile rechts neben der Anzahl — in beiden Blättern der
  /// Datumsknopf. Als Slot, weil das Datum für alle Zeilen gemeinsam gilt
  /// und deshalb dem Elternteil gehört.
  final Widget trailing;

  final String? initialSpecies;
  final int? initialCount;

  @override
  State<SpeciesCollector> createState() => _SpeciesCollectorState();
}

class _SpeciesCollectorState extends State<SpeciesCollector> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialSpecies ?? '');
  late int? _count = widget.initialCount;
  final _collected = <SpeciesEntry>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _species => _controller.text.trim();

  /// Abgelegte Zeilen plus die gerade ausgefüllte.
  ///
  /// Die offene Zeile zählt mit, sobald etwas drinsteht — und wenn nichts
  /// abgelegt ist, auch leer: Ein Fund ganz ohne Angaben bleibt erlaubt
  /// („da stand was, ich weiß nicht was"). Bei bereits abgelegten Arten
  /// hinge daran sonst ein leerer Zusatz-Fund.
  List<SpeciesEntry> get _all => [
        ..._collected,
        if (_species.isNotEmpty || _count != null || _collected.isEmpty)
          (species: _species.isEmpty ? null : _species, count: _count),
      ];

  void _report() => widget.onChanged(_all);

  void _collect() {
    setState(() {
      _collected.add((species: _species, count: _count));
      _controller.clear();
      _count = null;
    });
    _report();
  }

  void _setCount(int? value) {
    setState(() => _count = value);
    _report();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_collected.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: -6,
            children: [
              for (final (index, entry) in _collected.indexed)
                InputChip(
                  label: Text(entry.count == null
                      ? entry.species ?? 'Fund'
                      : '${entry.species ?? 'Fund'}, ${entry.count}'),
                  onDeleted: () {
                    setState(() => _collected.removeAt(index));
                    _report();
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        SpeciesField(
          controller: _controller,
          ownSpecies: widget.ownSpecies,
          onChanged: () {
            setState(() {});
            _report();
          },
        ),
        const SizedBox(height: 12),
        CountField(
          count: _count,
          onChanged: _setCount,
          trailing: widget.trailing,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          // Ohne Art gibt es nichts abzulegen — die Chips unterscheiden
          // sich nur über den Namen.
          onPressed: _species.isEmpty ? null : _collect,
          icon: const Icon(Icons.add),
          label: const Text('weitere Art'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }
}
