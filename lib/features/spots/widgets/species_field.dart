import 'package:flutter/material.dart';

import '../../../core/mushroom_species.dart';
import '../species_suggestions.dart';

/// Pilzart-Eingabe: Chips mit den eigenen Arten (zuletzt benutzt zuerst),
/// darunter Textfeld mit Inline-Vorschlägen aus eigenen + bekannten Arten.
/// Freitext bleibt erlaubt — er wird beim Speichern automatisch zur
/// eigenen Art des Users.
class SpeciesField extends StatefulWidget {
  const SpeciesField({
    super.key,
    required this.controller,
    this.ownSpecies = const [],
  });

  final TextEditingController controller;
  final List<String> ownSpecies;

  @override
  State<SpeciesField> createState() => _SpeciesFieldState();
}

class _SpeciesFieldState extends State<SpeciesField> {
  final _focusNode = FocusNode();
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _showSuggestions = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _select(String name) {
    widget.controller.text = name;
    _focusNode.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller.text.trim().toLowerCase();
    final suggestions = _showSuggestions
        ? suggestSpecies(widget.controller.text, widget.ownSpecies,
            kBekannteArten)
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.ownSpecies.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: -6,
            children: [
              for (final name in widget.ownSpecies.take(8))
                ChoiceChip(
                  label: Text(name),
                  selected: current == name.toLowerCase(),
                  onSelected: (_) => _select(name),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Pilzart (optional)',
            hintText: 'z. B. Steinpilz',
            border: const OutlineInputBorder(),
            suffixIcon: widget.controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Leeren',
                    onPressed: () {
                      widget.controller.clear();
                      setState(() {});
                    },
                  ),
          ),
        ),
        if (suggestions.isNotEmpty &&
            !(suggestions.length == 1 &&
                suggestions.first.toLowerCase() == current))
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final name in suggestions)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Text(
                      widget.ownSpecies
                              .any((o) => o.toLowerCase() == name.toLowerCase())
                          ? '🍄'
                          : '📖',
                      style: const TextStyle(fontSize: 16),
                    ),
                    title: Text(name),
                    onTap: () => _select(name),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
