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
    expect(config.onLongPress, isNotNull,
        reason: 'Seit #483 ist die Geste ab Werk AN — sie wirft die Kamera '
            'nicht mehr sofort, sondern fragt erst.');
  });

  testWidgets('Long-Press → „Heranzoomen" bewegt die Kamera',
      (tester) async {
    // Der Kamera-Vertrag über die Fassade: MapScreen → Controller →
    // Delegate der Engine. Reißt die Kette (Engine hängt sich nicht ein,
    // Controller verliert den Delegate), zielt „Neuer Spot" ins Leere.
    //
    // Seit #483 führt der Weg durchs Kontextmenü — der Nachweis wird
    // dadurch stärker, nicht schwächer: Er prüft jetzt Geste, Menü und
    // Kamera in einem.
    await pumpApp(tester, _signedIn());

    const pressed = LatLng(48.15, 11.55);
    await simulateMapLongPress(tester, pressed);
    await settle(tester);
    await tester.tap(find.text('Heranzoomen'));
    await settle(tester);

    final camera = tester.state<FakeMapViewState>(find.byType(FakeMapView));
    expect(camera.center, pressed);
    expect(camera.zoom, 16,
        reason: 'Heranzoomen zielt auf mindestens 16 (Fadenkreuz-Zoom).');
  });

  testWidgets('Das bloße Öffnen des Menüs bewegt nichts', (tester) async {
    // Die Gegenprobe, und der ganze Grund für das Menü: Ein Fehlgriff
    // darf die Orientierung nicht kosten. Bis #483 warf derselbe
    // Fehlgriff die Kamera sofort woanders hin — deshalb stand die
    // Geste seit #210 auf AUS.
    await pumpApp(tester, _signedIn());

    final before = tester.state<FakeMapViewState>(find.byType(FakeMapView));
    final center = before.center;
    final zoom = before.zoom;

    await simulateMapLongPress(tester, const LatLng(48.15, 11.55));
    await settle(tester);
    expect(find.text('Was ist hier?'), findsOneWidget);

    final after = tester.state<FakeMapViewState>(find.byType(FakeMapView));
    expect(after.center, center);
    expect(after.zoom, zoom);
  });
}
