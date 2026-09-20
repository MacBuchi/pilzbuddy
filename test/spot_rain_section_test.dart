// Die Textzeilen unter dem Wetterdiagramm — reine Funktionen, ohne
// Widget. Die Bodenfeuchte-Zeile (2026-09-20) nennt Wert, Datum und
// Station, oder sie fehlt ganz; ein Platzhalter wäre eine Aussage.
import 'package:flutter_test/flutter_test.dart';
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
