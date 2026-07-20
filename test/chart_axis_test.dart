// Y-Achse des Balkendiagramms „Funde pro Jahr" (Issue #97). Der Fehler war
// nicht sichtbar, solange man mit wenigen Testfunden arbeitet — er zeigt sich
// erst bei einem gut gefüllten Konto. Deshalb prüft der letzte Test die
// gesamte Spanne statt einzelner Beispiele.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/profile/profile_screen.dart';

/// So viele Beschriftungen zeichnet fl_chart für [maxY] bei diesem Schritt:
/// 0, step, 2·step … bis einschließlich maxY.
int _labelCount(double maxY, double step) => (maxY / step).floor() + 1;

void main() {
  test('Kleine Zahlen behalten den Schritt 1', () {
    // maxY ist im Diagramm immer maxCount * 1.2.
    expect(yAxisStep(1 * 1.2), 1);
    expect(yAxisStep(3 * 1.2), 1);
    expect(yAxisStep(4 * 1.2), 1);
    // Ab hier wären es sieben Beschriftungen auf 160 px Höhe — lieber 0/2/4/6.
    expect(yAxisStep(5 * 1.2), 2);
  });

  test('Größere Zahlen bekommen runde Schritte', () {
    expect(yAxisStep(7 * 1.2), 2);
    expect(yAxisStep(20 * 1.2), 5);
    expect(yAxisStep(50 * 1.2), 20);
    expect(yAxisStep(500 * 1.2), 200);
  });

  test('Der Schritt bleibt ganzzahlig — Funde sind Stückzahlen', () {
    for (var count = 1; count <= 1000; count++) {
      final step = yAxisStep(count * 1.2);
      expect(step, step.roundToDouble(),
          reason: '$count Funde ergeben den krummen Schritt $step');
    }
  });

  test('Nie mehr als sechs Beschriftungen, egal wie viele Funde', () {
    for (var count = 1; count <= 1000; count++) {
      final maxY = count * 1.2;
      final labels = _labelCount(maxY, yAxisStep(maxY));
      // Fünf Schritte plus die Null.
      expect(labels, lessThanOrEqualTo(6),
          reason: '$count Funde ergeben $labels Beschriftungen');
      // Die Gegenprobe: eine Achse mit nur einer Beschriftung wäre nutzlos.
      expect(labels, greaterThanOrEqualTo(2), reason: '$count Funde');
    }
  });
}
