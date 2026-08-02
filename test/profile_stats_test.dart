// „Top-Arten" im Profil. Die Zählung steckte bis 1.37.0 im Widget und
// gruppierte über den rohen Artnamen — „steinpilz" und „Steinpilz" standen
// dadurch getrennt untereinander, und zwei Namen derselben Art erst recht.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/profile/profile_screen.dart';
import 'package:pilzbuddy/models/find.dart';

Find find(String? species, {int? count}) => Find(
      id: '$species-$count',
      spotId: 's',
      species: species,
      count: count,
      foundOn: DateTime(2026, 8, 2),
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
}
