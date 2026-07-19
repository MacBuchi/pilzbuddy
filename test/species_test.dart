import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/features/spots/species_suggestions.dart';
import 'package:pilzbuddy/models/find.dart';

void main() {
  group('speciesFromText (Art im GPX-Punktnamen erkennen)', () {
    test('findet Arten in echten Punktnamen aus Karten-Apps', () {
      expect(speciesFromText('Edelreizker Spechbach'), 'Edelreizker');
      expect(speciesFromText('Steinpilz am Windrad'), 'Steinpilz');
      expect(speciesFromText('Wo du hin guckst, totentrompeten'),
          'Totentrompete');
      expect(speciesFromText('6 Maronenbäume'), 'Marone');
      expect(speciesFromText('Austernseitling am Stamm'), 'Austernseitling');
    });

    test('längster Treffer gewinnt, kein Treffer bleibt null', () {
      expect(speciesFromText('Maronenröhrling im Moos'), 'Maronenröhrling');
      expect(speciesFromText('Wasserturmweg, Bad Rappenau'), isNull);
      expect(speciesFromText('Semmelstoppelpipz'), isNull); // Tippfehler
      expect(speciesFromText(null), isNull);
    });
  });

  group('suggestSpecies', () {
    const own = ['Steinpilz', 'Pfifferling'];
    const builtin = [
      KnownSpecies('Steinpilz', SpeciesGroup.roehrlinge),
      KnownSpecies('Maronenröhrling', SpeciesGroup.roehrlinge),
      KnownSpecies('Fliegenpilz', SpeciesGroup.wulstlinge),
      KnownSpecies('Parasol', SpeciesGroup.schirmlinge),
    ];

    test('eigene Arten kommen vor bekannten', () {
      final result = suggestSpecies('pilz', own, builtin);
      expect(result.first.name, 'Steinpilz');
      expect(result.first.isOwn, isTrue);
      expect(result.map((s) => s.name), contains('Fliegenpilz'));
    });

    test('dedupliziert case-insensitiv über beide Listen', () {
      final result = suggestSpecies('stein', ['steinpilz'], builtin);
      expect(result.map((s) => s.name), ['steinpilz']);
    });

    test('Gruppen werden zugeordnet — auch für eigene Arten', () {
      final result = suggestSpecies('fliegen', ['Fliegenpilz'], builtin);
      expect(result.single.isOwn, isTrue);
      // Gruppe kommt per Lookup aus der eingebauten Artenliste
      expect(result.single.group, SpeciesGroup.wulstlinge);
    });

    test('unbekannte eigene Art hat keine Gruppe', () {
      final result = suggestSpecies('geheim', ['Geheimpilz'], builtin);
      expect(result.single.group, isNull);
    });

    test('Contains-Match, nicht nur Präfix', () {
      final result = suggestSpecies('röhrling', own, builtin);
      expect(result.map((s) => s.name), ['Maronenröhrling']);
    });

    test('leere Eingabe liefert Vorschläge bis zum Limit', () {
      final result = suggestSpecies('', own, builtin, limit: 3);
      expect(result, hasLength(3));
      expect(result.sublist(0, 2).map((s) => s.name), own);
    });

    test('kein Treffer → leer', () {
      expect(suggestSpecies('xyz', own, builtin), isEmpty);
    });
  });

  group('groupFor', () {
    test('findet Gruppen case-insensitiv, unbekannt/leer → null', () {
      expect(groupFor('steinpilz'), SpeciesGroup.roehrlinge);
      expect(groupFor('PFIFFERLING'), SpeciesGroup.leistlinge);
      expect(groupFor('Fliegenpilz'), SpeciesGroup.wulstlinge);
      expect(groupFor('Riesenbovist'), SpeciesGroup.boviste);
      expect(groupFor('Geheimpilz'), isNull);
      expect(groupFor(null), isNull);
      expect(groupFor('  '), isNull);
    });
  });

  group('ownSpeciesFromSortedNames', () {
    test('dedupliziert case-insensitiv und behält Reihenfolge', () {
      final result = ownSpeciesFromSortedNames(
          ['Marone', 'steinpilz', null, 'Steinpilz', '  ', 'Pfifferling']);
      expect(result, ['Marone', 'steinpilz', 'Pfifferling']);
    });
  });

  group('Find.createdAt', () {
    test('wird aus created_at geparst und ist optional', () {
      final mitTimestamp = Find.fromJson({
        'id': 'f1',
        'spot_id': 's1',
        'found_on': '2026-09-01',
        'created_at': '2026-09-01T14:30:00+00:00',
      });
      expect(mitTimestamp.createdAt, isNotNull);
      expect(mitTimestamp.createdAt!.toUtc().hour, 14);

      final ohne = Find.fromJson(
          {'id': 'f2', 'spot_id': 's1', 'found_on': '2026-09-01'});
      expect(ohne.createdAt, isNull);
    });
  });
}
