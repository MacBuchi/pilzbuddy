// Das Saison-Tor je Klasse (#495): Maximum über die Mitglieder, Tor
// statt Faktor, ausgenommene Arten zählen nicht.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/ampel/ampel_season_gate.dart';

void main() {
  test('die Mitglieder kommen aus dem Modell, nicht aus einer zweiten Liste',
      () {
    expect(ampelMembersOf('holz_winter'), contains('Austernseitling'));
    expect(ampelMembersOf('holz_winter'), contains('Krause Glucke'));
    expect(ampelMembersOf('sommer'), ['Pfifferling']);
    expect(ampelMembersOf('gibt es nicht'), isEmpty);
  });

  test('September: Austernseitling & Co. rechnet — wegen Krause Glucke und '
      'Leberpilz, nicht wegen des Austernseitlings', () {
    final now = ampelMembersInSeason('holz_winter', month: 9);
    expect(now, containsAll(['Krause Glucke', 'Leberpilz']));
    expect(now, isNot(contains('Austernseitling')));
    expect(ampelClassActive('holz_winter', month: 9), isTrue);
    expect(ampelNowLine(ampelHolzWinterClass, month: 9),
        startsWith('jetzt: '));
    expect(ampelNowLine(ampelHolzWinterClass, month: 9),
        contains('Krause Glucke'));
  });

  test('Dezember: Steinpilz & Co. und Pfifferling pausieren, die '
      'Holz-Klasse trägt ihr Namensgeber selbst', () {
    expect(ampelClassActive('herbst', month: 12), isFalse);
    expect(ampelClassActive('sommer', month: 12), isFalse);
    expect(ampelClassActive('holz_winter', month: 12), isTrue);
    expect(ampelNowLine(ampelHolzWinterClass, month: 12), isNull,
        reason: 'der Austernseitling hat im Dezember Saison — der Name '
            'stimmt, keine Zeile nötig');
    final active = ampelActiveClasses(ampelShippedClasses, month: 12);
    expect(active, isNot(contains(ampelHerbstClass)));
    expect(active, contains(ampelHolzWinterClass));
    expect(active.indexOf(ampelHolzWinterClass),
        lessThan(active.indexOf(ampelCantharellalesClass)),
        reason: 'die Reihenfolge der Auswahl bleibt — Gleichstand gewinnt '
            'weiter die frühere Klasse');
  });

  test('ausgenommene Arten zählen nicht: ohne die Herbst-Holzarten ist '
      'die Klasse im September aus', () {
    const excluded = {
      'Krause Glucke',
      'Leberpilz',
      'Rehbrauner Dachpilz',
      'Lungenseitling',
      'Schwefelporling',
    };
    expect(ampelClassActive('holz_winter', month: 9, excluded: excluded),
        isFalse);
    expect(ampelClassActive('holz_winter', month: 12, excluded: excluded),
        isTrue, reason: 'im Dezember trägt der Austernseitling selbst');
  });

  test('alle Arten einer Klasse ausgenommen heißt Klasse aus', () {
    final all = ampelMembersOf('herbst').toSet();
    expect(ampelClassActive('herbst', month: 9, excluded: all), isFalse);
    expect(ampelActiveClasses(ampelShippedClasses, month: 9, excluded: all),
        isNot(contains(ampelHerbstClass)));
  });

  test('die Zeile nennt höchstens drei Namen und zählt den Rest', () {
    // Im September tragen fünf Holz-Arten die Klasse.
    final line = ampelNowLine(ampelHolzWinterClass, month: 9)!;
    expect(line.split(', ').length, 3);
    expect(line, contains('+'));
  });
}
