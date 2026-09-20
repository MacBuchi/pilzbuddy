// Die Geometrie des Kontextmenüs (#483).
//
// Rein gerechnet, also hier ohne Widget-Baum geprüft. **Die Randfälle
// SIND die Sache**: Auf einer bildschirmfüllenden Karte drückt man
// ständig in Randnähe, und ein Menü, das dort hinausragt, ist genau
// dann kaputt, wenn man es braucht.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/widgets/map_context_menu.dart';

void main() {
  const screen = Size(400, 800);

  MapContextMenuLayout at(double x, double y) => MapContextMenuLayout(
        origin: Offset(x, y),
        screen: screen,
        count: 3,
      );

  test('In der Mitte klappt es nach oben und fächert nach rechts', () {
    // Nach oben ist die Vorgabe: Der Finger verdeckt, was darunter liegt.
    final layout = at(100, 500);
    expect(layout.opensUpward, isTrue);
    expect(layout.fansRight, isTrue);
    expect(layout.fitsOnScreen, isTrue);
  });

  test('Oben am Rand klappt es nach unten', () {
    final layout = at(100, 40);
    expect(layout.opensUpward, isFalse);
    expect(layout.fitsOnScreen, isTrue);
  });

  test('Rechts am Rand fächert es nach links', () {
    // Sonst ragte die breiteste Pille über den Rand — und rechts ist
    // der Daumen, also wird dort oft gedrückt.
    final layout = at(360, 500);
    expect(layout.fansRight, isFalse);
    expect(layout.fitsOnScreen, isTrue);
  });

  test('Auch in den vier Ecken bleibt alles im Bild', () {
    // Die eigentliche Zusage. Gerade die Ecken trifft man beim
    // Erkunden am Kartenrand ständig.
    for (final corner in [
      const Offset(8, 8),
      const Offset(392, 8),
      const Offset(8, 792),
      const Offset(392, 792),
    ]) {
      final layout = MapContextMenuLayout(
          origin: corner, screen: screen, count: 3);
      expect(layout.fitsOnScreen, isTrue,
          reason: 'Ecke $corner ragt hinaus');
    }
  });

  test('Kein Chip liegt auf der gedrückten Stelle', () {
    // „Was ist hier?" beantwortet genau diesen Punkt — verdeckt man
    // ihn, ist die Antwort wertlos.
    final layout = at(200, 400);
    for (var i = 0; i < 3; i++) {
      final chip = Rect.fromLTWH(layout.chipTopLeft(i).dx,
          layout.chipTopLeft(i).dy, 190, kContextChipHeight);
      expect(chip.contains(layout.origin), isFalse,
          reason: 'Chip $i liegt über der gedrückten Stelle');
    }
  });

  test('Die Trefferfläche bleibt bei 44', () {
    // „Die eine Zahl, an der nicht gespart wird" (map_screen.dart) —
    // ein aufgefächertes Menü darf davon nichts abziehen, nur weil es
    // hübsch aussieht.
    expect(kContextChipHeight, 44);
  });

  test('Die Chips überlappen einander nicht', () {
    final layout = at(200, 400);
    for (var i = 1; i < 3; i++) {
      final a = layout.chipTopLeft(i - 1).dy;
      final b = layout.chipTopLeft(i).dy;
      expect((a - b).abs(), greaterThanOrEqualTo(kContextChipHeight),
          reason: 'Chip ${i - 1} und $i liegen übereinander');
    }
  });
}
