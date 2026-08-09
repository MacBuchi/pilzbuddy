import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import '../../ampel/ampel_map_providers.dart';
import '../../offline_maps/offline_map_providers.dart';
import '../finite_camera_constraint.dart';
import '../forest_data_providers.dart';
import '../rain_data_providers.dart';
import '../rain_layer.dart';
import 'map_view.dart';

/// Fabrik für den Karten-Kachel-Provider. Tests ersetzen sie durch einen
/// Offline-Fake, damit keine echten OSM-Requests laufen.
///
/// `NetworkTileProvider` aus flutter_map selbst statt des früheren
/// `CancellableNetworkTileProvider`: Beides, was dessen Paket beitrug, ist
/// inzwischen eingebaut — überholte Anfragen werden abgebrochen
/// (`abortObsoleteRequests`, Vorgabe) und geladene Kacheln landen in einem
/// Platten-Cache (`BuiltInMapCachingProvider`, Vorgabe, bis 1 GB). Der
/// Cache ist hier der eigentliche Gewinn: Beim zweiten Besuch einer
/// Gegend steht die Karte sofort, und bei schwachem Empfang bleibt das
/// zuletzt Gesehene sichtbar, statt grau zu werden. Das alte Paket ist
/// upstream als „prepare for deprecation" markiert.
final tileProviderFactoryProvider =
    Provider<TileProvider Function()>((ref) => NetworkTileProvider.new);

/// Die heutige Karten-Engine: flutter_map 8 mit vector_map_tiles für die
/// Offline-Schichten. 1:1 aus `map_screen.dart` hierher gezogen, damit
/// hinter der [MapView]-Fassade eine zweite Engine (MapLibre) neben ihr
/// leben kann. Web nutzt immer diesen Pfad.
class FlutterMapView extends ConsumerStatefulWidget {
  const FlutterMapView({
    super.key,
    required this.config,
    required this.controller,
    required this.markers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewMarkers markers;

  @override
  ConsumerState<FlutterMapView> createState() => _FlutterMapViewState();
}

class _FlutterMapViewState extends ConsumerState<FlutterMapView>
    implements MapViewCameraDelegate {
  final _mapController = MapController();

  /// Stillstand melden — Mitte UND Sichtfenster, für Fadenkreuz-Werte
  /// (#235) und den Bildausschnitt der Waldfläche (#249).
  void _reportIdle(MapCamera camera) {
    final bounds = camera.visibleBounds;
    widget.config.onCameraIdle?.call(
      camera.center,
      MapViewBounds(
        west: bounds.west,
        east: bounds.east,
        south: bounds.south,
        north: bounds.north,
      ),
    );
  }

  /// GENAU EINE Provider-Instanz pro **eingehängtem TileLayer** — nicht
  /// mehr und nicht weniger. Nicht mehr: Eine neue Instanz je Rebuild
  /// (Positions-Ticks!) würde bei jeder Bewegung einen HTTP-Client samt
  /// Verbindungen leaken (#Karten-Freezes). Nicht weniger: flutter_map
  /// ruft beim Aushängen des TileLayer `tileProvider.dispose()` auf und
  /// schließt damit den HTTP-Client — und ausgehängt wird er bei JEDEM
  /// Wechsel in den Offline-Modus, auch dem automatischen bei
  /// Empfangsverlust (`offlineMapStyleProvider`). Eine über den Wechsel
  /// hinweg festgehaltene Instanz (früher `late final`) war danach eine
  /// Leiche: Jede frische Kachel scheiterte bis zum App-Neustart, nur der
  /// Platten-Cache lieferte noch — Bereiche erschienen und verschwanden
  /// je nach Zoomstufe und Gegend (#157, „graue Kacheln auch online").
  /// Deshalb: Referenz beim Wechsel auf Offline fallen lassen (im build),
  /// beim nächsten Online-Einbau frisch erzeugen.
  TileProvider? _tileProvider;

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
  }

  @override
  void didUpdateWidget(covariant FlutterMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detach(this);
      widget.controller.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    _mapController.dispose();
    super.dispose();
  }

  // ---- MapViewCameraDelegate ----
  @override
  void move(LatLng center, double zoom) => _mapController.move(center, zoom);

  @override
  LatLng get center => _mapController.camera.center;

  @override
  double get zoom => _mapController.camera.zoom;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final markers = widget.markers;
    // Offline-Layer nur, wenn eingeschaltet UND Karte + Style geladen werden
    // konnten — sonst immer Online-OSM (Sicherheitsnetz um den Beta-Renderer).
    final offlineStyle = ref.watch(offlineMapStyleProvider).valueOrNull;
    // Die Basiskarte hängt an nichts: kein Schalter, keine Installation.
    // Fehlt sie (Ladefehler), bleibt es beim Hintergrundton.
    final baseStyle = ref.watch(baseMapStyleProvider).valueOrNull;
    final offlineActive = offlineStyle != null;
    // Die Basiskarte NICHT mehr unter die Online-Kacheln legen (#137): Wo
    // eine OSM-Kachel schon liegt und die nächste noch fehlt, standen zwei
    // verschiedene Kartenstile nebeneinander — das sah kaputter aus als die
    // leere Fläche, die es verhindern sollte. Ohne Empfang bleibt sie
    // dagegen drin: Dann kommt gar keine Kachel, es gibt also nichts, womit
    // sie sich mischen könnte — und genau dieser Fall (Wald, kein Netz, noch
    // keine Region geladen) war der Anlass für #118.
    final showBaseMap = offlineActive || ref.watch(noConnectivityProvider);
    // Die Regenebene liegt auch auf diesem Pfad — er ist der einzige im
    // Web, und die PWA ist ein erklärtes Ziel. Ein Knopf, der nur auf
    // Android etwas tut, wäre ein Fehler ohne Fehlermeldung.
    final rainLayer = ref.watch(rainLayerProvider);
    final rainBounds = rainLayer.bounds;
    // Der Dreizustand entscheidet: eigene Fläche, noch nichts (Gitter
    // lädt — KEIN DWD-Bild, das gleich wieder verschwände), oder das
    // DWD-Bild als Rückfalllinie. Beim Radar immer das DWD-Bild — der
    // 5-Minuten-Takt lässt sich nicht vorberechnen.
    final rainPaint = ref.watch(rainPaintProvider(rainLayer));
    final rainFill = ref.watch(rainFillProvider(rainLayer)).value;
    final rainUrl = rainPaint == RainPaint.dwd
        ? rainLayerUrl(rainLayer, now: DateTime.now())
        : null;
    // Die Waldtypen-Fläche (#213) — wie der Regen auch auf diesem Pfad,
    // denn er ist der einzige im Web.
    final forestFill = ref.watch(forestFillProvider).valueOrNull;
    // Die Pilzwetter-Fläche (Ampel-Vorschau) — im Blatt exklusiv zu den
    // Regenflächen, liegt wie diese über dem Wald.
    final ampelFill = ref.watch(ampelFillProvider).valueOrNull;
    if (offlineActive) {
      // Der TileLayer, der die Instanz hält, verschwindet mit diesem Frame
      // und entsorgt sie dabei — siehe Kommentar am Feld.
      _tileProvider = null;
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: config.initialCenter,
        initialZoom: config.initialZoom,
        // Zoom hart begrenzen: OSM liefert Kacheln nur bis Zoom 19,
        // darüber skaliert flutter_map die z19-Kachel hoch (256 px ×
        // 2^(zoom−19)). Ohne Obergrenze wächst die gerenderte Kachel
        // ins Absurde und die Karte bleibt leer, bis man weit genug
        // herauszoomt. Unten reicht Zoom 3 (Kontinent) locker aus.
        minZoom: config.minZoom,
        maxZoom: config.maxZoom,
        // Statt flutter_maps Standard-Grau (0xFFE0E0E0): der Landton
        // des Offline-Styles. Wo noch keine Kachel liegt, sieht die
        // Fläche dann nach „Karte lädt" aus und nicht nach „kaputt" —
        // und der Übergang zur fertigen Kachel fällt kaum auf.
        backgroundColor: config.backgroundColor,
        // Karte bleibt fest nach Norden ausgerichtet — Drehen per
        // Zwei-Finger-Geste verwirrt nur und bringt keinen Mehrwert.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        // NaN-/Infinity-Kamerazustände aus Gesten-Grenzfällen an der
        // einzigen Engstelle verwerfen — sonst ANR über die
        // MarkerLayer-Endlosschleife (#151) und graue Kacheln über
        // die Kachelberechnung (#141). Details am Wächter selbst.
        cameraConstraint: const FiniteCameraConstraint(),
        onLongPress: (tapPosition, latLng) =>
            config.onLongPress?.call(latLng),
        // „Zum Stehen gekommen" (#235): Gesten- und Animationsenden,
        // nicht jede Bewegung — die Fadenkreuz-Werte rechnen daraufhin.
        // Das Mausrad hat kein Ende-Ereignis, sein Einzelschritt IST
        // der Stillstand.
        onMapReady: () => _reportIdle(_mapController.camera),
        onMapEvent: (event) {
          if (event is MapEventMoveEnd ||
              event is MapEventFlingAnimationEnd ||
              event is MapEventDoubleTapZoomEnd ||
              event is MapEventScrollWheelZoom) {
            _reportIdle(event.camera);
          }
        },
      ),
      children: [
        // Unterste Schicht: die mitgelieferte DACH-Übersicht. Sie
        // füllt jede Stelle, die die Regionskarte nicht abdeckt —
        // beim Kaltstart und mitten im Wald (#118/#119). Der Renderer
        // holt dafür die z7-Kachel und skaliert sie hoch; scharf
        // wird es, sobald die Schicht darüber geladen hat. Unter den
        // Online-Kacheln liegt sie bewusst NICHT (siehe showBaseMap).
        if (baseStyle != null && showBaseMap)
          vmt.VectorTileLayer(
            key: const ValueKey('base-map'),
            tileProviders: baseStyle.tileProviders,
            theme: baseStyle.theme,
            // Raster, nicht Vektor (#119): Der Vektor-Modus rendert
            // bei jeder Zwischen-Zoomstufe neu — laut Paket-Doku
            // „can result in low frame rates", und diese Schicht
            // läuft seit #118/#119 bei ALLEN mit, nicht nur bei
            // Offline-Nutzern. Hier kostet der Wechsel nichts: Die
            // Daten enden bei Zoom 7 und werden ohnehin immer
            // hochskaliert, es gibt also keine Schärfe zu verlieren.
            // Die Detailkarte unten bleibt bewusst auf Vektor.
            layerMode: vmt.VectorTileLayerMode.raster,
            maximumTileSubstitutionDifference: 1,
          ),
        if (offlineActive)
          vmt.VectorTileLayer(
            // Der Schlüssel hängt an der QUELLE, nicht an einem festen
            // Namen (Issue #144). `vector_map_tiles` vergleicht beim
            // Aktualisieren nur Theme, Sprites, tileOffset, layerMode
            // und maximumZoom (`hasRenderDifferences` in options.dart)
            // — ein Wechsel der `tileProviders` fällt dort durch. Der
            // Layer behielte also seine Caches und damit die Archive,
            // die `_offlineTileSourceProvider` beim Neuaufbau schließt
            // (jeder Resume invalidiert `installedMapsProvider`).
            // Danach wirft jede Kachel „withResource() may not be
            // called on a closed Pool", übrig bleibt die hochskalierte
            // Übersicht, und nur ein App-Neustart half. Ein neuer
            // Schlüssel erzwingt stattdessen einen frischen Layer mit
            // frischen Caches auf den neu geöffneten Archiven.
            key: ValueKey(offlineStyle.tileProviders),
            tileProviders: offlineStyle.tileProviders,
            theme: offlineStyle.theme,
            // Vector-Modus rendert scharf in jeder Zoomstufe; die
            // Kartendaten reichen bis Zoom ~15, darüber wird skaliert.
            layerMode: vmt.VectorTileLayerMode.vector,
            maximumZoom: 19,
            // Fehlende Kacheln maximal weit durch niedrigere
            // Zoomstufen ersetzen (Ränder der Regionskarten und
            // die eingebaute Übersichts-Basiskarte).
            maximumTileSubstitutionDifference: 1,
          )
        else
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'de.marcusbucher.pilzbuddy',
            tileProvider: _tileProvider ??=
                ref.read(tileProviderFactoryProvider)(),
            // Zurück auf die Paketvorgabe (Issue #142). #130 hatte
            // 3/2 gesetzt, um lieber grob weiterzuzeichnen als auf
            // die scharfe Kachel zu warten. Der Preis war zu hoch:
            // Jede gehaltene Kachel ist eine GPU-Textur, und
            // `flutter_map` gibt sie beim Ausdünnen nicht frei
            // (`evictImageFromCache = false`). Gemessen wuchs der
            // Texturspeicher beim Bedienen von 89 auf 257 MB und fiel
            // erst beim Neustart — in den ANR-Berichten stand er bei
            // 1,7–1,9 GB. Eine Karte, die nach zehn Minuten die App
            // abwürgt, ist schlechter als eine, die beim Nachladen
            // kurz blass ist.
            keepBuffer: 2,
            panBuffer: 1,
          ),
        // Die Waldtypen-Fläche (#213) — VOR den Regen-Overlays, damit
        // der Regen beim Kombinieren (#232) obenauf liegt: Er ist die
        // flüchtige Information, der Wald die Kulisse.
        // `filterQuality: none`, anders als der Regen-Fill und wie das
        // DWD-Bild: Die 250-m-Klötzchen sind die Daten, und ein weiches
        // Bild sähe genauer aus, als sie sind.
        if (forestFill != null)
          OverlayImageLayer(
            overlayImages: [
              OverlayImage(
                bounds: LatLngBounds(
                  LatLng(forestFill.south, forestFill.west),
                  LatLng(forestFill.north, forestFill.east),
                ),
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
                imageProvider: MemoryImage(forestFill.png),
              ),
            ],
          ),
        // Die Regenebene über der Karte, aber UNTER den Markern: Ein
        // Spot, der hinter dem Regen verschwindet, wäre genau dann
        // unauffindbar, wenn man ihn braucht. Dieselbe Schichtung wie
        // in der MapLibre-Engine (map_style_composer.dart).
        //
        // `filterQuality: none` = nächster Nachbar, aus demselben Grund
        // wie `raster-resampling: nearest` dort: Die Daten sind ein
        // 1-km-Raster, und ein weichgezeichnetes Bild sähe genauer aus,
        // als sie sind. `gaplessPlayback`, damit beim Ebenenwechsel
        // nicht kurz gar nichts liegt.
        if (rainUrl != null)
          OverlayImageLayer(
            overlayImages: [
              OverlayImage(
                bounds: LatLngBounds(
                  LatLng(rainBounds.south, rainBounds.west),
                  LatLng(rainBounds.north, rainBounds.east),
                ),
                opacity: rainLayer.opacity,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
                imageProvider:
                    ref.read(rainImageProviderFactory)(rainUrl),
              ),
            ],
          ),
        // Die eigene Fläche: dasselbe Bild-Overlay wie beim DWD, nur mit
        // einem selbst eingefärbten Gitter. Seit 1.48.0 trägt SIE die
        // Aussage — die Höhenlinien werden nicht mehr gezeichnet, weil
        // die Fläche bei 32 % Deckkraft unlesbar war und bei 55 % keine
        // Linien mehr braucht (am Gerät verglichen, 2026-08-04).
        //
        // `filterQuality: medium` statt `none` — dieselbe Kehrtwende und
        // dieselbe Begründung wie `raster-resampling: linear` bei
        // MapLibre: Als Hauptdarstellung traten die 1-km-Treppenstufen
        // hervor und widersprachen den geglätteten Konturen, aus denen
        // die Beschriftung kommt. Der Wert am Spot bleibt davon
        // unberührt, der kommt aus dem rohen Gitter.
        //
        // Was hier fehlt und auf MapLibre steht: die Millimeterzahlen in
        // der Karte. flutter_map kennt keine Beschriftung entlang einer
        // Linie; auf diesem Pfad trägt die Legende die Bedeutung allein.
        if (rainPaint == RainPaint.own && rainFill != null)
          OverlayImageLayer(
            overlayImages: [
              OverlayImage(
                bounds: LatLngBounds(
                  LatLng(rainFill.south, rainFill.west),
                  LatLng(rainFill.north, rainFill.east),
                ),
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                imageProvider: MemoryImage(rainFill.png),
              ),
            ],
          ),
        // Die Pilzwetter-Fläche (Ampel-Vorschau): `none` wie der Wald —
        // die Kilometer-Zellen und die drei Stufen SIND die Daten,
        // weichgezeichnet sähen sie genauer aus, als sie sind.
        if (ampelFill != null)
          OverlayImageLayer(
            overlayImages: [
              OverlayImage(
                bounds: LatLngBounds(
                  LatLng(ampelFill.south, ampelFill.west),
                  LatLng(ampelFill.north, ampelFill.east),
                ),
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
                imageProvider: MemoryImage(ampelFill.png),
              ),
            ],
          ),
        // Markergruppen in fester Reihenfolge (unten → oben), damit
        // Spots über den Live-Positionen liegen und tappbar bleiben.
        if (markers.myPosition.isNotEmpty)
          MarkerLayer(markers: [
            for (final m in markers.myPosition) _asFlutterMapMarker(m),
          ]),
        if (markers.friendLocations.isNotEmpty)
          MarkerLayer(markers: [
            for (final m in markers.friendLocations) _asFlutterMapMarker(m),
          ]),
        MarkerLayer(markers: [
          for (final m in markers.spots) _asFlutterMapMarker(m),
        ]),
        // Maßstab unten links — rechts sitzen Attribution und FABs.
        const Scalebar(
          alignment: Alignment.bottomLeft,
          padding: EdgeInsets.only(left: 12, bottom: 12),
        ),
        RichAttributionWidget(
          attributions: [
            const TextSourceAttribution('OpenStreetMap-Mitwirkende'),
            if (offlineActive)
              const TextSourceAttribution('Protomaps (Offline-Karte)'),
          ],
        ),
      ],
    );
  }

  static Marker _asFlutterMapMarker(MapViewMarker m) => Marker(
        point: m.point,
        width: m.width,
        height: m.height,
        alignment: m.alignment,
        child: m.child,
      );
}
