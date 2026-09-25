// Die Textzeilen unter dem Wetterdiagramm — reine Funktionen, ohne
// Widget. Die Bodenfeuchte-Zeile (2026-09-20) nennt Wert, Datum und
// Station, oder sie fehlt ganz; ein Platzhalter wäre eine Aussage.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';
import 'package:pilzbuddy/features/map/spot_weather.dart';
import 'package:pilzbuddy/features/spots/widgets/spot_rain_section.dart';

void main() {
  final moistureDays = [
    for (var i = 0; i < 26; i++) DateTime.utc(2026, 8, 25 + i),
  ];
  MoistureStation station(List<double?> bfgl) => MoistureStation(
      name: 'Großenkneten', lat: 52.9, lon: 8.2, height: 44, bfgl: bfgl);

  test('nennt Wert, Tag und Station', () {
    final at = SpotTemperature(
      days: const [],
      air: null,
      soil: null,
      moisture: (
        station: station([...List<double?>.filled(25, 60), 76.6]),
        km: 11.6,
      ),
      moistureDays: moistureDays,
    );
    expect(
        moistureLine(at),
        'Bodenfeuchte 0–60 cm: 77 % der nutzbaren Feldkapazität '
        '(19.9., Station Großenkneten, 12 km).');
  });

  group('Quelle des Regens (#612)', () {
    RainCourse courseOf(List<RainSource?> sources) => RainCourse([
          for (final (i, s) in sources.indexed)
            RainDay(
                date: DateTime.utc(2026, 9, 1 + i),
                mm: s == null ? null : 3,
                source: s ?? RainSource.radar),
        ]);
    test('nur Radar, nur Modell, gemischt — drei Sätze', () {
      expect(rainSourceLine(courseOf([RainSource.radar, RainSource.radar])),
          'Tagessummen des Deutschen Wetterdienstes (Radar, nur Deutschland)');
      expect(rainSourceLine(courseOf([RainSource.model, null, RainSource.model])),
          'Tagessummen aus Modellwerten (Open-Meteo, ICON) — hier gibt es '
          'kein Radar');
      expect(
          rainSourceLine(courseOf(
              [RainSource.radar, RainSource.model, RainSource.radar])),
          'Tagessummen des Deutschen Wetterdienstes, 1 von 3 Tagen aus '
          'Modellwerten (Open-Meteo)');
    });
    test('ein Modellpunkt heißt nicht Station', () {
      const at = SpotTemperature(
        days: [],
        air: (
          station: AirStation(
              name: 'Modell 46,50° N 11,35° O', lat: 46.5, lon: 11.35,
              height: 283, max: [20], min: [10], model: true),
          km: 4.2,
        ),
        soil: null,
      );
      expect(stationLine(at),
          'Lufttemperatur: Modell 46,50° N 11,35° O (4 km, 283 m ü. NN, '
          'Open-Meteo-Modell, kein Messwert).');
      const real = SpotTemperature(
        days: [],
        air: (
          station: AirStation(
              name: 'Garmisch', lat: 47.5, lon: 11.1, height: 719,
              max: [20], min: [10]),
          km: 4.2,
        ),
        soil: null,
      );
      expect(stationLine(real),
          'Lufttemperatur: Station Garmisch (4 km, 719 m ü. NN).');
    });
  });

  test('ohne Station oder ohne Wert keine Zeile', () {
    expect(moistureLine(null), isNull);
    final leer = SpotTemperature(
      days: const [],
      air: null,
      soil: null,
      moisture: (station: station(List<double?>.filled(26, null)), km: 3),
      moistureDays: moistureDays,
    );
    expect(moistureLine(leer), isNull);
  });
}
