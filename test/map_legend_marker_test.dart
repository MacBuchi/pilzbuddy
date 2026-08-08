// Der Messstrich der Karten-Legende (#235): Wo auf der Regen-Stufenskala
// ein Wert liegt — pur gerechnet, das Widget dazu prüft der Flow-Test.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/widgets/map_legend.dart';

void main() {
  test('rainMarkerFraction: Bandlage linear, Ränder ehrlich', () {
    const levels = [10, 20, 30, 40];
    // Unter der ersten Stufe ist die Karte farblos — KEIN Strich, sonst
    // behauptete die Skala „mindestens Stufe eins".
    expect(rainMarkerFraction(5, levels), isNull);
    expect(rainMarkerFraction(10, levels), 0);
    // Mitte des ersten Bandes = ein halbes von vier Bändern.
    expect(rainMarkerFraction(15, levels), closeTo(0.125, 1e-9));
    expect(rainMarkerFraction(25, levels), closeTo(0.375, 1e-9));
    // Ab der letzten Stufe endet die Skala mit „+" — ans Ende geklemmt.
    expect(rainMarkerFraction(40, levels), 1);
    expect(rainMarkerFraction(400, levels), 1);
    expect(rainMarkerFraction(12, const <int>[]), isNull);
  });
}
