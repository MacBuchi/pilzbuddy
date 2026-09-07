// Die Stelle eines NEUEN Spots, durch die echte Oberfläche (#407).
//
// Der Wunsch: „Ein Verschieben auf der Detailkarte lässt die finale
// Position bestimmen." Der teure Fehler dabei wäre nicht, dass sich
// nichts verschieben lässt — sondern dass es sich verschieben lässt und
// trotzdem woanders gespeichert wird. Genau das war der Zustand davor:
// Das Blatt gab nur Name und Funde zurück, die Aufrufer nahmen ihre
// eigene Koordinate.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/widgets/mini_map.dart';
import 'package:pilzbuddy/features/map/widgets/spot_position_field.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> openNewSpot(WidgetTester tester) async {
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
  }

  testWidgets('Das Anlegen-Blatt zeigt eine Karte zum Verschieben',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openNewSpot(tester);

    expect(find.byType(SpotPositionField), findsOneWidget);
    final map = tester.widget<MiniMap>(find.byType(MiniMap));
    expect(map.mode, MiniMapMode.pick,
        reason: 'die Mitte des Ausschnitts IST die Wahl');
  });

  testWidgets('Eine verschobene Stelle wird auch dort gespeichert',
      (tester) async {
    // Die eigentliche Zusage. Vorher nahm der Karten-Screen `center` —
    // die Verschiebung war sichtbar und wirkungslos.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openNewSpot(tester);

    const moved = LatLng(48.5, 11.5);
    tester
        .widget<MiniMap>(find.byType(MiniMap))
        .onCenterChanged!(moved);
    await settle(tester);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final spot = backend.spots.single;
    expect(spot.lat, closeTo(48.5, 1e-9));
    expect(spot.lng, closeTo(11.5, 1e-9));
    await drainSnackbars(tester);
  });

  testWidgets('Ohne Verschieben bleibt es beim Fadenkreuz', (tester) async {
    // Die Gegenrichtung: Der Normalfall darf sich nicht ändern.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openNewSpot(tester);

    // `reference` ist das Fadenkreuz, mit dem das Blatt geöffnet wurde —
    // also genau der Ort, an dem der Spot ohne Zutun landen muss.
    final crosshair = tester.widget<MiniMap>(find.byType(MiniMap)).reference;

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final spot = backend.spots.single;
    expect(spot.lat, closeTo(crosshair.latitude, 1e-9));
    expect(spot.lng, closeTo(crosshair.longitude, 1e-9));
    await drainSnackbars(tester);
  });

  testWidgets('Das Blatt fragt beim Öffnen NIE nach der Berechtigung',
      (tester) async {
    // Dieselbe Zusage wie im Fund-Blatt — und sie wird nicht vererbt,
    // weil dies eine eigene Oberfläche ist. Daran hängt der Abschnitt
    // „Prominent Disclosure" in docs/play-console.md.
    final (backend, _) = loggedInBackend();
    final fix = FakePositionFix(fakePosition(51.0, 11.0));
    await pumpApp(tester, backend, positionFix: fix);

    await openNewSpot(tester);

    expect(fix.calls, 0);
  });

  testWidgets('„Meine Position" fragt — und setzt die Stelle', (tester) async {
    final (backend, _) = loggedInBackend();
    final fix = FakePositionFix(fakePosition(49.25, 12.75));
    await pumpApp(tester, backend, positionFix: fix);
    await openNewSpot(tester);

    await tester.tap(find.text('Meine Position'));
    await settle(tester);
    expect(fix.calls, 1, reason: 'der Systemdialog gehört hinter einen Tipp');

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final spot = backend.spots.single;
    expect(spot.lat, closeTo(49.25, 1e-9));
    expect(spot.lng, closeTo(12.75, 1e-9));
    await drainSnackbars(tester);
  });
}
