// Die eine Vorrang-Liste (#646): Verlauf am Spot, gebündelte Verläufe
// und Ampel-Fläche lesen alle `rainStacksProvider`. Stünde der
// Alpenstapel dort hinter dem Radar, antwortete im deutschen Grenzband
// das rohe Radar statt der Mischung — und Ampel und Blatt sähen an der
// Grenze wieder eine Kante.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';

import 'rain_grid_test.dart' show encode;

void main() {
  RainStackData stack(RainStackKind kind) => RainStackData(
        kind: kind,
        info: const RainStackInfo(
            width: 1, height: 1, west: 10, east: 11, north: 48, south: 47,
            days: []),
        days: const [],
      );

  ProviderContainer containerWith({required bool consent}) {
    final container = ProviderContainer(overrides: [
      rainCourseEnabledProvider.overrideWith((ref) => consent),
      // In umgekehrter Reihenfolge angemeldet — die Liste darf nicht
      // davon abhängen, wer zuerst fertig ist oder gefragt wird.
      modelRainStackLoaderProvider
          .overrideWithValue(() async => stack(RainStackKind.model)),
      rainStackLoaderProvider
          .overrideWithValue(() async => stack(RainStackKind.radar)),
      alpsRainStackLoaderProvider
          .overrideWithValue(() async => stack(RainStackKind.alps)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('Alpenstapel, dann Radar, dann Modell', () async {
    final stacks =
        await containerWith(consent: true).read(rainStacksProvider.future);
    expect([for (final s in stacks) s.kind],
        [RainStackKind.alps, RainStackKind.radar, RainStackKind.model]);
  });

  test('ohne Zustimmung lädt auch der Alpenstapel nicht', () async {
    final stacks =
        await containerWith(consent: false).read(rainStacksProvider.future);
    expect(stacks, isEmpty);
  });

  test('die 30-Tage-Zahl am Spot folgt demselben Vorrang', () async {
    // W4 sagt 99 mm, der Alpenstapel 30 × 2 mm. Im Grenzband zeichnet die
    // Karte den Alpenstapel — das Blatt muss dieselbe Zahl nennen.
    final alps = RainStackData(
      kind: RainStackKind.alps,
      info: const RainStackInfo(
          width: 1, height: 1, west: 10, east: 11, north: 48, south: 47,
          days: []),
      days: [
        for (var i = 0; i < 30; i++)
          (
            date: DateTime(2026, 9, 1 + i),
            gzipped: encode([
              [2]
            ]),
          ),
      ],
    );
    final w4 = RainGrid.decode(
      encode([
        [99]
      ]),
      width: 1,
      height: 1,
      west: 10,
      east: 11,
      north: 48,
      south: 47,
      measured: DateTime.utc(2026, 10, 1, 5, 50),
    );
    final container = ProviderContainer(overrides: [
      rainCourseEnabledProvider.overrideWith((ref) => true),
      rainGridLoaderProvider.overrideWithValue((_) async => w4),
      rainStackLoaderProvider.overrideWithValue(() async => null),
      modelRainStackLoaderProvider.overrideWithValue(() async => null),
      alpsRainStackLoaderProvider.overrideWithValue(() async => alps),
    ]);
    addTearDown(container.dispose);
    expect(
        await container
            .read(rainMonthAtProvider((lat: 47.5, lon: 10.5)).future),
        60);
  });

  group('Ablesung am Fadenkreuz (#652)', () {
    // Legende und Ebenen-Blatt: bis 1.222.0 nur das Radargitter, im
    // Alpenraum stand die Skala ohne Strich.
    final w4 = RainGrid.decode(
      encode([
        [99]
      ]),
      width: 1,
      height: 1,
      west: 10,
      east: 11,
      north: 48,
      south: 47,
      measured: DateTime.utc(2026, 10, 1, 5, 50),
    );
    RainStackData alpsOf(int mm) => RainStackData(
          kind: RainStackKind.alps,
          info: const RainStackInfo(
              width: 1, height: 1, west: 10, east: 11, north: 48, south: 47,
              days: []),
          days: [
            for (var i = 0; i < 30; i++)
              (
                date: DateTime(2026, 9, 1 + i),
                gzipped: encode([
                  [mm]
                ]),
              ),
          ],
        );

    Future<int?> readingAt(
      RainLayer layer, {
      RainGrid? radar,
      RainStackData? alps,
      void Function()? onAlpsLoad,
    }) async {
      final container = ProviderContainer(overrides: [
        rainGridLoaderProvider.overrideWithValue((_) async => radar),
        rainStackLoaderProvider.overrideWithValue(() async => null),
        modelRainStackLoaderProvider.overrideWithValue(() async => null),
        alpsRainStackLoaderProvider.overrideWithValue(() async {
          onAlpsLoad?.call();
          return alps;
        }),
      ]);
      addTearDown(container.dispose);
      const at = (lat: 47.5, lon: 10.5);
      final reading =
          rainMmAtProvider((layer: layer, lat: at.lat, lon: at.lon));
      final sub = container.listen(reading, (_, _) {});
      addTearDown(sub.close);
      await container.read(alpsRainSumProvider(layer).future);
      await container.read(rainGridProvider(layer).future);
      await container.read(modelRainSumProvider(layer).future);
      return container.read(reading);
    }

    test('der Alpenstapel geht vor W4', () async {
      expect(await readingAt(RainLayer.last30d, radar: w4, alps: alpsOf(2)),
          60);
    });

    test('ohne Radargitter spricht der Alpenstapel', () async {
      expect(await readingAt(RainLayer.last30d, alps: alpsOf(2)), 60);
    });

    test('schweigt der Alpenstapel, spricht W4', () async {
      expect(await readingAt(RainLayer.last30d, radar: w4), 99);
    });

    test('Radar jetzt lädt keinen Alpenstapel', () async {
      // Dort liegt das DWD-Bild, eine Ablesung gibt es nicht — und die
      // Frage danach darf keinen Tagesstapel holen.
      var loads = 0;
      expect(
          await readingAt(RainLayer.now,
              radar: w4, alps: alpsOf(2), onAlpsLoad: () => loads++),
          isNull);
      expect(loads, 0);
    });
  });
}
