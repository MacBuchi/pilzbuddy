// Standort-Marker: Tropfen mit Spitze auf der Koordinate (#403).
//
// Der Betreiber hat beim Standort-Teilen drei Dinge gemeldet: Der eigene
// Marker sei von dem eines Buddys kaum zu unterscheiden, er liege
// dahinter, und ein Kreis über der Koordinate zeige nicht, WO jemand
// steht. Dieser Test hält alle drei fest.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/core/widgets/location_pin.dart';
import 'package:pilzbuddy/features/map/map_view/map_view.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/test_app.dart';

void main() {
  MapViewMarkers markersOf(WidgetTester tester) =>
      tester.widget<FakeMapView>(find.byType(FakeMapView)).markers;

  Future<FakeBackend> withFriendNearby(WidgetTester tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final lilli = backend.addUser(username: 'lilli');
    backend.signInAs(me.id);
    backend.addFriendship(lilli.id, me.id);
    backend.addLiveShare(lilli.id, lat: 51.0, lng: 11.0);
    return backend;
  }

  testWidgets('beide Standort-Marker hängen mit der Spitze am Punkt',
      (tester) async {
    final backend = await withFriendNearby(tester);
    await pumpApp(tester, backend, position: fakePosition(51.001, 11.001));
    await settle(tester);

    final markers = markersOf(tester);
    expect(markers.myPosition, hasLength(1));
    expect(markers.friendLocations, hasLength(1));

    for (final marker in [
      ...markers.myPosition,
      ...markers.friendLocations,
    ]) {
      // `topCenter` heißt: Der Punkt liegt an der UNTERKANTE des Markers
      // — also genau dort, wo die Spitze sitzt. Mit `center` (dem
      // Vorgabewert bis 1.119.1) schwebte der Marker mittig über der
      // Koordinate, und ein 40-px-Kreis deckt bei gewöhnlichem Zoom ein
      // halbes Fußballfeld ab.
      expect(marker.alignment, Alignment.topCenter);
      // Und die Box muss so hoch sein, wie der Tropfen zeichnet: Wäre
      // sie quadratisch, endete die Spitze mitten im Marker und die
      // Ausrichtung zeigte auf die falsche Stelle.
      expect(marker.height,
          closeTo(marker.width * LocationPin.pinHeightFactor, 0.001));
    }
  });

  testWidgets('meiner ist grün, der des Buddys blau', (tester) async {
    // Vorher unterschieden sie sich nur durch einen 2,5-px-Ring um ein
    // Pilz-Porträt; bei ähnlichen Avataren sah das gleich aus. Grün =
    // meins, Blau = Buddy ist dieselbe Sprache wie die Boden-Ellipse an
    // den Spots.
    final backend = await withFriendNearby(tester);
    await pumpApp(tester, backend, position: fakePosition(51.001, 11.001));
    await settle(tester);

    final pins = tester
        .widgetList<LocationPin>(find.byType(LocationPin))
        .map((p) => p.color)
        .toList();
    expect(pins, containsAll([AppColors.forestGreen, AppColors.friendBlue]));
  });

  testWidgets('mein Marker liegt VOR dem des Buddys', (tester) async {
    // Wer zusammen sucht, steht dicht beieinander — genau dann verschwand
    // der eigene Punkt unter dem fremden, also im einzigen Moment, in dem
    // man beide auseinanderhalten will.
    final backend = await withFriendNearby(tester);
    await pumpApp(tester, backend, position: fakePosition(51.0005, 11.0005));
    await settle(tester);

    final colors = tester
        .widgetList<LocationPin>(find.byType(LocationPin))
        .map((p) => p.color)
        .toList();
    expect(colors.last, AppColors.forestGreen,
        reason: 'zuletzt gezeichnet heißt obenauf');
  });

  test('beide Engines stapeln in derselben Reihenfolge', () {
    // Eine TEXTPRÜFUNG, und sie weiß es: Die Stapelung steht an drei
    // Stellen — in beiden Engines und im Fake — und kein Compiler liest
    // sie. Die Widget-Tests oben laufen gegen den Fake; wäre eine echte
    // Engine anders herum, bliebe alles grün und auf dem Gerät läge der
    // eigene Marker wieder hinten.
    //
    // Was sie NICHT beweist: dass die Engines wirklich so zeichnen. Das
    // sieht nur die Sichtprüfung.
    for (final path in const [
      'lib/features/map/map_view/flutter_map_view.dart',
      'lib/features/map/map_view/maplibre_map_view.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final friends = source.indexOf('markers.friendLocations');
      final mine = source.indexOf('markers.myPosition');
      expect(friends, greaterThan(-1), reason: path);
      expect(mine, greaterThan(-1), reason: path);
      expect(friends, lessThan(mine),
          reason: 'in $path müssen die Buddys VOR der eigenen Position '
              'gezeichnet werden — später heißt weiter oben');
    }
  });
}
