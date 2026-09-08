// Das Fragezeichen an unbekannten Arten (#417).
//
// Die Regel steckt in `isUnknownSpecies`, und ihre Feinheit ist der
// Unterschied zwischen „die App kennt diese Art nicht" und „es wurde gar
// keine Art eingetragen". Nur das Erste verdient ein Fragezeichen; das
// Zweite wäre ein Vorwurf für etwas, das niemand behauptet hat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

void main() {
  group('isUnknownSpecies', () {
    test('ein Name, den die Liste nicht kennt', () {
      expect(isUnknownSpecies('Mein Geheimpilz'), isTrue);
    });

    test('bekannte Arten nicht — auch nicht über Zweitnamen oder '
        'Schreibweise', () {
      // Läuft über `groupFor`, also über dieselbe Faltung wie die Suche
      // (#395): „flaschenbovist" ist bekannt, auch klein und ohne Umlaut.
      expect(isUnknownSpecies('Steinpilz'), isFalse);
      expect(isUnknownSpecies('Herrenpilz'), isFalse, reason: 'Zweitname');
      expect(isUnknownSpecies('flaschenbovist'), isFalse);
      expect(isUnknownSpecies('Flaschen-Stäubling'), isFalse);
    });

    test('KEINE Art ist nicht dasselbe wie eine unbekannte', () {
      // Ein Spot ohne Fund, ein Leergang: Da weiß die App nichts, weil
      // nichts gesagt wurde. Ein Fragezeichen wäre dort eine Behauptung
      // über eine Lücke, die der Nutzer selbst gelassen hat.
      expect(isUnknownSpecies(null), isFalse);
      expect(isUnknownSpecies(''), isFalse);
      expect(isUnknownSpecies('   '), isFalse);
    });
  });

  group('MushroomIcon', () {
    testWidgets('unbekannte Art trägt das Fragezeichen', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: MushroomIcon.forSpecies('Mein Geheimpilz', size: 44)));
      expect(find.byIcon(Icons.question_mark), findsOneWidget);
    });

    testWidgets('bekannte Art trägt keins', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: MushroomIcon.forSpecies('Steinpilz')));
      expect(find.byIcon(Icons.question_mark), findsNothing);
    });

    testWidgets('die Uhr gewinnt gegen das Fragezeichen', (tester) async {
      // Beide sitzen oben rechts. Wartet ein Eintrag noch auf die
      // Verbindung, ist DAS die dringendere Auskunft — die Art kann man
      // nachschlagen, den unversandten Fund nicht.
      await tester.pumpWidget(const MaterialApp(
        home: MushroomIcon(
            seed: 3, pending: true, unknown: true, species: 'Rätsel'),
      ));
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byIcon(Icons.question_mark), findsNothing);
    });

    testWidgets('eigene Arten bleiben untereinander unterscheidbar',
        (tester) async {
      // Der Grund, warum das Fragezeichen ein ABZEICHEN ist und kein
      // eigenes Symbol: Ein einheitliches „Unbekannt" gäbe drei selbst
      // eingetippten Arten drei identische Marker auf der Karte.
      final a = MushroomIcon.forSpecies('Mein Geheimpilz');
      final b = MushroomIcon.forSpecies('Noch ein Rätsel');
      expect(a.seed, isNot(b.seed));
      expect(a.unknown, isTrue);
      expect(b.unknown, isTrue);
    });
  });
}
