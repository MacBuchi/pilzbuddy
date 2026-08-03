// Die Engine-Wahl der MapView-Fassade: flutter_map ist Standard, MapLibre
// kommt nur per Opt-in-Schalter (Beta) — und die Wahl ist ein Provider,
// damit ein Umschalten im Profil die Karte sofort wechselt.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/map/map_view/flutter_map_view.dart';
import 'package:pilzbuddy/features/map/map_view/map_engine.dart';
import 'package:pilzbuddy/features/map/map_view/map_view.dart';
import 'package:pilzbuddy/features/map/map_view/maplibre_map_view.dart';

import 'fakes/fake_settings.dart';

void main() {
  final config = MapViewConfig(
    initialCenter: const LatLng(51.1634, 10.4477),
    initialZoom: 6.5,
    minZoom: 3,
    maxZoom: 19,
    backgroundColor: AppColors.mapBackground,
  );

  Widget buildWith({required bool mapLibreEnabled}) {
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWithValue(FakeSettings(mapLibreEnabled: mapLibreEnabled)),
    ]);
    addTearDown(container.dispose);
    final controller =
        MapViewController(initialCenter: config.initialCenter, initialZoom: 6.5);
    return container.read(mapViewBuilderProvider)(
        config, controller, const MapViewMarkers());
  }

  test('Standard bleibt flutter_map', () {
    expect(buildWith(mapLibreEnabled: false), isA<FlutterMapView>());
  });

  test('Opt-in-Schalter wählt die MapLibre-Engine', () {
    expect(buildWith(mapLibreEnabled: true), isA<MapLibreMapView>());
  });

  test('Schalter-Zustand kommt aus den Einstellungen und lässt sich togglen',
      () {
    final settings = FakeSettings(mapLibreEnabled: false);
    final container = ProviderContainer(
        overrides: [settingsProvider.overrideWithValue(settings)]);
    addTearDown(container.dispose);
    expect(container.read(mapLibreEnabledProvider), isFalse);
    container.read(mapLibreEnabledProvider.notifier).toggle();
    expect(container.read(mapLibreEnabledProvider), isTrue);
    expect(settings.mapLibreEnabled, isTrue,
        reason: 'Die Wahl muss den Neustart überdauern (gleiches Muster '
            'wie die Offline-Karte, Issue #145).');
  });
}
