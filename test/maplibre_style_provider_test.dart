// Der Style-Provider ist die I/O-Schicht über dem puren Composer. Sein
// wichtigstes Verhalten ist das Anti-Race aus der Spike-Autopsie: Der
// Style darf erst entstehen, wenn die Regionsliste GELADEN ist —
// `maplibre_android` wendet `initStyle` genau einmal bei Map-Ready an,
// ein zu früher Style ließe alle Regionen für immer unsichtbar.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/map/map_view/maplibre_style_provider.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_repository.dart';

import 'fakes/fake_settings.dart';

/// I/O-Fake: liefert feste Pfade und Header-Zoombereiche, merkt sich, für
/// welche Dateien der Header gelesen wurde.
class _FakeIo extends MapLibreStyleIo {
  final readHeaders = <String>[];
  bool failOverview = false;

  @override
  Future<String> loadBaseStyle() async => jsonEncode({
        'version': 8,
        'sources': {},
        'layers': [
          {
            'id': 'earth',
            'type': 'fill',
            'source': 'protomaps',
            'source-layer': 'earth',
          },
        ],
      });

  @override
  Future<String> materializeOverview() async {
    if (failOverview) throw StateError('Asset kaputt');
    return '/fake/offline_maps/overview_dach.pmtiles';
  }

  @override
  Future<String> materializeGlyphs() async =>
      'file:///fake/map_glyphs/{fontstack}/{range}.pbf';

  @override
  Future<({int min, int max})> readZoomRange(String path) async {
    readHeaders.add(path);
    // Übersicht 0–7, Regionen 0–15 — wie die echten Archiv-Header.
    return path.contains('overview') ? (min: 0, max: 7) : (min: 0, max: 15);
  }
}

/// Regionsliste, die erst auf Kommando fertig lädt.
class _GatedInstalledMaps extends InstalledMapsNotifier {
  _GatedInstalledMaps(this._gate);
  final Completer<List<InstalledMap>> _gate;

  @override
  Future<List<InstalledMap>> build() => _gate.future;
}

const _bayern = InstalledMap(
  key: 'de_bayern',
  dateStamp: '20260320',
  sizeBytes: 1789952894,
  filePath: '/fake/offline_maps/de_bayern_20260320.pmtiles',
);

void main() {
  (ProviderContainer, _FakeIo, Completer<List<InstalledMap>>) makeContainer() {
    final io = _FakeIo();
    final gate = Completer<List<InstalledMap>>();
    final container = ProviderContainer(overrides: [
      // Ohne diese Naht zöge der Style über die Regenfläche das
      // Wertegitter aus dem Netz — `flutter test` ist netzfrei.
      rainGridLoaderProvider.overrideWithValue((_) async => null),
      maplibreStyleIoProvider.overrideWithValue(io),
      installedMapsProvider.overrideWith(() => _GatedInstalledMaps(gate)),
      // Offline-Modus an: Diese Tests prüfen den Regions-Pfad des
      // Providers; die Quellen-Wahlregel selbst prüft die Matrix unten.
      settingsProvider
          .overrideWithValue(FakeSettings(offlineMapEnabled: true)),
      noConnectivityProvider.overrideWithValue(false),
    ]);
    addTearDown(container.dispose);
    return (container, io, gate);
  }

  test('Anti-Race: kein Style, bevor die Regionsliste geladen ist', () async {
    final (container, _, gate) = makeContainer();
    final styleFuture = container.read(maplibreStyleProvider.future);
    var done = false;
    unawaited(styleFuture.whenComplete(() => done = true));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse,
        reason: 'Der Style darf nicht vor der Regionsliste fertig sein — '
            'genau dieses Race machte im Spike alle Regionen unsichtbar.');

    gate.complete(const [_bayern]);
    final style = jsonDecode((await styleFuture)!) as Map<String, dynamic>;
    final sources = style['sources'] as Map<String, dynamic>;
    expect(sources.keys, ['overview', 'region_de_bayern']);
  });

  test('Zoombereiche kommen aus dem Archiv-Header jeder Datei', () async {
    final (container, io, gate) = makeContainer();
    gate.complete(const [_bayern]);
    final style =
        jsonDecode((await container.read(maplibreStyleProvider.future))!)
            as Map<String, dynamic>;
    expect(
        io.readHeaders,
        containsAll([
          '/fake/offline_maps/overview_dach.pmtiles',
          '/fake/offline_maps/de_bayern_20260320.pmtiles',
        ]));
    final sources = style['sources'] as Map<String, dynamic>;
    expect((sources['overview'] as Map)['maxzoom'], 7);
    expect((sources['region_de_bayern'] as Map)['maxzoom'], 15);
  });

  test('I/O-Fehler ⇒ null statt Wurf (Engine fällt auf flutter_map zurück)',
      () async {
    final (container, io, gate) = makeContainer();
    io.failOverview = true;
    gate.complete(const [_bayern]);
    expect(await container.read(maplibreStyleProvider.future), isNull);
  });

  // Die Quellen-Wahl folgt EXAKT der heutigen Regel der flutter_map-Engine
  // (offlineMapStyleProvider + showBaseMap): offline aktiv = (Schalter ODER
  // kein Empfang) UND Regionen installiert; die Übersicht liegt nie unter
  // funktionierenden Online-Kacheln (#137).
  group('Quellen-Matrix', () {
    Future<Map<String, dynamic>> styleFor({
      required bool offlineEnabled,
      required bool noConnectivity,
      required List<InstalledMap> installed,
    }) async {
      final io = _FakeIo();
      final gate = Completer<List<InstalledMap>>()..complete(installed);
      final container = ProviderContainer(overrides: [
      // Ohne diese Naht zöge der Style über die Regenfläche das
      // Wertegitter aus dem Netz — `flutter test` ist netzfrei.
      rainGridLoaderProvider.overrideWithValue((_) async => null),
        maplibreStyleIoProvider.overrideWithValue(io),
        installedMapsProvider.overrideWith(() => _GatedInstalledMaps(gate)),
        settingsProvider.overrideWithValue(
            FakeSettings(offlineMapEnabled: offlineEnabled)),
        noConnectivityProvider.overrideWithValue(noConnectivity),
      ]);
      addTearDown(container.dispose);
      return jsonDecode((await container.read(maplibreStyleProvider.future))!)
          as Map<String, dynamic>;
    }

    test('Schalter an + Regionen ⇒ offline: Übersicht + Regionen, KEIN '
        'Online-Raster', () async {
      final style = await styleFor(
          offlineEnabled: true,
          noConnectivity: false,
          installed: const [_bayern]);
      final sources = style['sources'] as Map<String, dynamic>;
      expect(sources.keys, ['overview', 'region_de_bayern']);
    });

    test('alles aus + Empfang ⇒ online: NUR das OSM-Raster — die Übersicht '
        'läge sonst unter fremdem Kartenstil (#137)', () async {
      final style = await styleFor(
          offlineEnabled: false,
          noConnectivity: false,
          installed: const [_bayern]);
      final sources = style['sources'] as Map<String, dynamic>;
      expect(sources.keys, ['osm']);
      expect((sources['osm'] as Map)['type'], 'raster');
    });

    test('kein Empfang + Regionen ⇒ automatisch offline (im Wald muss man '
        'nichts tun)', () async {
      final style = await styleFor(
          offlineEnabled: false,
          noConnectivity: true,
          installed: const [_bayern]);
      final sources = style['sources'] as Map<String, dynamic>;
      expect(sources.keys, ['overview', 'region_de_bayern']);
    });

    test('kein Empfang + KEINE Regionen ⇒ Übersicht unter dem (hungernden) '
        'Raster — der #118-Fall: Wald, kein Netz, nichts installiert',
        () async {
      final style = await styleFor(
          offlineEnabled: false, noConnectivity: true, installed: const []);
      final sources = style['sources'] as Map<String, dynamic>;
      expect(sources.keys, ['overview', 'osm']);
      final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
      expect(layers.last['type'], 'raster');
    });

    test('Schalter an, aber KEINE Regionen + Empfang ⇒ online (heutiges '
        'Verhalten: ohne Kacheln kein Offline-Modus)', () async {
      final style = await styleFor(
          offlineEnabled: true, noConnectivity: false, installed: const []);
      final sources = style['sources'] as Map<String, dynamic>;
      expect(sources.keys, ['osm']);
    });
  });

  test('Radar-Flag hängt das DWD-Overlay als oberste Ebene an — aus bleibt '
      'der Style unverändert', () async {
    final io = _FakeIo();
    final gate = Completer<List<InstalledMap>>()..complete(const []);
    final container = ProviderContainer(overrides: [
      // Ohne diese Naht zöge der Style über die Regenfläche das
      // Wertegitter aus dem Netz — `flutter test` ist netzfrei.
      rainGridLoaderProvider.overrideWithValue((_) async => null),
      maplibreStyleIoProvider.overrideWithValue(io),
      installedMapsProvider.overrideWith(() => _GatedInstalledMaps(gate)),
      settingsProvider.overrideWithValue(FakeSettings()),
      noConnectivityProvider.overrideWithValue(false),
    ]);
    addTearDown(container.dispose);

    final without =
        jsonDecode((await container.read(maplibreStyleProvider.future))!)
            as Map<String, dynamic>;
    expect((without['sources'] as Map).keys, isNot(contains('regen')));

    container.read(rainLayerProvider.notifier).state = RainLayer.last30d;
    // Erst das (leere) Gitter zu Ende laden lassen: Solange es lädt, hält
    // der Style das DWD-Bild bewusst draußen (siehe den Test darunter).
    await container.read(rainContoursProvider(RainLayer.last30d).future);
    final style =
        jsonDecode((await container.read(maplibreStyleProvider.future))!)
            as Map<String, dynamic>;
    final sources = style['sources'] as Map<String, dynamic>;
    expect(sources.keys, contains('regen'));
    final rain = sources['regen'] as Map<String, dynamic>;
    expect(rain['type'], 'image');
    expect(rain['url'], contains('RADOLAN-W4'),
        reason: 'Die gewählte Ebene muss im Style landen — sonst schaltet '
            'das Blatt sichtbar um und zeigt weiter dasselbe Bild.');
    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    expect(layers.last['id'], 'regen');
  });

  test('Solange das Gitter lädt, bleibt das DWD-Bild draußen — erst der '
      'Fehlschlag holt es als Rückfall in den Style', () async {
    // Der Umschalt-Moment auf dem MapLibre-Pfad: Das DWD-Bild lag im
    // Style, solange das Gitter lud, und flog beim Eintreffen der eigenen
    // Fläche wieder raus — sichtbar als Farbblitz samt doppeltem
    // Style-Rebuild.
    final io = _FakeIo();
    final installed = Completer<List<InstalledMap>>()..complete(const []);
    final gate = Completer<RainGrid?>();
    final container = ProviderContainer(overrides: [
      rainGridLoaderProvider.overrideWithValue((_) => gate.future),
      maplibreStyleIoProvider.overrideWithValue(io),
      installedMapsProvider.overrideWith(() => _GatedInstalledMaps(installed)),
      settingsProvider.overrideWithValue(FakeSettings()),
      noConnectivityProvider.overrideWithValue(false),
    ]);
    addTearDown(container.dispose);
    container.read(rainLayerProvider.notifier).state = RainLayer.last30d;

    final pending =
        jsonDecode((await container.read(maplibreStyleProvider.future))!)
            as Map<String, dynamic>;
    expect((pending['sources'] as Map).keys, isNot(contains('regen')),
        reason: 'ein Bild, das gleich ersetzt wird, gehört nicht in den '
            'Style — es wäre der Farbblitz');

    gate.complete(null);
    await container.read(rainContoursProvider(RainLayer.last30d).future);
    final fallback =
        jsonDecode((await container.read(maplibreStyleProvider.future))!)
            as Map<String, dynamic>;
    expect((fallback['sources'] as Map).keys, contains('regen'),
        reason: 'ohne Gitter bleibt das DWD-Bild die Rückfalllinie');
  });
}
