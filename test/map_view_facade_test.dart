// Die MapView-Fassade: MapScreen beschreibt die Karte engine-neutral,
// die Engine dahinter ist austauschbar (flutter_map heute, MapLibre im
// Migrationsplan, hier die Fake). Diese Tests beweisen die Fassaden-Seite
// des Vertrags — die flutter_map-Seite beweisen map_view_test.dart & Co.
// mit `useRealMap: true`.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/core/app_colors.dart';

import 'fakes/fake_backend.dart';
import 'fakes/fake_map_view.dart';
import 'fakes/fake_settings.dart';
import 'fakes/test_app.dart';

FakeBackend _signedIn() {
  final backend = FakeBackend();
  backend.signInAs(backend.addUser(username: 'testpilz').id);
  return backend;
}

void main() {
  testWidgets('MapScreen konfiguriert die Karte engine-neutral',
      (tester) async {
    // Diese Werte gelten für JEDE Engine — die flutter_map-Seite
    // (Config → MapOptions) prüft map_view_test.dart.
    await pumpApp(tester, _signedIn());

    final config =
        tester.widget<FakeMapView>(find.byType(FakeMapView)).config;
    expect(config.minZoom, 3);
    expect(config.maxZoom, 19);
    expect(config.backgroundColor, AppColors.mapBackground);
    expect(config.onLongPress, isNull,
        reason: 'Ab Werk keine Long-Press-Geste (#210) — der Fehlgriff ist '
            'damit unmöglich, nicht bloß selten.');
  });

  testWidgets('Eingeschaltet bewegt der Long-Press die Kamera',
      (tester) async {
    // Der Kamera-Vertrag über die Fassade: MapScreen → Controller →
    // Delegate der Engine. Reißt die Kette (Engine hängt sich nicht ein,
    // Controller verliert den Delegate), zielt „Neuer Spot" ins Leere.
    // Seit #210 hängt die Geste am Schalter, also mit ihm geprüft — sonst
    // stünde dieser Nachweis nicht mehr zur Verfügung.
    await pumpApp(tester, _signedIn(),
        settings: FakeSettings(mapLongPressEnabled: true));

    const pressed = LatLng(48.15, 11.55);
    await simulateMapLongPress(tester, pressed);

    final camera = tester.state<FakeMapViewState>(find.byType(FakeMapView));
    expect(camera.center, pressed);
    expect(camera.zoom, 16,
        reason: 'Long-Press zoomt auf mindestens 16 heran (Fadenkreuz-Zoom).');
  });

  testWidgets('Ohne Schalter bleibt die Kamera stehen', (tester) async {
    // Die Gegenprobe zum Test darüber, mit demselben Auslöser: Der Fake
    // ruft den Rückruf, aber es gibt keinen — die Kamera darf sich nicht
    // rühren.
    await pumpApp(tester, _signedIn());

    final before = tester.state<FakeMapViewState>(find.byType(FakeMapView));
    final center = before.center;
    final zoom = before.zoom;

    await simulateMapLongPress(tester, const LatLng(48.15, 11.55));

    final after = tester.state<FakeMapViewState>(find.byType(FakeMapView));
    expect(after.center, center);
    expect(after.zoom, zoom);
  });
}
