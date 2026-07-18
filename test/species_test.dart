import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/features/spots/species_suggestions.dart';
import 'package:pilzbuddy/models/find.dart';

void main() {
  group('suggestSpecies', () {
    const own = ['Steinpilz', 'Pfifferling'];
    const builtin = [
      KnownSpecies('Steinpilz', SpeciesCategory.speisepilz),
      KnownSpecies('Maronenröhrling', SpeciesCategory.speisepilz),
      KnownSpecies('Fliegenpilz', SpeciesCategory.giftpilz),
      KnownSpecies('Parasol', SpeciesCategory.speisepilz),
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

    test('Kategorien werden zugeordnet — auch für eigene Arten', () {
      final result = suggestSpecies('fliegen', ['Fliegenpilz'], builtin);
      expect(result.single.isOwn, isTrue);
      // Kategorie kommt per Lookup aus der bekannten Liste
      expect(result.single.category, SpeciesCategory.giftpilz);
    });

    test('unbekannte eigene Art hat keine Kategorie', () {
      final result = suggestSpecies('geheim', ['Geheimpilz'], builtin);
      expect(result.single.category, isNull);
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

  group('categoryFor', () {
    test('findet Kategorien case-insensitiv, unbekannt → null', () {
      expect(categoryFor('steinpilz'), SpeciesCategory.speisepilz);
      expect(categoryFor('FLIEGENPILZ'), SpeciesCategory.giftpilz);
      expect(categoryFor('Geheimpilz'), isNull);
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
