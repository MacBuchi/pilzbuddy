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
