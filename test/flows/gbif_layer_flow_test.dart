// Die Fundorte-Ebene (#467) von Hand: Ebenen-Blatt → Detailblatt → an,
// die Fläche auf der Karte, der Filter, der sie enger macht, die Legende
// — und der Umkreis im „Was ist hier?"-Blatt.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart'
    show mapIdleBoundsProvider;
import 'package:pilzbuddy/features/map/gbif_fill.dart';
import 'package:pilzbuddy/features/map/gbif_finds.dart';
import 'package:pilzbuddy/features/map/gbif_finds_providers.dart';
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart'
    show MapViewBounds;
import 'package:pilzbuddy/features/map/rain_grid.dart' show mercatorY;
import 'package:pilzbuddy/features/map/spot_filter.dart';
import 'package:pilzbuddy/features/map/widgets/map_legend.dart'
    show mapIdleCenterProvider;

import '../fakes/fake_backend.dart';
import '../fakes/map_ui.dart';
import '../fakes/test_app.dart';
import '../gbif_finds_test.dart' show findsOf;
import '../rain_fill_test.dart' show decodePng;

void main() {
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Die Kartenmitte der App ohne Standort.
  const centre = LatLng(51.1634, 10.4477);

  /// Drei Meldungen: ein Steinpilz genau in der Kartenmitte, ein
  /// Pfifferling daneben, ein Schweizer Hallimasch-Quadrat weit weg.
  GbifFinds testFinds() => findsOf([
        (species: 0, lat: centre.latitude, lon: centre.longitude, uncertaintyM: 250, count: 3, year: 2024),
        (species: 1, lat: centre.latitude + 0.01, lon: centre.longitude, uncertaintyM: 250, count: 1, year: 2021),
        (species: 2, lat: 47.0, lon: 8.0, uncertaintyM: 3535, count: 7, year: 2019),
      ], species: [
        'Steinpilz',
        'Pfifferling',
        'Hallimasch'
      ]);

  List<Override> withFinds(GbifFinds? finds) => [
        gbifFindsLoaderProvider.overrideWithValue(() async => finds),
      ];

  /// Ein Sichtfenster von ~28 × 27 km um die Kartenmitte — eng genug,
  /// dass die 250-m-Scheiben von Steinpilz und Pfifferling (1,1 km
  /// auseinander) sich nicht überlagern. Im Übersichtszoom der echten
  /// Karte lägen beide in derselben Mindest-Scheibe von 3 px, und die
  /// Mitte wäre ein Mischton.
  const testBounds = MapViewBounds(
    west: 10.2477,
    east: 10.6477,
    south: 51.0434,
    north: 51.2834,
  );

  /// Die Ebene direkt am Zustand einschalten und die Fläche abwarten.
  /// Der Kamera-Stillstand wird gesetzt statt abgewartet — ohne
  /// Sichtfenster gibt es kein Bild, und die echte Karte meldet ihn
  /// erst nach dem ersten Frame mit Größe.
  Future<void> enableLayer(WidgetTester tester, ProviderContainer container) async {
    // Erst das Asset, dann das Fenster: Der Fenster-Planer braucht die
    // Box des Assets, und ein Fill, der vor dem Asset gerechnet wird,
    // ist `null` — den Wert hätte der erste `await` sonst geliefert.
    await tester.runAsync(() => container.read(gbifFindsProvider.future));
    container.read(mapIdleBoundsProvider.notifier).state = testBounds;
    container.read(gbifLayerEnabledProvider.notifier).set(true);
    await tester.runAsync(() => container.read(gbifFillProvider.future));
    await settle(tester);
  }

  /// Pixel der Kartenmitte im Bild eines Fills.
  ({int r, int g, int b, int a}) centrePixel(GbifFillImage fill) {
    final png = decodePng(fill.png);
    final x = ((centre.longitude - fill.west) / (fill.east - fill.west) * png.width)
        .floor();
    final y = ((mercatorY(centre.latitude) - mercatorY(fill.north)) /
            (mercatorY(fill.south) - mercatorY(fill.north)) *
            png.height)
        .floor();
    final o = (y * png.width + x) * 4;
    return (
      r: png.pixels[o],
      g: png.pixels[o + 1],
      b: png.pixels[o + 2],
      a: png.pixels[o + 3],
    );
  }

  testWidgets('Ebenen → Blatt → einschalten legt die Scheiben auf die Karte',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withFinds(testFinds()));

    await openLayerSheet(tester, 'Gemeldete Fundorte');
    expect(find.text('Fundorte einblenden'), findsOneWidget);
    // Der ehrliche Satz steht im Blatt, nicht in einer Hilfeseite.
    expect(find.textContaining('Keine Scheibe heißt „keine Meldung"'),
        findsOneWidget);
    // Die Farben sind die Ampel-Gruppen.
    expect(find.text('Steinpilz & Co.'), findsOneWidget);

    final container = containerOf(tester);
    container.read(mapIdleBoundsProvider.notifier).state = testBounds;
    await tester.tap(find.text('Fundorte einblenden'));
    await tester.runAsync(() => container.read(gbifFillProvider.future));
    await settle(tester);

    // Die unteren Zeilen liegen im Blatt unter dem Falz.
    await tester.scrollUntilVisible(find.text('Arten ohne Ampel'), 60,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Arten ohne Ampel'), findsOneWidget);
    // Und die Abdeckung — aus dem Manifest, nicht erfunden.
    await tester.scrollUntilVisible(
        find.textContaining('11 Meldungen an 3 Orten'), 60,
        scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('11 Meldungen an 3 Orten'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20)); // Blatt schließen
    await settle(tester);

    expect(container.read(gbifLayerEnabledProvider), isTrue);
    final fill = container.read(gbifFillProvider).valueOrNull;
    expect(fill, isNotNull);
    // Das Fenster umfasst die Kartenmitte, und dort liegt die
    // Steinpilz-Scheibe in Rot.
    expect(fill!.north, greaterThan(centre.latitude));
    expect(fill.south, lessThan(centre.latitude));
    final pixel = centrePixel(fill);
    expect(pixel.a, greaterThan(0));
    expect(pixel.r, 0xC6);

    // Auf der Karte liegt genau ein Bild-Overlay mit den Grenzen SEINES
    // Fensters.
    final overlays = tester
        .widgetList<OverlayImageLayer>(find.byType(OverlayImageLayer))
        .toList();
    expect(overlays, hasLength(1));
    final image = overlays.single.overlayImages.single as OverlayImage;
    expect(image.bounds.north, fill.north);
    expect(image.bounds.west, fill.west);

    // Die Legende nennt die Ebene samt Gruppenfarben.
    expect(find.text('Gemeldete Fundorte (GBIF)'), findsOneWidget);
    expect(find.text('ohne Ampel'), findsOneWidget);
  });

  testWidgets('der Kartenfilter macht die Fläche enger — Art und Gruppe',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withFinds(testFinds()));
    final container = containerOf(tester);
    await enableLayer(tester, container);
    expect(centrePixel(container.read(gbifFillProvider).valueOrNull!).a,
        greaterThan(0));

    // Nur Pfifferling: Der Steinpilz in der Mitte verschwindet.
    container.read(spotFilterProvider.notifier).toggleSpecies('Pfifferling');
    await tester.runAsync(() => container.read(gbifFillProvider.future));
    await settle(tester);
    var fill = container.read(gbifFillProvider).valueOrNull!;
    expect(centrePixel(fill).a, 0);
    expect(fill.filterKey.species, 'Pfifferling');
    // Der Filter-Chip nennt es (#154) — derselbe Chip wie für die Spots.
    expect(find.textContaining('Pfifferling'), findsWidgets);

    // Filter weg, dafür Gruppe „Steinpilz & Co." abgewählt: wieder weg.
    container.read(spotFilterProvider.notifier).clearSpecies();
    container.read(spotFilterProvider.notifier).toggleClass('herbst');
    await tester.runAsync(() => container.read(gbifFillProvider.future));
    await settle(tester);
    fill = container.read(gbifFillProvider).valueOrNull!;
    expect(centrePixel(fill).a, 0);
    expect(fill.filterKey.classes, isNot(contains('herbst')));

    // Zwei Bilder, zwei Dateinamen: Sonst tauscht MapLibre nicht.
    final first = gbifFillVariant(
        container.read(gbifFillProvider).valueOrNull!);
    container.read(spotFilterProvider.notifier).toggleClass('herbst');
    await tester.runAsync(() => container.read(gbifFillProvider.future));
    await settle(tester);
    expect(gbifFillVariant(container.read(gbifFillProvider).valueOrNull!),
        isNot(first));
  });

  testWidgets('„Was ist hier?" zählt, was im Umkreis gemeldet ist',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        useRealMap: true, extraOverrides: withFinds(testFinds()));
    final container = containerOf(tester);
    await enableLayer(tester, container);
    container.read(mapIdleCenterProvider.notifier).state = centre;
    await settle(tester);

    await tester.tap(find.text('Was ist hier? →'));
    await settle(tester);
    expect(find.text('Im Umkreis von 5 km gemeldet (GBIF)'), findsOneWidget);
    // Der Steinpilz dreimal, zuletzt 2024; der Pfifferling einmal — und
    // das Schweizer Quadrat 400 km weiter nicht.
    expect(find.text('Steinpilz'), findsOneWidget);
    expect(find.text('3× · zuletzt 2024'), findsOneWidget);
    expect(find.text('1× · zuletzt 2021'), findsOneWidget);
    expect(find.text('Hallimasch'), findsNothing);
  });

  testWidgets('ohne Asset sagt das Blatt es und schaltet nicht', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withFinds(null));
    await openLayerSheet(tester, 'Gemeldete Fundorte');
    expect(find.textContaining('lassen sich nicht laden'), findsOneWidget);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.onChanged, isNull);
    expect(tile.value, isFalse);
  });

  test('die Deckkraft bleibt unter der Lesbarkeitsgrenze der Karte', () {
    // Dieselbe Obergrenze wie bei allen Flächen: Wege und Ortsnamen
    // müssen lesbar bleiben. 175 liegt unter den 215 der Ampel-Stufe
    // „günstig", die die höchste Deckkraft der Karte ist.
    expect(gbifMaxAlpha, lessThanOrEqualTo(215));
    expect(gbifCoarseAlpha, lessThan(gbifSharpAlpha));
  });
}
