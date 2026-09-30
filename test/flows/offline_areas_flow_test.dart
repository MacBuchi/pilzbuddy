// Gespeicherte Kartenbereiche (#630, Stufe 2) aus Sicht des Nutzers: der
// Eintrag im Profil erscheint erst mit der Neuen Karte (oder wenn schon
// ein Bereich liegt), Speichern misst zuerst und fragt dann, der Bereich
// landet in der Liste, und Löschen räumt ihn ab.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart';
import 'package:pilzbuddy/features/map/online_map.dart';
import 'package:pilzbuddy/features/offline_areas/area_plan.dart';
import 'package:pilzbuddy/features/offline_areas/area_providers.dart';
import 'package:pilzbuddy/features/offline_areas/area_store.dart';
import 'package:pilzbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:pmtiles/pmtiles.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

const _view = MapViewBounds(west: 11.6, east: 11.7, south: 47.9, north: 47.95);

/// Ein kleines Host-Archiv (Zoom 8–10) statt des Kartenservers.
Future<PmTilesArchive> _host(Uri _) async {
  const wide = AreaBounds(south: 47.0, west: 10.0, north: 48.5, east: 12.5);
  return PmTilesArchive.fromBytes(writePmTiles(
      tiles: [
        for (final t in tilesCovering(wide, maxZoom: 10))
          TileToWrite(t.z, t.x, t.y,
              Uint8List.fromList(utf8.encode('t${t.z}/${t.x}/${t.y}'))),
      ],
      tileCompression: Compression.none,
      bounds: const TileBounds(west: 10, south: 47, east: 12.5, north: 48.5)));
}

FakeBackend _signedIn() {
  final backend = FakeBackend();
  final me = backend.addUser(username: 'testpilz');
  backend.signInAs(me.id);
  return backend;
}

List<Override> _host10() => [
      mapManifestLoaderProvider.overrideWithValue(() async => const MapManifest(
          file: 'dach-20260928.pmtiles', maxZoom: 10, sourceBuild: '20260928')),
      areaSourceOpenerProvider.overrideWithValue(_host),
      // Die Online-Karte selbst bleibt hier aus dem Spiel — es geht um
      // das Speichern, und ihr Archiv hinge sonst am selben Fake.
      onlineMapProvider.overrideWith((ref) async => null),
      mapIdleBoundsProvider.overrideWith((ref) => _view),
    ];

Future<void> _openAreas(WidgetTester tester) async {
  await openTab(tester, 'Profil');
  final tile = find.text('Kartenbereiche');
  await tester.scrollUntilVisible(tile, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(tile);
  await settle(tester);
  await tester.tap(tile);
  await settle(tester);
}

void main() {
  testWidgets('ohne Neue Karte und ohne Bereich: kein Eintrag im Profil',
      (tester) async {
    await pumpApp(tester, _signedIn());
    await openTab(tester, 'Profil');
    await tester.scrollUntilVisible(find.text('Was ist neu'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Kartenbereiche'), findsNothing);
  });

  testWidgets('Ausschnitt speichern: messen, fragen, speichern, löschen',
      (tester) async {
    final store = MemoryAreaStore();
    final keepAlive = FakeKeepAlive();
    await pumpApp(tester, _signedIn(),
        settings: FakeSettings(newMapEnabled: true),
        areaStore: store,
        keepAlive: keepAlive,
        extraOverrides: _host10());
    await _openAreas(tester);

    expect(find.text('Noch kein Bereich gespeichert.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('areas-save-view')));
    await settle(tester);

    // Der Dialog nennt die gemessene Größe, bevor ein Byte fließt.
    expect(find.text('Bereich speichern?'), findsOneWidget);
    expect(find.textContaining('Kacheln, bis Zoomstufe 10'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('area-name')), 'Hausrunde');
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 20);

    expect(store.areas.single.name, 'Hausrunde');
    expect(store.archives, contains(store.areas.single.id));
    expect(find.text('Hausrunde'), findsOneWidget);
    expect(keepAlive.running, isFalse,
        reason: 'der Vordergrunddienst endet mit dem Download');

    await tester.tap(find.byTooltip('Bereich löschen'));
    await settle(tester);
    await tester.tap(find.text('Löschen'));
    await settle(tester);
    expect(store.areas, isEmpty);
    expect(find.text('Noch kein Bereich gespeichert.'), findsOneWidget);
  });

  testWidgets(
      'ein liegender Bereich bleibt ohne Neue Karte erreichbar — speichern '
      'nicht', (tester) async {
    final store = MemoryAreaStore()
      ..areas = [
        StoredArea(
          id: 'a1',
          name: 'Alter Bereich',
          bounds: const AreaBounds(
              south: 47.9, west: 11.6, north: 47.95, east: 11.7),
          minZoom: 8,
          maxZoom: 13,
          build: '20260928',
          tiles: 10,
          bytes: 1000,
          savedAt: DateTime.utc(2026, 9, 30),
        ),
      ];
    await pumpApp(tester, _signedIn(),
        areaStore: store,
        extraOverrides: [
          // Kein echtes Archiv im Speicher: die Kartenschicht bleibt leer.
          areaMapStyleProvider.overrideWith((ref) async => null),
        ]);
    await _openAreas(tester);

    expect(find.text('Alter Bereich'), findsOneWidget);
    expect(find.byKey(const ValueKey('areas-need-new-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('areas-save-view')), findsNothing);
    expect(find.byTooltip('Neu laden (aktueller Kartenstand)'), findsNothing,
        reason: 'Aktualisieren fragt den Kartenserver');
    expect(find.byTooltip('Bereich löschen'), findsOneWidget);
  });
}
