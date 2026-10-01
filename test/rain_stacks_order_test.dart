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
}
