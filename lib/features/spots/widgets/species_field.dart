import 'package:flutter/material.dart';

import '../../../core/mushroom_species.dart';
import '../../../core/widgets/mushroom_icon.dart';
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
    this.onChanged,
  });

  final TextEditingController controller;
  final List<String> ownSpecies;

  /// Wird nach jeder Änderung des Feldes gerufen — auch bei Auswahl über
  /// Chip oder Vorschlag und beim Leeren. Für Aufrufer, deren eigene
  /// Oberfläche davon abhängt, ob eine Art dasteht (der Sammler im
  /// Fund-Blatt, #211): Ein Listener auf dem Controller allein bekäme die
  /// Chip-Auswahl mit, aber der Aufrufer müsste ihn selbst verwalten.
  final VoidCallback? onChanged;

  @override
  State<SpeciesField> createState() => _SpeciesFieldState();
}

class _SpeciesFieldState extends State<SpeciesField> {
  final _focusNode = FocusNode();
  bool _showSuggestions = false;

  /// Liegt gerade ein Finger auf einem Vorschlag? (#421)
  ///
  /// Solange das gilt, wird die Liste NICHT ausgeblendet — auch dann
  /// nicht, wenn das Textfeld darüber den Fokus längst verloren hat. Auf
  /// Web nimmt schon das Aufsetzen des Fingers dem Feld den Fokus und
  /// setzt damit die 250 ms unten in Gang; ohne diese Klammer tippt, wer
  /// länger draufbleibt, am Ende ins Leere.
  ///
  /// Kein `setState`: Der Wert steht in keinem Widget, er hält nur das
  /// Ausblenden auf.
  bool _touchingSuggestion = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() => _showSuggestions = true);
    } else {
      _scheduleHide();
    }
  }

  /// Verzögert ausblenden, damit ein Tap auf einen Vorschlag noch
  /// ankommt, bevor die Liste verschwindet (sonst schluckt der
  /// Fokuswechsel den Klick — besonders auf Web).
  void _scheduleHide() {
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || _focusNode.hasFocus || _touchingSuggestion) return;
      setState(() => _showSuggestions = false);
    });
  }

  /// Der Finger ist von der Liste herunter.
  ///
  /// Hat der Tipp die Arena gewonnen, blendet `_select` gleich selbst
  /// aus. War es ein Wisch, muss das Ausblenden nachgeholt werden, das
  /// [_touchingSuggestion] vorhin verhindert hat — sonst bliebe die
  /// Liste auf Web nach jedem Scrollen für immer stehen.
  void _releaseSuggestion() {
    _touchingSuggestion = false;
    if (!_focusNode.hasFocus) _scheduleHide();
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
    widget.onChanged?.call();
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
    final showSuggestionCard = suggestions.isNotEmpty && !onlyExactMatch;
    final synonyms = synonymsOf(widget.controller.text);

    // Das Symbol der gewählten Art, links im Feld (#421-Folgewunsch).
    //
    // **Gezeigt wird es genau dann, wenn die Vorschlagskarte ZU ist** —
    // dieselbe Entscheidung, nicht eine zweite. Während des Tippens
    // („Steinpil") kennt die Liste den Namen noch nicht; ein Symbol
    // trüge dort das Fragezeichen für „unbekannte Art" und fällte damit
    // ein Urteil über eine Eingabe, die noch gar nicht fertig ist. Und
    // es wäre doppelt: Die Zeile direkt darunter trägt ihr Symbol schon.
    //
    // Sobald ausgewählt (oder der volle Name getippt, oder das Feld
    // verlassen) ist die Karte weg — und dann steht dort, was auch auf
    // der Karte stehen wird.
    //
    // Der Name geht KANONISCH hinein: „Totentrompete" und
    // „Herbsttrompete" sind dieselbe Art und sollen gleich aussehen. Der
    // Seed von `forSpecies` kommt aus dem Namen, die Rohform gäbe sonst
    // je nach Schreibweise einen anderen Farbton aus der Palette.
    final selected = widget.controller.text.trim();
    final showSpeciesIcon = selected.isNotEmpty && !showSuggestionCard;

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
          onChanged: (_) {
            setState(() {});
            widget.onChanged?.call();
          },
          decoration: InputDecoration(
            labelText: 'Pilzart (optional)',
            hintText: 'z. B. Steinpilz',
            border: const OutlineInputBorder(),
            // `Center` mit Shrink-Wrap, nicht ein nacktes `Padding`:
            // Der Slot gibt dem Kind `minWidth/minHeight: 48`, und ein
            // `CustomPaint` folgt seinen Constraints statt seiner
            // `size` — der Pilz wurde damit stumm auf 32 px gedehnt,
            // während im Code 26 stand. Gemessen, nicht vermutet.
            prefixIcon: !showSpeciesIcon
                ? null
                : Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: SizedBox.square(
                      dimension: 28,
                      child: MushroomIcon.forSpecies(
                          canonicalSpecies(selected) ?? selected,
                          size: 28),
                    ),
                  ),
            suffixIcon: widget.controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Leeren',
                    onPressed: () {
                      widget.controller.clear();
                      setState(() {});
                      widget.onChanged?.call();
                    },
                  ),
          ),
        ),
        // Zweitnamen der gewählten Art. Wer „Totentrompete" tippt, findet
        // hier wieder, dass er richtig lag — im Feld steht ab der Auswahl
        // „Herbsttrompete", und ohne diese Zeile sähe das nach einem
        // verschluckten Eintrag aus. Nur zeigen, wenn die Vorschlagsliste
        // zu ist: dort steht der Hinweis schon am Treffer selbst.
        if (synonyms.isNotEmpty && (suggestions.isEmpty || onlyExactMatch))
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              'auch: ${synonyms.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (showSuggestionCard)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Geraten ist nicht gefunden. Ohne diese Zeile sähe der
                // Tippfehler-Ausgleich aus wie ein Treffer — die App
                // behauptete also, der Nutzer habe „Riesenbovist" getippt,
                // obwohl da „Bofist" stand.
                if (suggestions.first.isGuess)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Meintest du …?',
                          style: TextStyle(
                              fontSize: 12, fontStyle: FontStyle.italic)),
                    ),
                  ),
                for (final s in suggestions)
                  // **Ausgewählt wird auf `onTap`, nicht auf
                  // `onPointerDown`** (#421).
                  //
                  // Bis 1.127.1 stand hier `onPointerDown: (_) =>
                  // _select(...)`, und das feuert beim AUFSETZEN des
                  // Fingers — vor jeder Gestenentscheidung. Die Liste
                  // sitzt im `SingleChildScrollView` der Blätter; damit
                  // wählte jeder Versuch, die rund 110 Arten
                  // durchzublättern, sofort die Art unter dem ersten
                  // Berührungspunkt aus. Gescrollt wurde weiterhin, nur
                  // war die Liste da schon zu.
                  //
                  // `onTap` fragt die Gesten-Arena und feuert deshalb
                  // erst, wenn aus der Berührung wirklich ein Tipp
                  // geworden ist statt eines Wischens.
                  //
                  // Der Grund für den alten Weg bleibt gültig: Auf Web
                  // nimmt das Aufsetzen dem Textfeld den Fokus, und der
                  // Fokuswechsel blendete die Zeile aus, bevor der Tipp
                  // ankam. Dagegen steht jetzt der Listener — er wählt
                  // nichts mehr aus, er hält die Liste nur offen,
                  // solange ein Finger auf ihr liegt. Das trägt weiter
                  // als vorher: Auch ein langsamer Tipp, der über die
                  // 250 ms hinausgeht, kommt an.
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _touchingSuggestion = true,
                    onPointerUp: (_) => _releaseSuggestion(),
                    onPointerCancel: (_) => _releaseSuggestion(),
                    child: ListTile(
                      onTap: () => _select(s.name),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      // Der Pilz selbst, nicht ein Emoji (#417).
                      //
                      // Hier stand `s.isOwn ? '🍄' : '📖'` — und die
                      // Design-Sprache verbietet genau das: „Never put a
                      // bare 🍄 in a species row — most systems render it
                      // as a red fly agaric, which makes every mushroom
                      // look poisonous." Jede Art sah aus wie ein
                      // Fliegenpilz, ausgerechnet in der Liste, aus der
                      // man die Art wählt.
                      //
                      // `forSpecies` ist für Listenzeilen gebaut: ohne
                      // Boden-Ellipse (die ist auf der Karte die
                      // Besitz-Kennzeichnung) und mit dem Seed aus dem
                      // NAMEN, damit dieselbe Art überall gleich
                      // aussieht.
                      //
                      // Die Unterscheidung eigene/eingebaute Art fällt
                      // damit weg, und das ist entschieden (Betreiber,
                      // 2026-09-08): Eigene stehen ohnehin zuerst, die
                      // Gruppen-Aufschrift rechts sagt das Fachliche, und
                      // gespeichert wird in beiden Fällen dasselbe.
                      leading: MushroomIcon.forSpecies(s.name, size: 28),
                      title: Text(s.name),
                      subtitle: s.matchedSynonym == null
                          ? null
                          : Text('auch: ${s.matchedSynonym}'),
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
