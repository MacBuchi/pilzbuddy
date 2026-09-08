// Die Vorschlagsliste muss man durchblättern können (#421).
//
// Gemeldet aus der App: „Bei dem Versuch, zu browsen, wird direkt die
// Pilzart ausgewählt, auf die man gerade drückt." Die Zeilen wählten auf
// `onPointerDown` aus — beim Aufsetzen des Fingers, vor jeder
// Gestenentscheidung. Bei rund 110 bekannten Arten in einem
// `SingleChildScrollView` heißt das: Wer scrollen will, wählt aus.
//
// Der alte Weg hatte einen Grund, und der gilt weiter: Auf Web nimmt das
// Aufsetzen dem Textfeld den Fokus, und der Fokuswechsel blendete die
// Zeile aus, bevor ein `onTap` ankam. Der dritte Test hier hält genau
// diese Hälfte fest — sonst tauscht der nächste Umbau den einen Fehler
// gegen den anderen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  /// Neuer Spot, Artenfeld mit „Steinpil" gefüllt, Vorschläge offen.
  Future<void> openWithSuggestions(WidgetTester tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Steinpil');
    await settle(tester, frames: 4);
    expect(find.widgetWithText(ListTile, 'Steinpilz'), findsOneWidget);
  }

  String speciesText(WidgetTester tester) => tester
      .widget<TextField>(find.widgetWithText(TextField, 'Pilzart (optional)'))
      .controller!
      .text;

  testWidgets('ein Wisch über die Liste wählt nichts aus', (tester) async {
    await openWithSuggestions(tester);

    await tester.drag(
        find.widgetWithText(ListTile, 'Steinpilz'), const Offset(0, -120));
    await settle(tester);

    expect(speciesText(tester), 'Steinpil',
        reason: 'gewischt ist nicht getippt — das Feld bleibt, wie es war');
    // Und die Liste steht noch da: Ein Wisch beendet die Eingabe nicht.
    expect(find.widgetWithText(ListTile, 'Steinpilz'), findsOneWidget);
  });

  testWidgets('ein Tipp wählt weiterhin aus', (tester) async {
    await openWithSuggestions(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Steinpilz'));
    await settle(tester, frames: 4);

    expect(speciesText(tester), 'Steinpilz');
  });

  testWidgets('ein langsamer Tipp überlebt den Fokusverlust', (tester) async {
    // Die Web-Falle, gegen die der alte `onPointerDown` gebaut war —
    // hier nachgestellt, weil `kIsWeb` unter `flutter test` immer falsch
    // ist und das Textfeld auf der VM den Fokus gar nicht erst abgibt.
    await openWithSuggestions(tester);

    final gesture = await tester
        .startGesture(tester.getCenter(find.widgetWithText(ListTile, 'Steinpilz')));
    await tester.pump();

    // Genau das tut ein Browser beim Aufsetzen des Fingers.
    tester.binding.focusManager.primaryFocus?.unfocus();
    // Länger als die 250 ms, nach denen die Liste sonst verschwindet.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.widgetWithText(ListTile, 'Steinpilz'), findsOneWidget,
        reason: 'die Liste bleibt offen, solange ein Finger auf ihr liegt');

    await gesture.up();
    await settle(tester, frames: 4);

    expect(speciesText(tester), 'Steinpilz',
        reason: 'der Tipp darf nicht am Fokuswechsel verloren gehen');
  });
}
