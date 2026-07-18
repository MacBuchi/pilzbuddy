import 'package:flutter/material.dart';

import '../../../core/mushroom_species.dart';
import '../species_suggestions.dart';

/// Pilzart-Eingabe: Chips mit den eigenen Arten (zuletzt benutzt zuerst),
/// darunter Textfeld mit Inline-Vorschlägen aus eigenen + bekannten Arten
/// inklusive Kategorie (Speisepilz/Giftpilz). Freitext bleibt erlaubt —
/// er wird beim Speichern automatisch zur eigenen Art des Users.
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
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() => _showSuggestions = true);
    } else {
      // Verzögert ausblenden, damit ein Tap auf einen Vorschlag noch
      // ankommt, bevor die Liste verschwindet (sonst schluckt der
      // Fokuswechsel den Klick — besonders auf Web).
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted && !_focusNode.hasFocus) {
          setState(() => _showSuggestions = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _select(String name) {
    widget.controller.text = name;
    _focusNode.unfocus();
    setState(() => _showSuggestions = false);
  }

  Widget _groupBadge(SpeciesGroup group) {
    const color = Color(0xFF6D5D4B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        group.label,
        style: const TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller.text.trim().toLowerCase();
    final suggestions = _showSuggestions
        ? suggestSpecies(
            widget.controller.text, widget.ownSpecies, kBekannteArten)
        : const <SpeciesSuggestion>[];
    final onlyExactMatch = suggestions.length == 1 &&
        suggestions.first.name.toLowerCase() == current;

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
        if (suggestions.isNotEmpty && !onlyExactMatch)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in suggestions)
                  // Listener statt onTap: onPointerDown feuert VOR dem
                  // Fokusverlust des Textfelds — der Klick geht nie verloren.
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _select(s.name),
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Text(s.isOwn ? '🍄' : '📖',
                          style: const TextStyle(fontSize: 16)),
                      title: Text(s.name),
                      trailing: s.group == null ? null : _groupBadge(s.group!),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
