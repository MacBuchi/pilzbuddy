// In einer Artenzeile steht der Pilz, nicht ein Emoji (#417).
//
// Die Vorschlagsliste zeigte `🍄` als Symbol — und die meisten Systeme
// zeichnen das als roten Fliegenpilz. Ausgerechnet in der Liste, aus der
// man die Art wählt, sah damit jeder Pilz giftig aus. Die Design-Sprache
// des Projekts verbietet es wörtlich; dieser Test hält es fest, weil
// genau so ein Emoji beim nächsten Umbau in fünf Sekunden wieder
// dasteht.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('die Vorschläge tragen echte Pilz-Symbole', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Steinpil');
    await settle(tester, frames: 4);

    // Die Treffer stehen da …
    expect(find.widgetWithText(ListTile, 'Steinpilz'), findsOneWidget);
    // … und tragen gezeichnete Pilze.
    expect(
        find.descendant(
            of: find.widgetWithText(ListTile, 'Steinpilz'),
            matching: find.byType(MushroomIcon)),
        findsOneWidget);
    // Kein nacktes Emoji mehr — das war der ganze Fehler.
    expect(find.text('🍄'), findsNothing);
    expect(find.text('📖'), findsNothing);
  });

  testWidgets('nach der Auswahl steht der Pilz im Feld', (tester) async {
    // Der Folgewunsch zu #417: Bis 1.127.2 verschwand das Symbol in dem
    // Moment, in dem man die Art gewählt hatte — danach stand dort nur
    // noch Text. Die Auswahl ist aber genau der Moment, in dem die App
    // WEISS, welcher Pilz gemeint ist.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);

    final field = find.widgetWithText(TextField, 'Pilzart (optional)');
    final iconInField =
        find.descendant(of: field, matching: find.byType(MushroomIcon));

    await tester.enterText(field, 'Steinpil');
    await settle(tester, frames: 4);

    // Solange die Vorschlagskarte offen ist: kein Symbol im Feld. Ein
    // halb getippter Name ist der Liste unbekannt und bekäme das
    // Fragezeichen — ein Urteil über eine Eingabe, die noch läuft.
    expect(iconInField, findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'Steinpilz'));
    await settle(tester, frames: 4);

    expect(iconInField, findsOneWidget);
  });

  testWidgets('ein Zweitname sieht aus wie seine Hauptart', (tester) async {
    // „Totentrompete" und „Herbsttrompete" sind dieselbe Art. Der Seed
    // von `forSpecies` kommt aus dem NAMEN — ginge die Rohform hinein,
    // bekäme dieselbe Art je nach Schreibweise einen anderen Farbton.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);

    final field = find.widgetWithText(TextField, 'Pilzart (optional)');
    await tester.enterText(field, 'Totentrompete');
    await settle(tester, frames: 4);
    // Ein Zweitname hält die Karte offen — sie bietet ja die Hauptart an.
    // Das Symbol steht, sobald man weitergegangen ist.
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, frames: 4);
    final icon = tester.widget<MushroomIcon>(
        find.descendant(of: field, matching: find.byType(MushroomIcon)));

    expect(icon.seed, stableSeed('Herbsttrompete'));
    expect(icon.species, 'Herbsttrompete');
  });

  testWidgets('eine abgelegte Art behält ihren Pilz', (tester) async {
    // „weitere Art" parkt die Zeile als Chip. Wer an einem Spot drei
    // Arten einträgt, sah die ersten beiden sonst wieder nur als Text.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Steinpilz');
    await settle(tester, frames: 4);
    await tester.ensureVisible(find.text('weitere Art'));
    await settle(tester, frames: 4);
    await tester.tap(find.text('weitere Art'));
    await settle(tester, frames: 4);

    final chip = find.widgetWithText(InputChip, 'Steinpilz');
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.byType(MushroomIcon)),
        findsOneWidget);
  });

  test('und keins schleicht sich in die Datei zurück', () {
    // Eine Textprüfung als zweite Reihe: Der Widget-Test oben sieht nur,
    // was bei DIESER Eingabe gerendert wird. Ein Emoji in einem anderen
    // Zweig derselben Datei — etwa im leeren Zustand — käme durch.
    //
    // Sie gilt NUR für die Artenliste. In Sätzen („Spot gespeichert 🍄")
    // ist das Emoji Zierde und ausdrücklich erlaubt.
    final source =
        File('lib/features/spots/widgets/species_field.dart').readAsStringSync();
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('🍄'), isFalse,
        reason: 'in einer Artenzeile gehört ein gezeichneter Pilz');
  });
}
