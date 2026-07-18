import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/species_suggestions.dart';
import 'package:pilzbuddy/models/find.dart';

void main() {
  group('suggestSpecies', () {
    const own = ['Steinpilz', 'Pfifferling'];
    const builtin = ['Steinpilz', 'Maronenröhrling', 'Fliegenpilz', 'Parasol'];

    test('eigene Arten kommen vor bekannten', () {
      final result = suggestSpecies('pilz', own, builtin);
      expect(result.first, 'Steinpilz');
      expect(result, contains('Fliegenpilz'));
    });

    test('dedupliziert case-insensitiv über beide Listen', () {
      final result = suggestSpecies('stein', ['steinpilz'], builtin);
      expect(result, ['steinpilz']); // builtin-"Steinpilz" nicht doppelt
    });

    test('Contains-Match, nicht nur Präfix', () {
      final result = suggestSpecies('röhrling', own, builtin);
      expect(result, ['Maronenröhrling']);
    });

    test('leere Eingabe liefert Vorschläge bis zum Limit', () {
      final result = suggestSpecies('', own, builtin, limit: 3);
      expect(result, hasLength(3));
      expect(result.sublist(0, 2), own);
    });

    test('kein Treffer → leer', () {
      expect(suggestSpecies('xyz', own, builtin), isEmpty);
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
