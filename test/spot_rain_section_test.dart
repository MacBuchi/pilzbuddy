// Die Textzeilen unter dem Wetterdiagramm — reine Funktionen, ohne
// Widget. Die Bodenfeuchte-Zeile nennt Wert, Datum und Quelle (seit
// #676 aus dem ERA5-Land-Gitter), oder sie fehlt ganz; ein Platzhalter
// wäre eine Aussage.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';
import 'package:pilzbuddy/features/map/soil_moisture_grid.dart';
import 'package:pilzbuddy/features/map/spot_weather.dart';
import 'package:pilzbuddy/features/spots/widgets/spot_rain_section.dart';

void main() {
  SpotTemperature withSoil(double? latest) => SpotTemperature(
        days: const [],
        air: null,
        soil: null,
        moisture: SpotSoilMoisture(
            mean: 0.3,
            latest: latest,
            newest: DateTime(2026, 10, 2),
            stale: false),
      );

  test('nennt Wert in Vol.-%, Tag und Quelle (#676)', () {
    expect(
        moistureLine(withSoil(0.312)),
        'Bodenfeuchte 7–28 cm: 31 Vol.-% (2.10., ERA5-Land, Copernicus).');
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
    group('gemessen im Alpenraum (#646)', () {
      RainDay alps(int origin, {int day = 1}) => RainDay(
          date: DateTime.utc(2026, 9, day),
          mm: 4,
          source: RainSource.alps,
          origin: origin);
      test('ein Landesdienst allein', () {
        expect(
            rainSourceLine(RainCourse([
              alps(AlpsOrigin.inca),
              alps(AlpsOrigin.inca, day: 2),
            ])),
            'Tagessummen gemessen: GeoSphere Austria');
      });
      test('an der Grenze: alle Beteiligten und das Wort „gemischt"', () {
        expect(
            rainSourceLine(RainCourse([
              alps(AlpsOrigin.inca | AlpsOrigin.radar),
              alps(AlpsOrigin.rprelimd | AlpsOrigin.inca, day: 2),
            ])),
            'Tagessummen gemessen: GeoSphere Austria, MeteoSchweiz und '
            'Deutscher Wetterdienst, an der Grenze gemischt');
      });
      test('Modellanteil wird gezählt, nicht verschwiegen', () {
        expect(
            rainSourceLine(RainCourse([
              alps(AlpsOrigin.dpc | AlpsOrigin.model),
              alps(AlpsOrigin.dpc, day: 2),
              RainDay(
                  date: DateTime.utc(2026, 9, 3),
                  mm: 1,
                  source: RainSource.model),
            ])),
            'Tagessummen gemessen: Radar-DPC, 2 von 3 Tagen mit '
            'Modellwerten (Open-Meteo)');
      });
      test('wo keiner misst, bleibt es beim Modellsatz', () {
        // Slowenien: Der Alpenstapel trägt dort nur das Modell.
        expect(
            rainSourceLine(RainCourse([alps(AlpsOrigin.model)])),
            'Tagessummen aus Modellwerten (Open-Meteo, ICON) — hier gibt es '
            'kein Radar');
      });
      test('ohne Herkunftsdatei: gemessen, ohne Namen zu raten', () {
        expect(rainSourceLine(RainCourse([alps(0)])),
            'Tagessummen gemessen: Messnetze des Alpenraums');
      });
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

  test('ohne Gitter oder ohne Wert keine Zeile', () {
    expect(moistureLine(null), isNull);
    expect(moistureLine(withSoil(null)), isNull);
  });
}
