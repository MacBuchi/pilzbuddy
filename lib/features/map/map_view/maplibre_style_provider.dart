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

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pmtiles/pmtiles.dart';

import '../../../core/app_colors.dart';
import '../../../core/errors.dart';
import '../../offline_maps/offline_map_providers.dart';
import '../rain_layer.dart';
import 'map_style_composer.dart';

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

  /// Materialisiert die DACH-Übersicht und liefert ihren Pfad. Bewusst
  /// derselbe Zielpfad wie `_openBundledOverview` beim Canvas-Renderer —
  /// beide Engines teilen sich die eine Datei auf Platte.
  Future<String> materializeOverview() async {
    final dir = await getApplicationSupportDirectory();
    final file = await _materialize(
      'assets/offline_maps/overview_dach.pmtiles',
      File('${dir.path}/offline_maps/overview_dach.pmtiles'),
    );
    return file.path;
  }

  /// Materialisiert die Glyph-PBFs und liefert die Glyphs-URL-Vorlage.
  Future<String> materializeGlyphs() async {
    final dir = await getApplicationSupportDirectory();
    for (final stack in _fontStacks) {
      for (final range in _glyphRanges) {
        await _materialize('assets/map_glyphs/$stack/$range.pbf',
            File('${dir.path}/map_glyphs/$stack/$range.pbf'));
      }
    }
    return 'file://${dir.path}/map_glyphs/{fontstack}/{range}.pbf';
  }

  /// Liest min/max Zoom aus dem PMTiles-ARCHIV-HEADER — nie aus den
  /// eingebetteten Metadaten, die nachweislich lügen (siehe
  /// MapStyleSource).
  Future<({int min, int max})> readZoomRange(String path) async {
    final archive = await PmTilesArchive.fromFile(File(path));
    try {
      return (min: archive.header.minZoom, max: archive.header.maxZoom);
    } finally {
      await archive.close();
    }
  }
}

final maplibreStyleIoProvider =
    Provider<MapLibreStyleIo>((ref) => MapLibreStyleIo());

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
  final installed = await ref.watch(installedMapsProvider.future);
  final manuallyEnabled = ref.watch(offlineMapEnabledProvider);
  final noConnectivity = ref.watch(noConnectivityProvider);
  final io = ref.watch(maplibreStyleIoProvider);
  try {
    final offlineActive =
        (manuallyEnabled || noConnectivity) && installed.isNotEmpty;
    final showOverview = offlineActive || noConnectivity;

    final base = jsonDecode(await io.loadBaseStyle()) as Map<String, dynamic>;
    final glyphsUrl = await io.materializeGlyphs();

    final sources = <MapStyleSource>[];
    if (showOverview) {
      final overviewPath = await io.materializeOverview();
      final overviewZoom = await io.readZoomRange(overviewPath);
      sources.add(MapStyleSource(
        id: 'overview',
        filePath: overviewPath,
        minZoom: overviewZoom.min,
        maxZoom: overviewZoom.max,
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

    return composeMapLibreStyle(
      baseStyle: base,
      glyphsUrl: glyphsUrl,
      backgroundColor: _cssColor(AppColors.mapBackground.toARGB32()),
      sources: sources,
      rasterSources: offlineActive ? const [] : const [_osmRaster],
      // `DateTime.now()` nur für die Vorhersage-Ebene, siehe rain_layer.dart.
      overlays: [
        ?_rainOverlay(ref.watch(rainLayerProvider), DateTime.now()),
      ],
    );
  } catch (e, stackTrace) {
    logError('MapLibre-Style bauen', e, stackTrace);
    return null;
  }
});
