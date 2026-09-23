// Die Karten-Legende mit ALLEN Ebenen zugleich (1.200.0).
//
// Bis 1.199.0 prüfte kein Test die Legende mit Regen, Wald und GBIF
// zusammen — und genau in diesem Fall lief die eingeklappte Schiene
// 11 px aus ihrem Rahmen (Betreiber-Screenshot, 2026-09-23): drei Balken
// zu 11 px plus zwei Abstände von 7 px sind 47 px, Platz war für 36.
// Jeder Test mit höchstens zwei dieser Ebenen blieb grün.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart'
    show ampelClassKeyOf, ampelClassFor;
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/gbif_finds_providers.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/map/spot_filter.dart'
    show spotFilterProvider;
import 'package:pilzbuddy/features/map/widgets/map_legend.dart'
    show MapLegend, mapIdleCenterProvider;

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';
import '../forest_grid_test.dart' show forestOf;
import '../gbif_finds_test.dart' show findsOf;
import '../rain_grid_test.dart' show gridOf;

void main() {
  const centre = LatLng(51.1634, 10.4477);

  Future<ProviderContainer> pumpAllLayers(WidgetTester tester,
      {required bool open}) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    final settings = FakeSettings(
        forestLayerEnabled: true,
        gbifLayerEnabled: true,
        ampelPreviewEnabled: true,
        ampelLayerEnabled: true,
        contourLayerEnabled: true,
        rainLayerName: 'last30d')
      ..mapLegendOpen = open;
    await pumpApp(tester, backend, settings: settings, extraOverrides: [
      forestGridLoaderProvider.overrideWithValue(() async => forestOf([
            [11, 11, 11],
            [96, 96, 96],
          ], west: 5.8, east: 15.4, north: 55.1, south: 47.0)),
      // Ein eigenes Regengitter, sonst fällt die Ebene aufs DWD-Bild
      // zurück und die Legende zeigt KEINE Regenskala — dann wären es
      // wieder nur zwei Balken, und der Fall wäre nicht gemessen.
      rainGridLoaderProvider.overrideWithValue((_) async => gridOf([
            for (var y = 0; y < 40; y++)
              [
                for (var x = 0; x < 40; x++)
                  math.max(0, 200 - 10 * math.max((x - 20).abs(), (y - 20).abs()))
              ],
          ])),
      // Steinpilz 3 + Maronenröhrling 2 (dieselbe Gruppe), Pfifferling 1
      // (1,1 km nördlich), Hallimasch 4 (ohne Gruppe) — und ein Steinpilz
      // 20 km entfernt, der NICHT zählen darf.
      gbifFindsLoaderProvider.overrideWithValue(() async => findsOf([
            (species: 0, lat: centre.latitude, lon: centre.longitude, uncertaintyM: 250, count: 3, year: 2024),
            (species: 1, lat: centre.latitude, lon: centre.longitude + 0.01, uncertaintyM: 250, count: 2, year: 2024),
            (species: 2, lat: centre.latitude + 0.01, lon: centre.longitude, uncertaintyM: 250, count: 1, year: 2021),
            (species: 3, lat: centre.latitude - 0.01, lon: centre.longitude, uncertaintyM: 250, count: 4, year: 2020),
            (species: 0, lat: centre.latitude + 0.18, lon: centre.longitude, uncertaintyM: 250, count: 50, year: 2024),
          ], species: ['Steinpilz', 'Maronenröhrling', 'Pfifferling', 'Hallimasch'])),
    ]);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(MapLegend)));
    await tester.runAsync(() => container.read(forestGridProvider.future));
    await tester.runAsync(() => container.read(gbifFindsProvider.future));
    container.read(mapIdleCenterProvider.notifier).state = centre;
    await settle(tester, frames: 12);
    return container;
  }

  /// Der Rahmen der Legende: die `Material`-Fläche, die sie trägt.
  Rect legendFrame(WidgetTester tester) => tester.getRect(find
      .descendant(of: find.byType(MapLegend), matching: find.byType(Material))
      .first);

  testWidgets('eingeklappt liegt JEDER Teil der Schiene in ihrem Rahmen — '
      'mit allen Ebenen zugleich', (tester) async {
    await pumpAllLayers(tester, open: false);
    expect(find.byKey(const Key('legend-rail-rain')), findsOneWidget,
        reason: 'ohne Regenskala misst der Test den Fall nicht');
    expect(find.byKey(const Key('legend-rail-forest')), findsOneWidget);
    expect(find.byKey(const Key('legend-rail-gbif')), findsOneWidget);

    // Gemessen am RAHMEN, nicht am Bildschirm: Die Schiene sitzt am
    // linken Rand, ein Überlauf nach rechts läge weiterhin im Bild.
    final frame = legendFrame(tester);
    expect(frame.width, 40, reason: 'die Schiene bleibt 40 px breit');
    for (final element in find
        .descendant(of: find.byType(MapLegend), matching: find.byType(Icon))
        .evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(frame.contains(rect.topLeft) && frame.contains(rect.bottomRight - const Offset(0.01, 0.01)),
          isTrue,
          reason: 'ein Symbol ragt aus der Schiene: $rect in $frame');
    }
    final gbif = tester.getRect(find.byKey(const Key('legend-rail-gbif')));
    expect(gbif.right, lessThanOrEqualTo(frame.right));
  });

  testWidgets('ausgeklappt nennt die Legende die Meldungen im Umkreis — je '
      'Gruppe, mit derselben Auswahl wie die Fläche', (tester) async {
    final container = await pumpAllLayers(tester, open: true);

    Finder countOf(String group) => find.descendant(
        of: find.ancestor(of: find.text(group), matching: find.byType(Row)).first,
        matching: find.byType(Text));
    List<String> textsIn(String group) => [
          for (final e in countOf(group).evaluate())
            (e.widget as Text).data ?? '',
        ];

    // Steinpilz 3 + Maronenröhrling 2 in derselben Gruppe; der Steinpilz
    // 20 km weiter nördlich zählt nicht.
    expect(textsIn('Steinpilz & Co.'), contains('5'));
    expect(textsIn('Pfifferling'), contains('1'));
    expect(textsIn('ohne Ampel'), contains('4'));
    expect(find.text('5 km'), findsOneWidget);

    // Kein „· 3 Ebenen" mehr — die Zahl zählte GBIF nicht mit.
    expect(find.text('Legende'), findsOneWidget);
    expect(find.textContaining('Ebenen'), findsOneWidget,
        reason: 'nur noch der Verweis „Ebenen" in der Fußzeile');

    // Gruppe abwählen: Sie verschwindet aus der Legende, und mit ihr
    // „ohne Ampel" — wie auf der Fläche.
    final pfifferling = ampelClassKeyOf(ampelClassFor('Pfifferling')!)!;
    container.read(spotFilterProvider.notifier).toggleClass(pfifferling);
    await settle(tester, frames: 6);
    expect(find.text('Pfifferling'), findsNothing);
    expect(find.text('ohne Ampel'), findsNothing);
    expect(textsIn('Steinpilz & Co.'), contains('5'));
  });
}
