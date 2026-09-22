import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../spots/widgets/species_collector.dart';
import 'spot_position_field.dart';
import '../../../core/app_colors.dart';
import '../../../core/mushroom_species.dart';
import '../../spots/species_suggestions.dart';
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

  /// „Art unbekannt" wurde bewusst gewählt.
  ///
  /// **Pflicht, aber mit Ausweg** (#549, Betreiber 2026-09-22). Bis
  /// 1.182.0 legte ein leeres Artfeld stillschweigend einen artlosen
  /// Fund an — bewusst, für „da stand was, ich weiß nicht was", aber
  /// nicht zu unterscheiden vom Vergessen. Jetzt ist die Art Pflicht
  /// UND der unbekannte Pilz bleibt eintragbar: Wer hier tippt, hat
  /// entschieden. Gespeichert wird danach dasselbe wie vorher, nämlich
  /// ein Fund OHNE Art — „Unbekannt" als Artname stünde sonst im
  /// Artenfilter, in den Vorschlägen und auf dem Marker.
  bool _unknownOk = false;

  /// Beim Speichern fehlte die Art — die Zeile sagt es, statt dass der
  /// Knopf nur nichts tut.
  bool _missingSpecies = false;

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

  /// Die ausgefüllten Zeilen, getrimmt.
  List<SpeciesEntry> get _named => [
        for (final e in _entries)
          if (e.species?.trim() case final name? when name.isNotEmpty)
            (species: name, count: e.count),
      ];

  /// Fragt nach, wenn ein Name nicht in der Artenliste steht.
  ///
  /// **Die Rückfrage bietet den besten Treffer an** (#549). Dieselbe
  /// Maschinerie wie die Vorschlagskarte (#395), nur zum Schluss: Wer
  /// „Steipilz" tippt und das Blatt zuklappt, hat sonst einen Spot mit
  /// einer Art, die es nicht gibt — und die steht danach in seiner
  /// eigenen Artenliste und schlägt sich beim nächsten Mal selbst vor.
  ///
  /// Gibt den zu verwendenden Namen zurück, oder `null` für Abbrechen.
  Future<String?> _confirmUnknown(String typed) async {
    final best = suggestSpecies(typed, widget.ownSpecies, kBekannteArten,
            limit: 3)
        .where((s) => !s.isOwn && s.name.toLowerCase() != typed.toLowerCase())
        .firstOrNull;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Art nicht bekannt'),
        content: Text(best == null
            ? '„$typed" steht nicht in der Artenliste. So eintragen?'
            : '„$typed" steht nicht in der Artenliste. '
                'Meintest du „${best.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zurück'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(typed),
            child: const Text('So eintragen'),
          ),
          if (best != null)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(best.name),
              child: Text('„${best.name}"'),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final named = _named;
    // **Ohne Art kein Spot** — außer, „Art unbekannt" ist gewählt.
    if (named.isEmpty && !_unknownOk) {
      setState(() => _missingSpecies = true);
      return;
    }
    // Drei Zeichen: Ein oder zwei Buchstaben sind ein Verrutscher, kein
    // Pilzname, und stünden danach als eigene Art in der Liste.
    if (named.any((e) => e.species!.length < 3)) {
      setState(() => _missingSpecies = true);
      return;
    }

    final resolved = <SpeciesEntry>[];
    for (final entry in named) {
      var name = entry.species!;
      if (isUnknownSpecies(name)) {
        final decided = await _confirmUnknown(name);
        if (decided == null) return;
        name = decided;
      }
      resolved.add((species: name, count: entry.count));
    }
    if (!mounted) return;

    final note =
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    Navigator.of(context).pop(NewSpotData(
      position: _position,
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      // Datum und Notiz gelten für alle Arten, die hier zusammenkommen.
      // Vorgemerkt: KEIN Fund — auch nicht der artlose. Die Arten werden
      // zur Erwartung; Anzahl und Datum haben dort keine Bedeutung.
      finds: _planned
          ? const []
          // Nichts benannt heißt: „Art unbekannt" war gewählt, und dann
          // ist es GENAU EIN Fund ohne Art. Leere Zusatzzeilen neben
          // benannten fallen weg — sie wären ein zweiter, artloser Fund
          // am selben Spot.
          : [
              for (final entry
                  in resolved.isEmpty ? const [(species: null, count: null)] : resolved)
                NewFind(
                  species: entry.species,
                  count: entry.count,
                  foundOn: _foundOn,
                  note: note,
                ),
            ],
      expectedSpecies: _planned
          ? [for (final entry in resolved) entry.species!]
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
                labelText: 'Name des Spots (optional)',
                hintText: 'z. B. Fichtenhang am Bach',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SpeciesCollector(
              speciesRequired: true,
              ownSpecies: widget.ownSpecies,
              initialSpecies: widget.defaultSpecies,
              onChanged: (entries) {
                _entries = entries;
                // Der Hinweis verschwindet, sobald jemand etwas tut —
                // stehenbleiben würde er wie ein Vorwurf lesen.
                if (_missingSpecies) setState(() => _missingSpecies = false);
              },
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
            // **Der Ausweg zur Pflichtangabe** (#549). Er steht neben
            // der Artzeile und nicht in der Vorschlagskarte: Ein
            // Vorschlag „Unbekannt" wäre eine Art unter Arten und
            // landete als Name in den Daten. Hier ist er eine
            // Entscheidung über die Zeile.
            Row(
              children: [
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Art unbekannt'),
                  tooltip: 'Trägt den Fund ohne Artnamen ein',
                  selected: _unknownOk,
                  onSelected: (value) => setState(() {
                    _unknownOk = value;
                    if (value) _missingSpecies = false;
                  }),
                ),
              ],
            ),
            if (_missingSpecies)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  // Sagt BEIDE Auswege, nicht nur den ersten.
                  'Bitte eine Pilzart mit mindestens drei Zeichen angeben '
                  '— oder „Art unbekannt" wählen.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error),
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
