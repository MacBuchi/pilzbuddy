// Die Online-Karte vom Kartenhost (#630, Stufe 1): das Manifest, das ein
// ANDERES Repo schreibt (TrailBuddys `map-data.yml`), und die eine Regel,
// wann gefragt wird und wann OSM bleibt.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show ThemeLayerType;
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/map/online_map.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:pilzbuddy/features/offline_maps/pmtiles_tile_provider.dart';

import 'fakes/fake_settings.dart';

/// `dach.json` in der Form, die TrailBuddys `map-data.yml` am 2026-09-28
/// geschrieben hat (Feldnamen aus dem Workflow, Werte aus dem ersten
/// veröffentlichten Stand). Ändert TrailBuddy die Form, soll DIESER Test
/// es sagen — nicht ein Nutzer, dessen Vorschau still zur alten Karte
/// wird.
const _recorded = {
  'format': 1,
  'file': 'dach-20260928.pmtiles',
  'bytes': 2800000000,
  'maxzoom': 13,
  'source_build': '20260928',
};

const _manifest = MapManifest(
    file: 'dach-20260928.pmtiles', maxZoom: 13, sourceBuild: '20260928');

/// Ein echtes, kleines Archiv für den Öffner: die mitgelieferte Übersicht.
Future<PmTilesVectorTileProvider> _openOverview(Uri _) async =>
    PmTilesVectorTileProvider.openBytes(
        await File('assets/offline_maps/overview_dach.pmtiles').readAsBytes());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('das Manifest in TrailBuddys heutiger Form wird gelesen', () {
    final m = MapManifest.fromJson(Map<String, dynamic>.from(_recorded));
    expect(m.file, 'dach-20260928.pmtiles');
    expect(m.maxZoom, 13);
    expect(m.sourceBuild, '20260928');
    expect(m.archiveUri.toString(),
        'https://tiles.mcbuchi.de/trailbuddy/dach-20260928.pmtiles');
  });

  test('was nicht passt, wirft — ein Dateiname wird zu einem Pfad', () {
    for (final broken in [
      {..._recorded, 'file': '../secret.pmtiles'},
      {..._recorded, 'file': 'dach-latest.pmtiles'},
      {..._recorded, 'file': null},
      {..._recorded, 'maxzoom': '13'},
      {..._recorded, 'maxzoom': 3},
    ]) {
      expect(() => MapManifest.fromJson(Map<String, dynamic>.from(broken)),
          throwsFormatException,
          reason: '$broken');
    }
  });

  group('onlineMapProvider', () {
    late int manifestCalls;
    late int openCalls;

    ProviderContainer make({
      required bool enabled,
      bool offline = false,
      Future<MapManifest> Function()? loader,
      Future<PmTilesVectorTileProvider> Function(Uri)? opener,
    }) {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWithValue(FakeSettings(newMapEnabled: enabled)),
        noConnectivityProvider.overrideWithValue(offline),
        mapManifestLoaderProvider.overrideWithValue(() {
          manifestCalls++;
          return (loader ?? () async => _manifest)();
        }),
        onlineArchiveOpenerProvider.overrideWithValue((uri) {
          openCalls++;
          return (opener ?? _openOverview)(uri);
        }),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      manifestCalls = 0;
      openCalls = 0;
    });

    test('Schalter aus: der Host wird NIE gefragt', () async {
      expect(await make(enabled: false).read(onlineMapProvider.future),
          isNull);
      expect(manifestCalls, 0);
      expect(openCalls, 0);
    });

    test('kein Empfang: auch mit Schalter nicht', () async {
      expect(
          await make(enabled: true, offline: true)
              .read(onlineMapProvider.future),
          isNull);
      expect(manifestCalls, 0);
    });

    test('Schalter an, Empfang: Manifest UND Archiv geöffnet', () async {
      final online =
          await make(enabled: true).read(onlineMapProvider.future);
      expect(online?.manifest.file, 'dach-20260928.pmtiles');
      expect(manifestCalls, 1);
      expect(openCalls, 1,
          reason: 'Erst ein geöffnetes Archiv beweist „erreichbar" — sonst '
              'zeichnete MapLibre bei einer 403 leere Kacheln ohne Rückfall.');
    });

    test('Manifest kaputt oder Archiv tot ⇒ null (= OSM), nie ein Wurf',
        () async {
      expect(
          await make(
                  enabled: true,
                  loader: () async => throw const FormatException('x'))
              .read(onlineMapProvider.future),
          isNull);
      expect(
          await make(
                  enabled: true,
                  opener: (_) async => throw const HttpException('403'))
              .read(onlineMapProvider.future),
          isNull);
    });

    test('der Schalter wirkt sofort und fragt erst dann', () async {
      final c = make(enabled: false);
      expect(await c.read(onlineMapProvider.future), isNull);
      c.read(newMapEnabledProvider.notifier).set(true);
      expect(await c.read(onlineMapProvider.future), isNotNull);
      expect(manifestCalls, 1);
      expect((c.read(settingsProvider) as FakeSettings).newMapEnabled, isTrue);
    });

    test('flutter_map-Stil: Archiv plus Thema ohne Hintergrund', () async {
      final c = make(enabled: true);
      final style = await c.read(onlineMapStyleProvider.future);
      expect(style, isNotNull);
      expect(style!.theme.layers.any((l) => l.type == ThemeLayerType.background), isFalse);
      expect(style.theme.layers, isNotEmpty);
    });
  });
}
