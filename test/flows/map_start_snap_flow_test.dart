// Beim Start einmal auf die eigene Position einrasten (#360).
//
// Der Betreiber: „Bei Start einrasten auf GPS Position (einmalig, nicht
// dauernd umspringen). Kann aber weiter entfernt sein als bei Drücken des
// GPS-Buttons." Genau diese drei Aussagen stehen hier als Tests — der
// Sprung passiert, er passiert weiter draußen als „Auf mich zentrieren",
// und er passiert genau einmal.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/position_provider.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/test_app.dart';

void main() {
  // Die Startansicht der Karte: Mitte Deutschlands, Zoom 6,5.
  const startCenter = LatLng(51.1634, 10.4477);
  const startZoom = 6.5;

  FakeMapViewState camera(WidgetTester tester) =>
      tester.state<FakeMapViewState>(find.byType(FakeMapView));

  FakeBackend signedIn() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  testWidgets('steht eine Position bereit, rastet die Karte beim Start '
      'darauf ein', (tester) async {
    await pumpApp(tester, signedIn(), position: fakePosition(48.2, 11.6));

    expect(camera(tester).center, const LatLng(48.2, 11.6));
    // Weiter weg als „Auf mich zentrieren" (15) — der Start zeigt die
    // Gegend, nicht den Fleck, auf dem man steht. Rund 10 km Umkreis.
    expect(camera(tester).zoom, 10.0);
  });

  testWidgets('ohne Position bleibt die Karte auf der Startansicht',
      (tester) async {
    await pumpApp(tester, signedIn());

    expect(camera(tester).center, startCenter);
    expect(camera(tester).zoom, startZoom);
  });

  testWidgets('auch der zweite Start in derselben Sitzung rastet ein',
      (tester) async {
    // Wer sich abmeldet und wieder anmeldet, bekommt einen frischen
    // Karten-Screen — der Positionsstrom aber lebt weiter und hält seinen
    // letzten Wert. Ein `ref.listen` feuert dann NIE, weil sich nichts
    // ändert; nur das Nachsehen beim ersten Frame findet ihn noch. Ohne
    // das bliebe die Karte nach dem Wiederanmelden auf Deutschland
    // stehen, bis das GPS von sich aus etwas Neues meldet — und wer
    // stillsteht, wartet darauf lange (`distanceFilter: 10`).
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    final fixes = StreamController<Position?>();
    addTearDown(fixes.close);
    await pumpApp(tester, backend, extraOverrides: [
      positionStreamProvider.overrideWith((ref) => fixes.stream),
    ]);

    fixes.add(fakePosition(48.2, 11.6));
    await settle(tester);
    expect(camera(tester).center, const LatLng(48.2, 11.6));

    backend.setCurrentUser(null, AuthChangeEvent.signedOut);
    await settle(tester);
    expect(find.text('Anmelden'), findsOneWidget, reason: 'abgemeldet');
    backend.setCurrentUser(me, AuthChangeEvent.signedIn);
    await settle(tester);

    // KEIN neuer Fix — der alte steht noch im Strom.
    expect(camera(tester).center, const LatLng(48.2, 11.6));
    expect(camera(tester).zoom, 10.0);
  });

  testWidgets('wer schon geschoben hat, wird vom ersten Fix nicht '
      'weggerissen', (tester) async {
    // Der Fix kommt unter Blätterdach erst nach Sekunden — deshalb hier
    // von Hand gesteuert statt über `position:`, das ihn sofort liefert.
    final fixes = StreamController<Position?>();
    addTearDown(fixes.close);
    await pumpApp(tester, signedIn(), extraOverrides: [
      positionStreamProvider.overrideWith((ref) => fixes.stream),
    ]);

    // Der Nutzer sieht sich inzwischen eine andere Gegend an.
    camera(tester).move(const LatLng(53.5, 9.9), 12);
    fixes.add(fakePosition(48.2, 11.6));
    await settle(tester);

    expect(camera(tester).center, const LatLng(53.5, 9.9),
        reason: 'der Fix darf die Karte nicht unter der Hand wegziehen');

    // Und die Gelegenheit ist damit verbraucht, obwohl gar nichts
    // gesprungen ist: Wer später zufällig wieder auf der Startansicht
    // landet, soll vom nächsten Fix nicht doch noch weggezogen werden.
    // Beim Gehen meldet das GPS alle paar Meter.
    camera(tester).move(startCenter, startZoom);
    fixes.add(fakePosition(48.3, 11.7));
    await settle(tester);

    expect(camera(tester).center, startCenter,
        reason: 'einmal gefragt, einmal beantwortet');
  });

  testWidgets('eingerastet wird genau einmal, nicht bei jedem Fix',
      (tester) async {
    final fixes = StreamController<Position?>();
    addTearDown(fixes.close);
    await pumpApp(tester, signedIn(), extraOverrides: [
      positionStreamProvider.overrideWith((ref) => fixes.stream),
    ]);

    fixes.add(fakePosition(48.2, 11.6));
    await settle(tester);
    expect(camera(tester).center, const LatLng(48.2, 11.6),
        reason: 'der erste Fix rastet ein');

    // Danach sieht sich der Nutzer woanders um, und das GPS meldet
    // weiter — beim Gehen tut es das alle paar Meter.
    camera(tester).move(const LatLng(53.5, 9.9), 12);
    fixes.add(fakePosition(48.3, 11.7));
    await settle(tester);

    expect(camera(tester).center, const LatLng(53.5, 9.9),
        reason: 'einmalig, nicht dauernd umspringen');
  });
}
