// Die I/O-Schicht über dem puren Style-Composer: materialisiert Glyphs
// und Übersichtskarte aus den Assets, liest die Zoombereiche aus den
// Archiv-Headern und setzt daraus das Style-Dokument der MapLibre-Engine
// zusammen.
//
// Das wichtigste Verhalten steckt im `await` auf die Regionsliste
// (Anti-Race aus der Spike-Autopsie): `maplibre_android` wendet
// `initStyle` genau EINMAL bei Map-Ready an — ein Style, der vor dem
// Laden der Registry entsteht, kennt keine Regionsquellen, und die
// Regionen bleiben für immer unsichtbar.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pmtiles/pmtiles.dart';

import '../../../core/app_colors.dart';
import '../../../core/errors.dart';
import '../../offline_maps/offline_map_providers.dart';
import '../../offline_maps/offline_map_repository.dart' show InstalledMap;
import '../rain_data_providers.dart';
import '../rain_layer.dart';
import '../map_overlays.dart';
import '../online_map.dart';
import '../online_tile_server.dart';
import '../app_tile_protocol.dart';
import '../../offline_maps/pmtiles_tile_provider.dart';
import '../../offline_areas/area_providers.dart';
import 'map_style_composer.dart';
import 'maplibre_web.dart' show loadMapLibreJs, registerAppTileProtocol;

/// Die fünf Unicode-Bereiche, die für deutsche Kartenbeschriftung reichen
/// (Lücke bewusst: `Failed to load glyph range 1024-1279` für z. B.
/// Kyrillisch — betrifft nur Beschriftung außerhalb des DACH-Ausschnitts).
const _glyphRanges = ['0-255', '256-511', '512-767', '7680-7935', '8192-8447'];
const _fontStacks = ['noto-sans-regular', 'noto-sans-medium'];

/// Alle Plattenzugriffe des Style-Providers — als Klasse, damit Tests sie
/// durch eine Fake ersetzen können (maplibre_style_provider_test.dart);
/// echte Dateien und Platform-Channels gibt es im Widget-Test nicht.
class MapLibreStyleIo {
  /// Der generierte Protomaps-Basis-Style (dasselbe Asset wie beim
  /// Canvas-Renderer — eine Quelle der Wahrheit für beide Engines).
  Future<String> loadBaseStyle() =>
      rootBundle.loadString('assets/map_style/protomaps_light_de.json');

  /// Kopiert ein Asset ins App-Verzeichnis, wenn es dort fehlt oder eine
  /// andere Größe hat — MapLibre kann keine `asset://`-URLs lesen (kein
  /// Byte-Range auf Assets), es braucht echte Dateien.
  Future<File> _materialize(String assetPath, File target) async {
    final data = await rootBundle.load(assetPath);
    if (!await target.exists() || await target.length() != data.lengthInBytes) {
      await target.create(recursive: true);
      await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return target;
  }

  /// Im Browser gibt es keine Platte, aber die Assets liegen unter
  /// `assets/` neben der Seite — MapLibre GL JS liest sie von dort
  /// (#689). Absolut, weil MapLibre relative URLs nicht gegen die
  /// `<base href>` auflöst; `Uri.base` trägt Freigabe- und Vorschaupfad.
  static String _webAsset(String assetPath) =>
      Uri.base.resolve('assets/$assetPath').toString();

  /// Materialisiert die DACH-Übersicht und liefert ihren Pfad. Bewusst
  /// derselbe Zielpfad wie `_openBundledOverview` beim Canvas-Renderer —
  /// beide Engines teilen sich die eine Datei auf Platte.
  ///
  /// Im Browser die URL des Assets (#689): GitHub Pages beantwortet
  /// Range-Anfragen mit 206, nachgemessen am 2026-10-09, und der Service
  /// Worker lässt Teilanfragen durch. Grenze: Ohne Netz kommt die
  /// Übersicht so NICHT — Teilanfragen legt der Worker nicht ab.
  Future<String> materializeOverview() async {
    if (kIsWeb) return _webAsset('assets/offline_maps/overview_dach.pmtiles');
    final dir = await getApplicationSupportDirectory();
    final file = await _materialize(
      'assets/offline_maps/overview_dach.pmtiles',
      File('${dir.path}/offline_maps/overview_dach.pmtiles'),
    );
    return file.path;
  }

  /// Materialisiert die Glyph-PBFs und liefert die Glyphs-URL-Vorlage.
  Future<String> materializeGlyphs() async {
    // Im Browser direkt aus den Assets; die Platzhalter erst nach dem
    // Auflösen anhängen, sonst kodiert `Uri` die Klammern.
    if (kIsWeb) {
      return '${_webAsset('assets/map_glyphs/')}{fontstack}/{range}.pbf';
    }
    final dir = await getApplicationSupportDirectory();
    for (final stack in _fontStacks) {
      for (final range in _glyphRanges) {
        await _materialize('assets/map_glyphs/$stack/$range.pbf',
            File('${dir.path}/map_glyphs/$stack/$range.pbf'));
      }
    }
    return 'file://${dir.path}/map_glyphs/{fontstack}/{range}.pbf';
  }

  Future<PmTilesVectorTileProvider>? _overviewTiles;

  /// Die Übersicht als offenes Archiv für das Kachel-Protokoll im Browser
  /// (#689) — ganz aus dem Asset gelesen, wie bei flutter_map. Nur so legt
  /// der Service Worker sie ab und sie kommt auch ohne Netz; die
  /// Range-Anfragen des `pmtiles://`-Wegs legt er nicht ab. Einmal je
  /// Sitzung: Die 8,6 MB bleiben ohnehin im Speicher.
  Future<PmTilesVectorTileProvider> openOverviewTiles() =>
      _overviewTiles ??= () async {
        try {
          final data = await rootBundle
              .load('assets/offline_maps/overview_dach.pmtiles');
          return await PmTilesVectorTileProvider.openBytes(data.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes));
        } catch (_) {
          _overviewTiles = null; // beim nächsten Style neu versuchen
          rethrow;
        }
      }();

  /// Liest min/max Zoom aus dem PMTiles-ARCHIV-HEADER — nie aus den
  /// eingebetteten Metadaten, die nachweislich lügen (siehe
  /// MapStyleSource).
  Future<({int min, int max})> readZoomRange(String path) async {
    // Eine URL (Browser, #689) liest nur den Header per Range-Anfrage.
    final archive = isRemoteArchive(path)
        ? await PmTilesArchive.fromUri(Uri.parse(path))
        : await PmTilesArchive.fromFile(File(path));
    try {
      return (min: archive.header.minZoom, max: archive.header.maxZoom);
    } finally {
      await archive.close();
    }
  }
}

/// Ist [path] eine Adresse statt eines Dateipfads? Im Browser liefert
/// [MapLibreStyleIo.materializeOverview] eine URL (#689).
bool isRemoteArchive(String path) =>
    path.startsWith('https://') || path.startsWith('http://');

final maplibreStyleIoProvider =
    Provider<MapLibreStyleIo>((ref) => MapLibreStyleIo());

/// Das Kachel-Protokoll der App für MapLibre GL JS (#689,
/// `app_tile_protocol.dart`) — null außerhalb des Browsers (dort gibt es
/// Dateien und den Kachel-Server auf Loopback) und wenn die Anmeldung
/// scheitert; dann bleibt der Style bei den bisherigen Wegen.
final appTileRouterProvider = FutureProvider<AppTileRouter?>((ref) async {
  if (!kIsWeb) return null;
  if (!await loadMapLibreJs()) return null;
  final router = AppTileRouter();
  return registerAppTileProtocol(router.load) ? router : null;
});

/// CSS-Farbwert für den Style — aus derselben Konstante wie die
/// flutter_map-Engine, damit die Landflächen beider Engines gleich aussehen.
String _cssColor(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Die Regenebene als georeferenziertes WMS-Einzelbild — welcher Layer,
/// welcher Ausschnitt und warum ein festes Bild: `rain_layer.dart`.
/// Warum kein Kachel-Template: siehe [MapImageOverlay] — maplibre-native
/// kennt `{bbox-epsg-3857}` nicht.
MapImageOverlay? _rainOverlay(RainLayer layer, DateTime now) {
  final url = rainLayerUrl(layer, now: now);
  if (url == null) return null;
  final b = layer.bounds;
  return MapImageOverlay(
    id: 'regen',
    url: url,
    west: b.west,
    south: b.south,
    east: b.east,
    north: b.north,
    opacity: layer.opacity,
    // Pflichtangabe nach GeoNutzV; der Dienst nennt als
    // AccessConstraints https://www.dwd.de/copyright.
    attribution: '© Deutscher Wetterdienst',
  );
}

/// Das Online-Raster (OSM) — dieselbe Quelle wie der TileLayer der
/// flutter_map-Engine.
const _osmRaster = MapRasterSource(
  id: 'osm',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  // OSM liefert Kacheln nur bis Zoom 19 (siehe _maxZoom in map_screen).
  maxZoom: 19,
);

/// Das fertige Style-Dokument — oder null, wenn etwas fehlt: Dann fällt
/// die MapLibre-Engine auf flutter_map zurück (maplibre_map_view.dart),
/// die Karte bleibt benutzbar. Optionales Feature, still degradieren.
///
/// Die Quellen-Wahl folgt EXAKT der Regel der flutter_map-Engine
/// (`offlineMapStyleProvider` + `showBaseMap`):
///
/// - offline aktiv = (Schalter ODER kein Empfang) UND Regionen
///   installiert ⇒ Übersicht + Regionen, kein Raster;
/// - sonst das OSM-Raster — und die Übersicht liegt NUR dann darunter,
///   wenn kein Empfang besteht: Dann kommt keine Kachel, es gibt nichts,
///   womit sie sich mischen könnte (#118). Unter funktionierenden
///   Online-Kacheln sähen zwei Kartenstile nebeneinander kaputter aus
///   als die leere Fläche (#137).
///
/// Ein Wechsel (Schalter, Empfangsverlust) erzeugt einen neuen
/// Style-String; die Engine spielt ihn per `setStyle` ein — es gibt
/// keinen TileProvider-Lebenszyklus, der dabei sterben könnte (die
/// #157-Fehlerklasse der alten Engine existiert hier nicht).
final maplibreStyleProvider = FutureProvider<String?>((ref) async {
  // ANTI-RACE: warten, nicht `valueOrNull` — siehe Kopfkommentar.
  // Im Browser gibt es keine Regionskarten (#496) — und keine Platte:
  // `installedMapsProvider` scheitert dort an `path_provider` (#689).
  final allInstalled = ref.watch(offlineMapsSupportedProvider)
      ? await ref.watch(installedMapsProvider.future)
      : const <InstalledMap>[];
  // Stillgelegte Regionen (Schalter „Regionskarten verwenden") zählen wie
  // keine — dieselbe Regel wie `offlineMapStyleProvider`.
  final installed = ref.watch(regionMapsEnabledProvider)
      ? allInstalled
      : allInstalled.take(0).toList();
  final manuallyEnabled = ref.watch(offlineMapEnabledProvider);
  final noConnectivity = ref.watch(noConnectivityProvider);
  // Ohne Empfang und mit Neuer Karte kein OSM-Raster — dieselbe Regel
  // wie in der flutter_map-Engine (`osmFallbackAllowedProvider`).
  final osmAllowed = ref.watch(osmFallbackAllowedProvider);
  final io = ref.watch(maplibreStyleIoProvider);
  // Dasselbe Anti-Race wie bei den Regionen: warten, damit der erste
  // Style die gespeicherten Bereiche schon kennt. Ein unlesbarer Bereich
  // nimmt der Karte nicht den Rest.
  AppTileRouter? router;
  try {
    router = await ref.watch(appTileRouterProvider.future);
  } catch (e, stackTrace) {
    logError('Kachel-Protokoll für den Style', e, stackTrace);
  }
  // Die Quellen hinter dem Protokoll, gesammelt beim Bauen und erst ganz
  // am Ende übergeben — siehe [AppTileRouter.replaceSources].
  final appSources = <String, AppTileSource>{};
  var areaSources = const <MapStyleSource>[];
  try {
    if (router != null) {
      // Im Browser gibt es keine Dateien: die Bytes aus IndexedDB, über
      // das Protokoll. Stand und Kachelzahl im Schlüssel — ein bearbeiteter
      // Bereich behält seine Id, MapLibre bräuchte sonst neue Kacheln
      // unter alter Adresse.
      areaSources = [
        for (final entry in await ref.watch(openedAreasProvider.future))
          _appSource(
            appSources,
            styleId: 'area_${entry.area.id}',
            key: 'area-${entry.area.id}-${entry.area.build}-${entry.area.tiles}',
            tiles: entry.provider,
            minZoom: entry.area.minZoom,
            maxZoom: entry.area.maxZoom,
          ),
      ];
    } else {
      areaSources = [
        for (final entry in await ref.watch(areaArchivePathsProvider.future))
          MapStyleSource(
            id: 'area_${entry.area.id}',
            filePath: entry.path,
            minZoom: entry.area.minZoom,
            maxZoom: entry.area.maxZoom,
          ),
      ];
    }
  } catch (e, stackTrace) {
    logError('Kartenbereiche für den Style lesen', e, stackTrace);
  }
  try {
    final offlineActive =
        (manuallyEnabled || noConnectivity) && installed.isNotEmpty;
    // Die Online-Karte vom Kartenhost (#630) — derselbe Provider und
    // dieselbe Regel wie in der flutter_map-Engine: nur mit Schalter,
    // Regionen gehen vor, und null heißt OSM wie bisher. Geöffnet hat
    // der Provider das Archiv schon; nur so ist „erreichbar" geprüft,
    // bevor MapLibre auf leere Kacheln umgestellt wird.
    final online =
        offlineActive ? null : await ref.watch(onlineMapProvider.future);
    // Unter der Online-Karte liegt die Übersicht: derselbe Kartenstil,
    // #137 betraf zwei verschiedene.
    final showOverview = offlineActive || noConnectivity || online != null;

    final base = jsonDecode(await io.loadBaseStyle()) as Map<String, dynamic>;
    final glyphsUrl = await io.materializeGlyphs();

    final sources = <MapStyleSource>[];
    if (showOverview && router != null) {
      final overview = await io.openOverviewTiles();
      sources.add(_appSource(
        appSources,
        styleId: 'overview',
        key: 'overview',
        tiles: overview,
        minZoom: overview.minimumZoom,
        maxZoom: overview.maximumZoom,
      ));
    } else if (showOverview) {
      final overviewPath = await io.materializeOverview();
      final overviewZoom = await io.readZoomRange(overviewPath);
      sources.add(isRemoteArchive(overviewPath)
          ? MapStyleSource.remote(
              id: 'overview',
              remoteUrl: overviewPath,
              minZoom: overviewZoom.min,
              maxZoom: overviewZoom.max,
            )
          : MapStyleSource(
              id: 'overview',
              filePath: overviewPath,
              minZoom: overviewZoom.min,
              maxZoom: overviewZoom.max,
            ));
    }
    if (online != null && router != null) {
      // Im Browser über das Protokoll: dasselbe Archiv, das
      // `onlineMapProvider` geöffnet hat, statt `pmtiles://` an R2 vorbei
      // an der App. Der Stand im Schlüssel, wie beim Kachel-Server.
      sources.add(_appSource(
        appSources,
        styleId: 'online',
        key: 'online-${online.manifest.file.replaceAll('.pmtiles', '')}',
        tiles: online.tiles,
        minZoom: 0,
        maxZoom: online.manifest.maxZoom,
        remote: true,
      ));
    } else if (online != null) {
      // Über den Kachel-Server der App (#659): Header und Verzeichnisse
      // einmal, jede Kachel einmal, über Neustarts hinweg abgelegt. Läuft
      // er nicht, liest MapLibre das Archiv wie bisher selbst.
      String? tilesUrl;
      try {
        tilesUrl = await ref.watch(onlineTilesUrlProvider.future);
      } catch (e, stackTrace) {
        logError('Kachel-Server für den Style', e, stackTrace);
      }
      sources.add(tilesUrl != null
          ? MapStyleSource.tiles(
              id: 'online',
              tilesUrl: tilesUrl,
              minZoom: 0,
              maxZoom: online.manifest.maxZoom,
            )
          : MapStyleSource.remote(
              id: 'online',
              remoteUrl: online.manifest.archiveUri.toString(),
              minZoom: 0,
              maxZoom: online.manifest.maxZoom,
            ));
    }
    if (offlineActive) {
      for (final map in installed) {
        final zoom = await io.readZoomRange(map.filePath);
        sources.add(MapStyleSource(
          id: 'region_${map.key}',
          filePath: map.filePath,
          minZoom: zoom.min,
          maxZoom: zoom.max,
        ));
      }
    }

    router?.replaceSources(appSources);
    return composeMapLibreStyle(
      baseStyle: base,
      glyphsUrl: glyphsUrl,
      backgroundColor: _cssColor(AppColors.mapBackground.toARGB32()),
      sources: sources,
      rasterSources: offlineActive || online != null || !osmAllowed
          ? const []
          : const [_osmRaster],
      // Die gespeicherten Kartenbereiche (#630) zuoberst, immer — siehe
      // `area_providers.dart`. Zoombereich aus dem Index: Der Download hat
      // Index und Archiv aus demselben Plan geschrieben.
      topSources: areaSources,
      // `DateTime.now()` nur für die Vorhersage-Ebene, siehe rain_layer.dart.
      overlays: [
        // Das DWD-Bild nur im dwd-Zustand: beim Radar immer, bei den
        // Summen als Rückfalllinie. Während das Gitter lädt (pending)
        // bleibt es bewusst draußen — es wäre der Farbblitz, der beim
        // Eintreffen der eigenen Fläche gleich wieder verschwände.
        // `select` mit Absicht: pending→own ändert den Bool nicht, ohne
        // select baute jede Summenaktivierung den Style zweimal komplett
        // neu (inkl. Glyph-I/O), und jeder Rebuild geht per setStyle an
        // die Engine.
        if (ref.watch(rainPaintProvider(ref.watch(drawnRainLayerProvider))
            .select((paint) => paint == RainPaint.dwd)))
          ?_rainOverlay(ref.watch(drawnRainLayerProvider), DateTime.now()),
      ],
    );
  } catch (e, stackTrace) {
    logError('MapLibre-Style bauen', e, stackTrace);
    return null;
  }
});

/// Meldet [tiles] unter [key] für das Kachel-Protokoll an und liefert die
/// Style-Quelle mit der passenden Vorlage.
MapStyleSource _appSource(
  Map<String, AppTileSource> appSources, {
  required String styleId,
  required String key,
  required PmTilesVectorTileProvider tiles,
  required int minZoom,
  required int maxZoom,
  bool remote = false,
}) {
  appSources[key] =
      AppTileSource(tiles.rawTile, gzip: tiles.tilesGzipped, remote: remote);
  return MapStyleSource.tiles(
    id: styleId,
    tilesUrl: AppTileRouter.urlTemplate(key),
    minZoom: minZoom,
    maxZoom: maxZoom,
  );
}
