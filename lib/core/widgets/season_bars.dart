// Zwölf Balken, einer je Monat, der laufende hervorgehoben.
//
// Bis 1.152.0 lag das als `_Bars` im Saison-Abschnitt des Spot-Blatts.
// Seit der Reiter „Pilze" dieselbe Kurve je Art in klein zeigt, ist es
// EIN Widget mit zwei Größen — zwei Zeichner hätten zwei Meinungen
// darüber, wie ein Nullmonat aussieht oder welcher Balken der laufende
// ist, und die Kurve im Blatt sähe anders aus als die im Reiter.
//
// Von Hand statt mit fl_chart: Es gibt keine Achse, keine Skala und
// nichts zu skalieren — die Werte sind bereits auf 0…100 normiert. Ein
// Diagrammpaket brächte hier Konfiguration statt Ersparnis.
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../season_curves.dart';

class SeasonBars extends StatelessWidget {
  const SeasonBars({
    super.key,
    required this.months,
    required this.currentMonth,
    this.height = 44,
    this.showLetters = true,
  });

  /// Effort-korrigierter Jahresgang, Index 0 = Januar, Maximum = 100.
  final List<int> months;

  /// Index 0…11 des Monats, der hervorgehoben wird.
  final int currentMonth;

  /// Höhe der Balken. Im Blatt 44, in der Katalogzeile 18.
  final double height;

  /// Die Monatsbuchstaben unter den Balken — im Katalog weggelassen,
  /// dort steht die Kurve neben dem Namen und muss in eine Zeile passen.
  final bool showLetters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < 12; index++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: showLetters ? 1.5 : 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: height,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        // Ein Wert von 0 bekommt trotzdem eine dünne
                        // Linie: Die leere Spalte soll als „fast nie"
                        // lesbar sein und nicht als Lücke im Diagramm.
                        heightFactor: (months[index] / 100).clamp(0.04, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: index == currentMonth
                                ? AppColors.forestGreen
                                : AppColors.forestGreen.withValues(alpha: 0.35),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showLetters) ...[
                    const SizedBox(height: 2),
                    Text(
                      kMonthLetters[index],
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: index == currentMonth
                            ? AppColors.forestGreen
                            : theme.hintColor,
                        fontWeight: index == currentMonth
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
