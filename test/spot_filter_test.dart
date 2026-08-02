// Die Filterregeln als reine Funktionen — hier liegt die Substanz von
// #154, nicht in der Oberfläche.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/spot_filter.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

int _id = 0;

Spot spot({
  required List<String?> species,
  bool isOwn = true,
}) {
  final id = 'spot-${_id++}';
  return Spot(
    id: id,
    ownerId: isOwn ? 'me' : 'buddy',
    lat: 51.0,
    lng: 10.0,
    isOwn: isOwn,
    finds: [
      for (var i = 0; i < species.length; i++)
        Find(
          id: '$id-$i',
          spotId: id,
          species: species[i],
          // Absteigend, damit der erste Eintrag der jüngste Fund ist.
          foundOn: DateTime(2026, 7, species.length - i),
        ),
    ],
  );
}

void main() {
  group('matchesSpotFilter', () {
    test('Ohne Filter passt jeder Spot', () {
      expect(
          matchesSpotFilter(spot(species: ['Marone']), const SpotFilter()),
          isTrue);
    });

    test('Die Art zählt über alle Funde, nicht nur den letzten', () {
      // Der wichtigste Fall: An der Stelle wurde zuletzt eine Marone
      // gefunden, davor ein Pfifferling. Wer nach Pfifferlingen filtert,
      // sucht genau diese Stelle wieder — auch wenn der Marker inzwischen
      // eine Marone zeigt.
      final s = spot(species: ['Marone', 'Pfifferling']);
      expect(s.lastFind?.species, 'Marone');
      expect(matchesSpotFilter(s, const SpotFilter(species: 'Pfifferling')),
          isTrue);
      expect(
          matchesSpotFilter(s, const SpotFilter(species: 'Steinpilz')),
          isFalse);
    });

    test('Groß-/Kleinschreibung entscheidet nicht', () {
      // Die Art ist ein Freitextfeld — „marone" und „Marone" sind dieselbe.
      expect(
          matchesSpotFilter(
              spot(species: ['marone']), const SpotFilter(species: 'Marone')),
          isTrue);
    });

    test('Ein Zweitname im Bestand passt zur Hauptbezeichnung', () {
      // Spots aus der Zeit vor der Vereinheitlichung tragen noch den
      // Zweitnamen. Fänden sie den Filter nicht, wäre eine Fundstelle im
      // Wald nicht auffindbar — der teuerste Fehler dieser App.
      final alt = spot(species: ['Totentrompete']);
      expect(matchesSpotFilter(alt, const SpotFilter(species: 'Herbsttrompete')),
          isTrue);
      // …und andersherum genauso.
      final neu = spot(species: ['Herbsttrompete']);
      expect(matchesSpotFilter(neu, const SpotFilter(species: 'Totentrompete')),
          isTrue);
    });

    test('Spots ohne Art fallen bei gesetzter Art heraus', () {
      expect(
          matchesSpotFilter(
              spot(species: [null]), const SpotFilter(species: 'Marone')),
          isFalse);
    });

    test('„Nur meine" blendet Freundes-Spots aus, auch bei passender Art', () {
      final friends = spot(species: ['Marone'], isOwn: false);
      expect(matchesSpotFilter(friends, const SpotFilter(onlyMine: true)),
          isFalse);
      expect(
          matchesSpotFilter(friends,
              const SpotFilter(species: 'Marone', onlyMine: true)),
          isFalse,
          reason: 'Beide Bedingungen gelten zusammen, nicht alternativ');
    });
  });

  group('speciesTally', () {
    test('zählt Fundstellen, nicht Funde', () {
      final tally = speciesTally([
        spot(species: ['Birkenpilz', 'Birkenpilz', 'Birkenpilz']),
        spot(species: ['Birkenpilz']),
        spot(species: ['Pfifferling']),
      ]);
      expect(tally.map((t) => (t.name, t.spots)),
          [('Birkenpilz', 2), ('Pfifferling', 1)]);
    });

    test('sortiert nach Häufigkeit, bei Gleichstand alphabetisch', () {
      final tally = speciesTally([
        spot(species: ['Steinpilz']),
        spot(species: ['Birkenpilz']),
        spot(species: ['Pfifferling']),
        spot(species: ['Pfifferling']),
      ]);
      expect(
          tally.map((t) => t.name), ['Pfifferling', 'Birkenpilz', 'Steinpilz']);
    });

    test('legt Zweitnamen mit der Hauptbezeichnung zusammen', () {
      // Der Kern der Sache: Zwei Fundstellen, zwei Namen, eine Art. Ohne
      // das stünden sie im Filterblatt getrennt untereinander und keiner
      // der beiden Einträge zeigte alle Spots.
      final tally = speciesTally([
        spot(species: ['Totentrompete']),
        spot(species: ['Herbsttrompete']),
      ]);
      expect(tally, hasLength(1));
      expect(tally.single.name, 'Herbsttrompete');
      expect(tally.single.spots, 2);
    });

    test('eigene Arten: Schreibweisen zusammen, die erste gewinnt', () {
      // Freitext wird nicht umbenannt — nur zusammengefasst.
      final tally = speciesTally([
        spot(species: ['Geheimpilz']),
        spot(species: ['geheimpilz']),
      ]);
      expect(tally, hasLength(1));
      expect(tally.single.name, 'Geheimpilz');
      expect(tally.single.spots, 2);
    });

    test('überspringt leere und fehlende Arten', () {
      expect(speciesTally([spot(species: [null, '', '   '])]), isEmpty);
    });
  });

  test('applySpotFilter behält die Reihenfolge', () {
    final spots = [
      spot(species: ['Marone']),
      spot(species: ['Pfifferling']),
      spot(species: ['Marone']),
    ];
    final filtered =
        applySpotFilter(spots, const SpotFilter(species: 'Marone'));
    expect(filtered.map((s) => s.id), [spots[0].id, spots[2].id]);
  });
}
