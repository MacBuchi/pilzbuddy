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
                // **Die Zahl selbst ist der Weg zum Rad.** Ein vierter
                // Knopf neben Plus und Minus wäre eine weitere Stelle,
                // die man suchen muss; die Zahl steht ohnehin in der
                // Mitte und ist das, was man ändern will.
                // Nachgeben darf nur die Zahl: Auf 360 dp ist das Feld
                // halb so breit wie das Blatt, und Plus/Minus behalten
                // ihre 48 px (im Test 18 px Überlauf, #596).
                Flexible(
                  child: InkWell(
                  onTap: () async {
                    final chosen =
                        await showCountPicker(context, current: count);
                    if (chosen != null) onChanged(chosen.value);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(count?.toString() ?? '–',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                )),
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

/// Die größte Zahl, die das Rad anbietet.
///
/// **999, nicht unendlich.** Ein Rad ohne Ende lässt sich nicht
/// überblicken, und wer mehr als 999 Pilze in einem Eintrag zählt,
/// schreibt sie von Hand — das Feld daneben nimmt jede Zahl.
const kCountWheelMax = 999;

/// Was der Wähler zurückgibt: [value] `null` heißt „keine Angabe".
///
/// **Abbrechen ist etwas anderes als „keine Angabe".** Der Wähler liefert
/// dafür gar nichts (`null` als Ergebnis des Dialogs), und die Anzahl
/// bleibt, wie sie war. Ohne diesen Unterschied löschte ein versehentlich
/// geöffnetes Rad beim Wegtippen die Zahl.
typedef CountChoice = ({int? value});

/// Anzahl per Rad wählen oder eintippen.
///
/// **Das Rad kam vor die Knöpfe** (#549, Betreiber 2026-09-22: „Anzahl
/// über +- ist nicht so schnell, lieber die Zahlen zum nach unten
/// wischen und alternativ Handeingabe. So kann man auch mal schnell 200
/// Pilze erfassen."). Plus und Minus bleiben: Für zwei Pfifferlinge sind
/// sie der kürzere Weg, und ein Rad für den Schritt von 1 auf 2 wäre
/// eine Zumutung. Der Tipp auf die ZAHL öffnet das Rad.
Future<CountChoice?> showCountPicker(
  BuildContext context, {
  int? current,
}) {
  return showDialog<CountChoice>(
    context: context,
    builder: (context) => _CountPicker(current: current),
  );
}

class _CountPicker extends StatefulWidget {
  const _CountPicker({required this.current});

  final int? current;

  @override
  State<_CountPicker> createState() => _CountPickerState();
}

class _CountPickerState extends State<_CountPicker> {
  late int _value = widget.current ?? 1;
  late final _controller = TextEditingController(text: '$_value');
  late final _wheel =
      FixedExtentScrollController(initialItem: _value - 1);

  /// **Gegen die Rückkopplung.** Rad und Feld schreiben beide `_value`;
  /// ohne diesen Riegel schöbe das Feld das Rad, das Rad das Feld und so
  /// weiter, und der Cursor spränge bei jedem Tastendruck.
  bool _syncing = false;

  @override
  void dispose() {
    _controller.dispose();
    _wheel.dispose();
    super.dispose();
  }

  void _fromWheel(int index) {
    if (_syncing) return;
    _syncing = true;
    setState(() => _value = index + 1);
    _controller.text = '$_value';
    _syncing = false;
  }

  void _fromField(String text) {
    if (_syncing) return;
    final parsed = int.tryParse(text.trim());
    if (parsed == null || parsed < 1) return;
    _syncing = true;
    setState(() => _value = parsed);
    if (parsed <= kCountWheelMax) {
      _wheel.jumpToItem(parsed - 1);
    }
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Anzahl'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              onChanged: _fromField,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Eintippen',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ListWheelScrollView.useDelegate(
                controller: _wheel,
                itemExtent: 40,
                // Ohne Perspektive steht das Rad als Liste da; mit zu
                // viel kippen die Ränder weg und sind nicht mehr zu
                // lesen.
                diameterRatio: 1.6,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: _fromWheel,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: kCountWheelMax,
                  builder: (context, index) => Center(
                    child: Text(
                      '${index + 1}',
                      style: index + 1 == _value
                          ? theme.textTheme.titleLarge
                              ?.copyWith(color: theme.colorScheme.primary)
                          : theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // „Keine Angabe" ist ein gültiges Ergebnis: Die Datenbank kennt
        // eine Anzahl ohne Wert, und 0 lässt sie nicht zu (`count > 0`).
        TextButton(
          onPressed: () => Navigator.of(context).pop((value: null)),
          child: const Text('Keine Angabe'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((value: _value)),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}
