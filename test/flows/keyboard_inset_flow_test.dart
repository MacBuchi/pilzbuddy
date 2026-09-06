// Die Tastatur überlagert die Karte, sie schiebt sie nicht (#397).
//
// Der Feldbericht hat zwei Hälften. Die eine ist reproduzierbar: Sobald
// irgendwo ein Textfeld den Fokus bekommt, wandern Karte, Legende,
// Knopfspalte und Reiterleiste nach oben. Die andere ist es NICHT — „selten
// taucht es einfach auf, dann ist das untere Drittel des Bildschirms weiß
// und wird nicht genutzt", auch nachdem die Tastatur wieder zu ist.
//
// Beide haben dieselbe Wurzel: `Scaffold` schrumpft ab Werk seinen Body um
// `viewInsets.bottom`. Bleibt dieses Inset hängen, schrumpft er weiter, und
// unter dem Body erscheint `colorScheme.surface` — weiß. Die URSACHE des
// hängenden Insets ist nicht gefunden; was diese Tests festhalten, ist,
// dass sie keine Wirkung mehr hat.
//
// Deshalb stellen sie genau diesen Zustand her: ein Fenster mit gesetztem
// `viewInsets.bottom`, ohne dass je eine Tastatur da war. Das ist die
// Lage, die der Nutzer gesehen hat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/map_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  FakeBackend loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  /// Ein Telefonschirm mit einer Tastatur, die „hängengeblieben" ist.
  /// 800 physische Pixel bei dpr 2,625 sind rund 305 dp — eine gewöhnliche
  /// Android-Tastatur, also ziemlich genau das „untere Drittel".
  void stuckKeyboard(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(tester.view.reset);
  }

  testWidgets('die Reiterleiste bleibt unten, auch bei hängendem Inset',
      (tester) async {
    stuckKeyboard(tester);
    await pumpApp(tester, loggedInBackend());

    final screenHeight = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;
    final bar = tester.getRect(find.byType(NavigationBar));

    // Ohne `resizeToAvoidBottomInset: false` in der Hülle säße sie hier
    // 305 dp höher — und darunter stünde der weiße Streifen.
    expect(bar.bottom, moreOrLessEquals(screenHeight, epsilon: 0.5),
        reason: 'die Hülle darf dem Inset nicht ausweichen');
  });

  testWidgets('die Knopfspalte bleibt unten, auch bei hängendem Inset',
      (tester) async {
    // Der zweite Scaffold, und er braucht eine eigene Messung: Der RAHMEN
    // eines Scaffolds bleibt groß, auch wenn er seinen Body schrumpft —
    // die Kante des Karten-Scaffolds sieht den Fehler also gar nicht. Die
    // Knopfspalte hängt dagegen an `floatingActionButton`, und den hebt
    // Flutter über die Tastatur. Sie ist damit die Stelle, an der sich der
    // innere Scaffold verrät — und es ist genau das, was der Bericht
    // nennt: „Es ist auch nicht notwendig alles zu verschieben (Karte,
    // Legende, Knöpfe)".
    stuckKeyboard(tester);
    await pumpApp(tester, loggedInBackend());

    final buttons = tester.getRect(find.byType(FittedBox).first);
    final bar = tester.getRect(find.byType(NavigationBar));

    expect(buttons.bottom, lessThan(bar.top + 0.5),
        reason: 'die Spalte sitzt über der Reiterleiste');
    expect(buttons.bottom, greaterThan(bar.top - 100),
        reason: 'aber dicht darüber — mit ausweichendem Scaffold stünde sie '
            'eine ganze Tastaturhöhe höher');
  });

  testWidgets('die Karte reicht bis an die Reiterleiste', (tester) async {
    // Die eigentliche Zusage: kein ungenutzter Streifen zwischen Karte und
    // Leiste. Gemessen wird gegen die Kante der Leiste und nicht gegen den
    // Schirm — die Leiste ist die einzige richtige Bezugsgröße, sonst
    // prüfte der Test nur, dass irgendetwas irgendwo groß ist.
    stuckKeyboard(tester);
    await pumpApp(tester, loggedInBackend());

    // Gemessen wird der Scaffold des Karten-Screens und nicht `MapView`:
    // Der Renderer der Karte hat im Test keine Fläche (die Kacheln sind
    // durch ein 1×1-PNG ersetzt), `getRect` läge dort bei 0×0 und der
    // Test prüfte nichts.
    final mapArea = tester.getRect(find.descendant(
        of: find.byType(MapScreen), matching: find.byType(Scaffold)));
    final bar = tester.getRect(find.byType(NavigationBar));

    expect(mapArea.bottom, moreOrLessEquals(bar.top, epsilon: 0.5),
        reason: 'zwischen Karte und Reiterleiste darf nichts frei bleiben');
  });
}
