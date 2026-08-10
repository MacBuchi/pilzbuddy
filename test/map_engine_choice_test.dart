// Die Engine-Wahl der MapView-Fassade: Seit der Abnahme des
// Direktvergleichs (docs/map-performance.md) ist MapLibre auf Android
// Standard; der Profil-Schalter ist ein Opt-out zur bisherigen
// flutter_map-Karte (Rückfalllinie). Die Wahl ist ein Provider, damit
// ein Umschalten im Profil die Karte sofort wechselt.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_settings.dart';

void main() {
  final config = const MapViewConfig(
    initialCenter: LatLng(51.1634, 10.4477),
    initialZoom: 6.5,
    minZoom: 3,
    maxZoom: 19,
    backgroundColor: AppColors.mapBackground,
  );

  Widget buildWith({required bool classicMapEnabled}) {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWithValue(
          FakeSettings(classicMapEnabled: classicMapEnabled)),
    ]);
    addTearDown(container.dispose);
    final controller =
        MapViewController(initialCenter: config.initialCenter, initialZoom: 6.5);
    return container.read(mapViewBuilderProvider)(
        config, controller, const MapViewMarkers());
  }

  test('Standard ist die MapLibre-Engine', () {
    expect(buildWith(classicMapEnabled: false), isA<MapLibreMapView>());
  });

  test('Opt-out wählt die bisherige flutter_map-Karte (Rückfalllinie)', () {
    expect(buildWith(classicMapEnabled: true), isA<FlutterMapView>());
  });

  test('Schalter-Zustand kommt aus den Einstellungen und lässt sich togglen',
      () {
    final settings = FakeSettings();
    final container = ProviderContainer(
        overrides: [settingsProvider.overrideWithValue(settings)]);
    addTearDown(container.dispose);
    expect(container.read(mapLibreEnabledProvider), isTrue);
    container.read(mapLibreEnabledProvider.notifier).toggle();
    expect(container.read(mapLibreEnabledProvider), isFalse);
    expect(settings.classicMapEnabled, isTrue,
        reason: 'Die Wahl muss den Neustart überdauern (gleiches Muster '
            'wie die Offline-Karte, Issue #145).');
  });

  test('Der alte Beta-Schlüssel wird ignoriert — jedes Gerät landet beim '
      'Update auf der neuen Engine', () async {
    // Während der Beta-Phase (1.39.0–1.42.0) speicherte der Opt-in-Schalter
    // unter 'maplibre_enabled'. Ein dort hinterlegtes false darf die neue
    // Standard-Engine NICHT abschalten: Das Opt-out ist eine frische,
    // bewusste Entscheidung unter neuem Schlüssel.
    SharedPreferences.setMockInitialValues({'maplibre_enabled': false});
    final prefs = await SharedPreferences.getInstance();
    final settings = PrefsSettings(prefs);
    expect(settings.classicMapEnabled, isFalse,
        reason: 'Der Beta-Schlüssel darf nicht als Opt-out weiterwirken.');
  });
}
