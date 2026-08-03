// Die Regenebene von der Karte aus: Knopf → Blatt → Wahl → Ebene liegt
// auf der Karte. Der Weg wird hier ganz gegangen, weil die einzelnen
// Teile ihn nicht beweisen: Ein korrekt gebautes GetMap nützt nichts,
// wenn der Knopf das falsche Blatt öffnet oder die Wahl nirgends ankommt.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  FakeBackend loggedIn() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  testWidgets('Vorgabe ist aus — niemand lädt ungefragt ein Regenbild',
      (tester) async {
    await pumpApp(tester, loggedIn());
    expect(containerOf(tester).read(rainLayerProvider), RainLayer.off);
  });

  testWidgets('Knopf öffnet das Blatt, die Wahl kommt an', (tester) async {
    await pumpApp(tester, loggedIn());

    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    expect(find.text('Letzte 30 Tage'), findsOneWidget);

    await tester.tap(find.text('Letzte 30 Tage'));
    await settle(tester);

    expect(containerOf(tester).read(rainLayerProvider), RainLayer.last30d);
  });

  testWidgets('Das Blatt nennt den Geltungsbereich, sobald eine Ebene liegt',
      (tester) async {
    await pumpApp(tester, loggedIn());
    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);

    // Ohne Ebene keine Legende und kein Geltungsbereich.
    expect(find.textContaining('Nur Deutschland'), findsNothing);

    await tester.tap(find.text('Letzte 24 Stunden'));
    await settle(tester);

    expect(find.textContaining('Nur Deutschland'), findsOneWidget,
        reason: 'Ohne diesen Satz sieht eine leere Fläche in Österreich '
            'nach einem Fehler der App aus.');
  });

  testWidgets('Aus nimmt die Ebene wieder weg', (tester) async {
    await pumpApp(tester, loggedIn());
    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    await tester.tap(find.text('Jetzt'));
    await settle(tester);
    await tester.tap(find.text('Aus'));
    await settle(tester);

    expect(containerOf(tester).read(rainLayerProvider), RainLayer.off);
  });

  testWidgets('flutter_map (der Web-Pfad) hängt die Ebene wirklich ein',
      (tester) async {
    await pumpApp(tester, loggedIn(), useRealMap: true);
    expect(find.byType(OverlayImageLayer), findsNothing);

    containerOf(tester).read(rainLayerProvider.notifier).state =
        RainLayer.last30d;
    await settle(tester);

    final layer =
        tester.widget<OverlayImageLayer>(find.byType(OverlayImageLayer));
    final image = layer.overlayImages.single as OverlayImage;
    expect(image.bounds.north, RainLayer.last30d.bounds.north);
    expect(image.opacity, RainLayer.last30d.opacity);
    expect(image.filterQuality, FilterQuality.none,
        reason: 'Weichgezeichnet sähe das 1-km-Raster genauer aus, als es '
            'ist — dieselbe Regel wie raster-resampling: nearest bei '
            'MapLibre.');
  });

  testWidgets('Die Regenebene liegt UNTER den Spot-Markern', (tester) async {
    // Ein Spot, der hinter dem Regen verschwindet, wäre genau dann
    // unauffindbar, wenn man ihn braucht.
    final backend = loggedIn();
    backend.addSpot(
      ownerId: backend.currentUserId!,
      lat: 48.1,
      lng: 11.5,
      name: 'Buchenhang',
      species: 'Steinpilz',
    );
    await pumpApp(tester, backend, useRealMap: true);
    containerOf(tester).read(rainLayerProvider.notifier).state = RainLayer.now;
    await settle(tester);

    final children = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .children
        .map((w) => w.runtimeType)
        .toList();
    final rain = children.indexOf(OverlayImageLayer);
    // Zuerst: Ist sie überhaupt da? Ohne diese Zeile wäre der Vergleich
    // unten wahr, sobald die Ebene FEHLT (indexOf liefert dann −1) — der
    // Test ginge also gerade dann durch, wenn nichts mehr funktioniert.
    expect(rain, isNonNegative);
    expect(rain, lessThan(children.lastIndexOf(MarkerLayer)));
  });
}
