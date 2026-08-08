import 'package:flutter/material.dart';

/// Anzahl-Wähler mit Plus und Minus, rechts daneben optional der
/// Datumsknopf.
///
/// Herausgelöst aus [SpeciesCollector], als das Korrektur-Blatt (#240) als
/// zweiter Nutzer dazukam: Die Regel „unter 1 geht es auf keine Angabe,
/// nicht auf 0" ist eine Eigenschaft der Datenbank (`count > 0`) und
/// gehört an EINE Stelle — dieselbe Lehre wie bei `PasswordField` (#131),
/// wo vier Kopien nebeneinander lagen.
class CountField extends StatelessWidget {
  const CountField({
    super.key,
    required this.count,
    required this.onChanged,
    this.trailing,
  });

  final int? count;
  final ValueChanged<int?> onChanged;

  /// Steht rechts neben der Anzahl — in beiden Blättern der Datumsknopf.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                  // Unter 1 geht es auf „keine Angabe", nicht auf 0:
                  // Die Datenbank lässt 0 nicht zu (`count > 0`), und
                  // „nichts gefunden" ist ein eigener Eintrag.
                  onPressed: count == null
                      ? null
                      : () => onChanged(count! > 1 ? count! - 1 : null),
                  icon: const Icon(Icons.remove),
                ),
                Text(count?.toString() ?? '–',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  onPressed: () => onChanged((count ?? 0) + 1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          Expanded(child: trailing!),
        ],
      ],
    );
  }
}
