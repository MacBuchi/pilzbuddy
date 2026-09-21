// Die Zahlen des Reiters „Spots" (#509) — bis 1.160.0 die Statistik im
// Profil, daher der frühere Name `profile_stats_test.dart`.
//
// „Top-Arten": Die Zählung steckte bis 1.37.0 im Widget und gruppierte
// über den rohen Artnamen — „steinpilz" und „Steinpilz" standen dadurch
// getrennt untereinander, und zwei Namen derselben Art erst recht.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/spot_stats.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

Find find(String? species, {int? count, DateTime? on, bool blank = false}) =>
    Find(
      id: '$species-$count-${on?.millisecondsSinceEpoch}',
      spotId: 's',
      species: species,
      count: count,
      foundOn: on ?? DateTime(2026, 8, 2),
      blank: blank,
    );

Spot spot(List<Find> finds) => Spot(
      id: 'spot-${finds.length}-${finds.hashCode}',
      ownerId: 'me',
      lat: 51,
      lng: 10,
      finds: finds,
    );

void main() {
  test('zählt Stückzahlen, häufigste zuerst', () {
    final top = topSpecies([
      find('Pfifferling', count: 3),
      find('Steinpilz', count: 1),
      find('Pfifferling', count: 2),
    ]);
    expect(top.map((t) => (t.name, t.count)),
        [('Pfifferling', 5), ('Steinpilz', 1)]);
  });

  test('ein Fund ohne Stückzahl zählt als einer', () {
    expect(topSpecies([find('Steinpilz')]).single.count, 1);
  });

  test('Groß-/Kleinschreibung trennt nicht mehr', () {
    final top = topSpecies([find('steinpilz'), find('Steinpilz')]);
    expect(top, hasLength(1));
    expect(top.single, (name: 'Steinpilz', count: 2));
  });

  test('Zweitnamen zählen zur selben Art', () {
    final top = topSpecies([find('Totentrompete'), find('Herbsttrompete')]);
    expect(top, hasLength(1));
    expect(top.single, (name: 'Herbsttrompete', count: 2));
  });

  test('Funde ohne Art fallen heraus', () {
    expect(topSpecies([find(null), find('')]), isEmpty);
  });

  test('bei Gleichstand alphabetisch', () {
    final top = topSpecies([find('Steinpilz'), find('Birkenpilz')]);
    expect(top.map((t) => t.name), ['Birkenpilz', 'Steinpilz']);
  });

  group('Jahr und Monat', () {
    test('Funde pro Jahr kommen aufsteigend', () {
      final years = findsPerYear([
        find('Steinpilz', on: DateTime(2026, 9, 1)),
        find('Marone', on: DateTime(2024, 9, 1)),
        find('Marone', on: DateTime(2026, 8, 1)),
      ]);
      expect(years.map((y) => (y.year, y.count)), [(2024, 1), (2026, 2)]);
    });

    test('der Jahresgang zählt über alle Jahre in denselben Monat', () {
      final months = findsPerMonth([
        find('Steinpilz', on: DateTime(2025, 9, 20)),
        find('Steinpilz', on: DateTime(2026, 9, 2)),
        find('Morchel', on: DateTime(2026, 4, 5)),
      ]);
      expect(months[8], 2, reason: 'September');
      expect(months[3], 1, reason: 'April');
      expect(months.where((m) => m > 0), hasLength(2));
    });

    test('skaliert wird auf den stärksten Monat, nicht auf die Summe', () {
      expect(scaledToHundred([0, 2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
          [0, 50, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('ohne Funde bleibt der Jahresgang bei null — keine Division', () {
      expect(scaledToHundred(List<int>.filled(12, 0)),
          List<int>.filled(12, 0));
    });
  });

  group('Saison bis heute', () {
    final heute = DateTime(2026, 9, 21);

    test('vergleicht bis zum selben Tag des Vorjahres', () {
      // Der Oktober-Fund von 2025 zählt NICHT mit: Am 21. September
      // hatte man ihn damals noch nicht. Sonst stünde man jedes Jahr bis
      // Dezember im Rückstand.
      final season = seasonToDate([
        find('Steinpilz', on: DateTime(2026, 9, 3)),
        find('Marone', on: DateTime(2026, 8, 30)),
        find('Steinpilz', on: DateTime(2025, 9, 1)),
        find('Steinpilz', on: DateTime(2025, 10, 8)),
      ], heute);
      expect(season.year, 2026);
      expect(season.finds, 2);
      expect(season.species, 2);
      expect(season.lastFinds, 1);
      expect(season.lastSpecies, 1);
    });

    test('der heutige Tag zählt noch mit', () {
      final season = seasonToDate([find('Steinpilz', on: heute)], heute);
      expect(season.finds, 1);
    });

    test('ältere Jahre bleiben draußen', () {
      final season =
          seasonToDate([find('Steinpilz', on: DateTime(2020, 9, 1))], heute);
      expect(season.finds, 0);
      expect(season.lastFinds, 0);
    });
  });

  group('Leergänge', () {
    test('zählt Besuche und die leeren darunter', () {
      final share = blankShare([
        spot([
          find('Steinpilz'),
          find(null, on: DateTime(2026, 8, 3), blank: true),
        ]),
        spot([find(null, on: DateTime(2026, 8, 4), blank: true)]),
      ]);
      expect(share.visits, 3);
      expect(share.blanks, 2);
    });

    test('Buddy-Einträge zählen nicht als meine Besuche', () {
      final fremd = Find(
        id: 'f',
        spotId: 's',
        species: 'Parasol',
        foundOn: DateTime(2026, 8, 2),
        isOwn: false,
      );
      final share = blankShare([spot([find('Steinpilz'), fremd])]);
      expect(share.visits, 1);
    });
  });
}
