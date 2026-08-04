// Die Stationssuche am Spot.
//
// Der kritische Teil ist nicht die Schleife, sondern ihre Regeln: Eine
// Station mit zu vielen Lücken darf nicht gewinnen (die übernächste tut
// es), Luft und Boden sind getrennte Netze, und jenseits der Reichweite
// gibt es KEINE Antwort statt einer aus einer anderen Gegend.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/map/spot_weather.dart';

void main() {
  List<double?> filled(int days, double value) =>
      List<double?>.filled(days, value);

  AirStation airAt(double lat, double lon,
          {String name = 'Station',
          int height = 200,
          List<double?>? max,
          List<double?>? min}) =>
      AirStation(
        name: name,
        lat: lat,
        lon: lon,
        height: height,
        max: max ?? filled(14, 20),
        min: min ?? filled(14, 10),
      );

  SoilStation soilAt(double lat, double lon,
          {String name = 'Bodenstation', List<double?>? soil}) =>
      SoilStation(
        name: name,
        lat: lat,
        lon: lon,
        height: 200,
        soil: soil ?? filled(14, 15),
      );

  final days = [
    for (var i = 0; i < 14; i++) DateTime.utc(2026, 7, 21 + i),
  ];

  group('nearest', () {
    test('findet die nächste, nicht die erste in der Liste', () {
      final table = WeatherTable(days: days, air: [
        airAt(53, 11, name: 'Fern'),
        airAt(51.1, 11, name: 'Nah'),
      ], soil: const []);
      final pick = table.at(51, 11)!.air!;
      expect(pick.station.name, 'Nah');
      expect(pick.km, closeTo(11.1, 0.3));
    });

    test('bei Gleichstand gewinnt die frühere — deterministisch', () {
      // Zwei Stationen, exakt gleich weit: Derselbe Spot muss immer
      // dieselbe Station sehen, sonst springt die Linie zwischen Öffnen
      // und Öffnen.
      final table = WeatherTable(days: days, air: [
        airAt(51.5, 11, name: 'Erste'),
        airAt(50.5, 11, name: 'Zweite'),
      ], soil: const []);
      expect(table.at(51, 11)!.air!.station.name, 'Erste');
    });

    test('überspringt eine Station mit zu vielen Lücken', () {
      // Die nähere hat nur 9 von 14 Tagen — eine Linie, die überwiegend
      // aus Lücken besteht, sieht aus wie ein Fehler der App. Die
      // übernächste gewinnt: eine benennbare Station, keine Mischung.
      final gappy = [...filled(9, 20), null, null, null, null, null];
      final table = WeatherTable(days: days, air: [
        airAt(51.05, 11, name: 'Lückig', max: gappy),
        airAt(51.5, 11, name: 'Vollständig'),
      ], soil: const []);
      expect(table.at(51, 11)!.air!.station.name, 'Vollständig');
    });

    test('ein Luft-Tag zählt nur mit Höchst- UND Tiefstwert', () {
      final halfDays = [...filled(9, 20), null, null, null, null, null];
      expect(airAt(51, 11, min: halfDays).measuredDays, 9,
          reason: 'max liegt vor, aber ohne min ist der Tag halb');
    });

    test('jenseits der Reichweite gibt es keine Antwort', () {
      // ~220 km — das Wetter einer anderen Gegend. Zeile weglassen
      // statt raten: Genau die Regel, nach der auch die Regensummen
      // außerhalb des Gitters verschwinden.
      final table = WeatherTable(
          days: days, air: [airAt(53, 11)], soil: const []);
      expect(table.at(51, 11), isNull);
    });

    test('Luft und Boden sind getrennte Netze', () {
      final table = WeatherTable(
        days: days,
        air: [airAt(51.1, 11, name: 'Luftstation')],
        soil: [soilAt(51.3, 11, name: 'Bodenstation')],
      );
      final at = table.at(51, 11)!;
      expect(at.air!.station.name, 'Luftstation');
      expect(at.soil!.station.name, 'Bodenstation');
    });

    test('ein Netz darf fehlen, ohne das andere mitzunehmen', () {
      final table = WeatherTable(
          days: days, air: [airAt(51.1, 11)], soil: const []);
      final at = table.at(51, 11)!;
      expect(at.air, isNotNull);
      expect(at.soil, isNull);
      expect(at.soilMean, isNull);
    });
  });

  test('distanceKm liegt an bekannten Paaren richtig', () {
    // Berlin–Potsdam (~27 km Luftlinie) und München–Augsburg (~57 km):
    // grob genug, um vertauschte Achsen oder eine fehlende
    // Breitengrad-Stauchung sofort zu sehen.
    expect(distanceKm(52.52, 13.405, 52.396, 13.058), closeTo(27, 2));
    expect(distanceKm(48.137, 11.575, 48.371, 10.898), closeTo(57, 3));
  });

  group('span', () {
    test('nimmt Frost mit — er ist die wichtigste Zahl', () {
      final at = SpotTemperature(
        days: days,
        air: (
          station: airAt(51, 11,
              max: [...filled(13, 12), 14],
              min: [...filled(13, 2), -3.4]),
          km: 5,
        ),
        soil: null,
      );
      expect(at.span, (low: -3.4, high: 14.0));
      expect(at.isEmpty, isFalse);
    });

    test('lauter Lücken heißt leer', () {
      final at = SpotTemperature(
        days: days,
        air: (
          station: airAt(51, 11,
              max: filled(14, 0).map((_) => null).toList(),
              min: filled(14, 0).map((_) => null).toList()),
          km: 5,
        ),
        soil: null,
      );
      expect(at.span, isNull);
      expect(at.isEmpty, isTrue);
    });
  });

  group('weatherTableFrom', () {
    List<int> packed(Map<String, dynamic> json) =>
        GZipEncoder().encode(utf8.encode(jsonEncode(json)))!;

    Map<String, dynamic> asset() => {
          'days': ['2026-08-01', '2026-08-02', '2026-08-03'],
          'stations': [
            {
              'id': 44,
              'lat': 52.9336,
              'lon': 8.237,
              'h': 44,
              'name': 'Großenkneten',
              'max': [31.5, null, 23.2],
              'min': [12.1, 11.0, null],
            },
          ],
          'soil': [
            {
              'id': 44,
              'lat': 52.9336,
              'lon': 8.237,
              'h': 44,
              'name': 'Großenkneten',
              'soil': [24.2, null, 22.0],
            },
          ],
        };

    test('liest Tage, beide Netze und die Lücken', () {
      final table = weatherTableFrom(packed(asset()))!;
      expect(table.days, [
        DateTime.parse('2026-08-01'),
        DateTime.parse('2026-08-02'),
        DateTime.parse('2026-08-03'),
      ]);
      expect(table.air.single.max, [31.5, null, 23.2]);
      expect(table.air.single.min, [12.1, 11.0, null]);
      expect(table.air.single.height, 44);
      expect(table.soil.single.soil, [24.2, null, 22.0]);
    });

    test('eine kaputte Datei ist keine Tabelle', () {
      expect(weatherTableFrom(const [1, 2, 3]), isNull);
      expect(weatherTableFrom(GZipEncoder().encode(utf8.encode('kaputt'))!),
          isNull);
    });

    test('eine Reihe falscher Länge wird übersprungen, nicht gedehnt', () {
      // Länge ≠ Tage hieße: still um Tage verschoben gelesen.
      final broken = asset();
      (broken['stations'] as List).add({
        'id': 99,
        'lat': 50.0,
        'lon': 10.0,
        'h': 100,
        'name': 'Schief',
        'max': [1.0, 2.0],
        'min': [1.0, 2.0],
      });
      final table = weatherTableFrom(packed(broken))!;
      expect(table.air.single.name, 'Großenkneten');
    });

    test('ein alter Stand ohne Boden-Abschnitt bleibt lesbar', () {
      final old = asset()..remove('soil');
      final table = weatherTableFrom(packed(old))!;
      expect(table.air, hasLength(1));
      expect(table.soil, isEmpty);
    });
  });

  test('der Provider lädt nichts ohne Zustimmung — auch am Widget vorbei',
      () async {
    // Das Spot-Blatt fragt den Provider erst nach der Zustimmung, aber
    // die Zusage „lädt nicht ungefragt" soll nicht daran hängen, dass
    // das für immer der einzige Aufrufer bleibt.
    var calls = 0;
    final container = ProviderContainer(overrides: [
      rainCourseEnabledProvider.overrideWith((ref) => false),
      weatherTableLoaderProvider.overrideWithValue(() async {
        calls++;
        return null;
      }),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(weatherTableProvider.future), isNull);
    expect(calls, 0, reason: 'ungefragt geladen');
  });
}
