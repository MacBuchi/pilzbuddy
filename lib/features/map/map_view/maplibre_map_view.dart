// Die MapLibre-Engine hinter der MapView-Fassade (Android, Opt-in-Beta).
//
// Rendert nativ auf eigenem GL-Thread (maplibre-native via Paket
// `maplibre`) statt per Canvas auf dem UI-Isolate — der Kern der
// „Lupo → Porsche"-Migration. In dieser Stufe (PR 3) bewusst NUR die
// rohe Offline-Karte: keine Marker, keine Online-Kacheln — der
// Opt-in-Schalter im Profil sagt das ehrlich dazu. Web sieht diese Datei
// nie (bedingter Import in map_view.dart).
//
// Die Widget-Shell bleibt bewusst dumm: Platform-Views sind im
// Widget-Test nicht renderbar, ihr Gate ist das Gerät. Alles Prüfbare
// steckt im puren Composer (map_style_composer.dart) und im
// Style-Provider (maplibre_style_provider.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../../../core/app_colors.dart';
import '../rain_contours.dart';
import '../rain_data_providers.dart';
import '../rain_layer.dart';
import 'flutter_map_view.dart';
import 'map_view.dart';
import 'maplibre_rain_fill.dart';
import 'maplibre_style_provider.dart';
import 'marker_culling.dart';

/// Bau-Funktion für die Engine-Wahl in `map_view.dart` — Stub und echte
/// Datei müssen dieselbe Signatur exportieren (bedingter Import).
Widget createMapLibreMapView({
  required MapViewConfig config,
  required MapViewController controller,
  required MapViewMarkers markers,
}) =>
    MapLibreMapView(config: config, controller: controller, markers: markers);

class MapLibreMapView extends ConsumerStatefulWidget {
  const MapLibreMapView({
    super.key,
    required this.config,
    required this.controller,
    required this.markers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewMarkers markers;

  @override
  ConsumerState<MapLibreMapView> createState() => _MapLibreMapViewState();
}

class _MapLibreMapViewState extends ConsumerState<MapLibreMapView>
    implements MapViewCameraDelegate {
  ml.MapController? _ml;

  /// Kamerawunsch aus der Zeit zwischen Einbau und Map-Ready (z. B. die
  /// GPS-Zentrierung beim Start): wird bei `onMapCreated` nachgeholt,
  /// statt still verloren zu gehen.
  (LatLng, double)? _pendingMove;

  /// Sichtfenster vom letzten Kamera-Idle — Grundlage des
  /// Marker-Cullings. Vorher (Karte noch nicht bereit) werden KEINE
  /// Marker eingebaut: `WidgetLayer` positioniert jeden Marker in jedem
  /// Frame auf dem UI-Isolate, und der volle Bestand ungefiltert war der
  /// Grund, warum der Spike nur −28 % Haupt-Thread-Last gemessen hat.
  MapViewBounds? _visibleBounds;

  /// Die Zoomstufe beim letzten Kamera-Stillstand. Sie entscheidet, welche
  /// Höhenlinien noch etwas aussagen — dieselbe Stelle und derselbe Takt
  /// wie das Marker-Culling: bei Idle, nicht je Bild.
  double _idleZoom = 0;

  /// Liest das Sichtfenster der Engine und stößt bei Änderung den
  /// Rebuild an, der die Markerliste neu filtert.
  void _updateVisibleBounds() {
    final controller = _ml;
    if (controller == null || !mounted) return;
    final region = controller.getVisibleRegion();
    setState(() {
      _idleZoom = controller.camera?.zoom ?? _idleZoom;
      _visibleBounds = MapViewBounds(
        west: region.longitudeWest,
        east: region.longitudeEast,
        south: region.latitudeSouth,
        north: region.latitudeNorth,
      );
    });
  }

  /// Die Höhenlinien, die bei der aktuellen Zoomstufe etwas aussagen.
  List<ContourLine> _visibleRainLines(WidgetRef ref) =>
      rainContoursAtZoom(_rainLines(ref), _idleZoom,
          levels: _rainLevels(ref));

  /// Übersetzt einen Fassaden-Marker in einen MapLibre-Marker — die
  /// Kind-Widgets (MushroomIcon, Avatare, Tooltips, Taps) bleiben
  /// unangetastet.
  static ml.Marker asMapLibreMarker(MapViewMarker marker) => ml.Marker(
        point: ml.Geographic(
            lon: marker.point.longitude, lat: marker.point.latitude),
        size: Size(marker.width, marker.height),
        alignment: marker.alignment,
        child: marker.child,
      );

  /// Der zuletzt an die Engine gegebene Style. `initStyle` wird von
  /// `maplibre_android` genau EINMAL bei Map-Ready angewendet — jede
  /// spätere Änderung (z. B. neue Region installiert; jeder Resume
  /// invalidiert `installedMapsProvider`) muss über `setStyle` laufen,
  /// und der String-Vergleich erspart der Engine die unveränderten Fälle.
  String? _appliedStyle;

  /// Der Style, wie ihn die Engine gerade hält — Zugang für alles, was
  /// NICHT im Style-Dokument steht. Genau ein Fall bisher: die
  /// Regenfläche (`maplibre_rain_fill.dart`, dort steht das Warum).
  ml.StyleController? _style;

  /// Die zuletzt eingehängte Fläche. Nach einem `setStyle` ist sie weg,
  /// ohne dass jemand sie entfernt hätte — deshalb wird sie bei jedem
  /// Style-Laden zurückgesetzt und neu gelegt.
  String? _appliedFillUrl;

  /// Reiht die Änderungen der Fläche auf. Ohne das könnten zwei rasch
  /// aufeinanderfolgende Wechsel (Ebene umschalten, während die Fläche
  /// noch lädt) sich überholen — und übrig bliebe eine Quelle ohne
  /// Ebene oder eine Ebene ohne Quelle.
  Future<void> _fillWork = Future.value();

  void _syncRainFill() {
    final style = _style;
    if (style == null) return;
    final fill = ref.read(rainFillFileProvider).valueOrNull;
    _fillWork = _fillWork.then((_) async {
      try {
        _appliedFillUrl = await applyRainFill(style,
            fill: fill, appliedUrl: _appliedFillUrl);
      } catch (_) {
        // Die Fläche ist eine Zugabe zu den Linien; ein Fehlschlag beim
        // Ein- oder Aushängen darf die Karte nicht mitnehmen. Still,
        // weil ein Eintrag je Kartenwechsel den Wochendigest zuschüttet
        // (Lehre aus #124/#136).
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    super.dispose();
  }

  // MapViewCameraDelegate — die Kamera der Fassade.

  @override
  void move(LatLng center, double zoom) {
    final controller = _ml;
    if (controller == null) {
      _pendingMove = (center, zoom);
      return;
    }
    unawaited(controller.moveCamera(
        center: ml.Geographic(lon: center.longitude, lat: center.latitude),
        zoom: zoom));
  }

  @override
  LatLng get center {
    final cam = _ml?.camera;
    if (cam == null) {
      return _pendingMove?.$1 ?? widget.config.initialCenter;
    }
    return LatLng(cam.center.lat.toDouble(), cam.center.lon.toDouble());
  }

  @override
  double get zoom =>
      _ml?.camera?.zoom ?? _pendingMove?.$2 ?? widget.config.initialZoom;

  @override
  Widget build(BuildContext context) {
    ref.listen(maplibreStyleProvider, (previous, next) {
      final style = next.valueOrNull;
      final controller = _ml;
      if (style != null && controller != null && style != _appliedStyle) {
        _appliedStyle = style;
        controller.setStyle(style);
      }
    });
    // Die Fläche hängt NICHT im Style (Begründung in
    // maplibre_rain_fill.dart) — sie wird nachgetragen, sobald der
    // Provider einen neuen Stand hat.
    ref.listen(rainFillFileProvider, (previous, next) => _syncRainFill());

    final styleAsync = ref.watch(maplibreStyleProvider);
    final style = styleAsync.valueOrNull;
    if (styleAsync.hasError || (styleAsync.hasValue && style == null)) {
      // Rückfalllinie: Ohne Style keine leere Karte, sondern die alte
      // Engine — die Nutzerin merkt vom Fehlschlag nichts (geloggt hat
      // ihn der Style-Provider).
      return FlutterMapView(
        config: widget.config,
        controller: widget.controller,
        markers: widget.markers,
      );
    }
    if (style == null) {
      // Style lädt noch: Landton statt „kaputtem" Grau — dieselbe
      // Semantik wie backgroundColor bei flutter_map.
      return ColoredBox(color: widget.config.backgroundColor);
    }

    // Startkamera aus der Fassade, nicht aus der Config: Ein `move()` vor
    // Map-Ready (z. B. GPS-Zentrierung) landet im Fallback-Zustand des
    // Controllers und ginge sonst verloren.
    final initialCenter = widget.controller.center;
    final initialZoom = widget.controller.zoom;
    return ml.MapLibreMap(
      options: ml.MapOptions(
        initStyle: style,
        initCenter: ml.Geographic(
            lon: initialCenter.longitude, lat: initialCenter.latitude),
        initZoom: initialZoom,
        minZoom: widget.config.minZoom,
        maxZoom: widget.config.maxZoom,
        // Rotation und Neigung bleiben aus — wie heute bei flutter_map
        // (InteractiveFlag.all & ~rotate): Drehen verwirrt nur.
        gestures: const ml.MapGestures(
            rotate: false, pan: true, zoom: true, pitch: false),
      ),
      // Läuft bei jedem Style-Laden, also auch nach jedem `setStyle`.
      // Alles Imperative ist dann weg — die Fläche wird deshalb hier neu
      // gelegt und nicht bloß beim ersten Mal.
      onStyleLoaded: (style) {
        _style = style;
        _appliedFillUrl = null;
        _syncRainFill();
      },
      onMapCreated: (controller) {
        _ml = controller;
        _appliedStyle = style;
        final pending = _pendingMove;
        if (pending != null) {
          _pendingMove = null;
          move(pending.$1, pending.$2);
        }
        // Erstes Sichtfenster nach dem Aufbau — ohne diesen Aufruf
        // erschienen Marker erst nach der ersten Geste.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _updateVisibleBounds());
      },
      onEvent: (event) {
        if (event is ml.MapEventLongClick) {
          widget.config.onLongPress
              ?.call(LatLng(event.point.lat.toDouble(),
                  event.point.lon.toDouble()));
        }
        // Culling bei Kamera-Idle, NICHT pro Frame: Zwischen zwei
        // Idle-Momenten bewegt die Engine die eingebauten Marker selbst.
        if (event is ml.MapEventCameraIdle) _updateVisibleBounds();
      },
      // Vektor-Ebenen der Engine (nicht `children` — das sind Widgets):
      // die eigenen Regen-Höhenlinien, eine Ebene je Höhenstufe, weil
      // MapLibres PolylineLayer wie flutter_maps eine Farbe je Ebene
      // kennt. Sie liegen unter dem WidgetLayer und damit unter den
      // Markern.
      layers: [
        for (final (index, level) in _rainLevels(ref).indexed)
          if (_visibleRainLines(ref).any((line) => line.mm == level))
            ml.PolylineLayer(
              polylines: [
                for (final line in _visibleRainLines(ref))
                  if (line.mm == level)
                    ml.Feature(
                      geometry: ml.LineString.from([
                        for (final point in line.points)
                          ml.Geographic(
                              lon: point.longitude, lat: point.latitude),
                      ]),
                    ),
              ],
              color: AppColors.rainLine(index),
              width: 2,
            ),
      ],
      children: [
        // Maßstab und dauerhafte Quellen-Attribution (ODbL-Rechtspflicht;
        // die Texte liefert der Style-Composer an jeder Quelle mit) —
        // die fertigen Widgets des Pakets, Positionen wie bei der
        // flutter_map-Engine: Maßstab unten links, Hinweis unten rechts.
        const ml.MapScalebar(alignment: Alignment.bottomLeft),
        const ml.SourceAttribution(alignment: Alignment.bottomRight),
        if (_visibleBounds != null)
          ml.WidgetLayer(
            // Ohne dieses Flag kommen keine Taps an den Markern an.
            allowInteraction: true,
            markers: [
              // Feste Stapelung der Fassade: Position < Freunde < Spots.
              for (final marker in visibleMarkers(
                  widget.markers.myPosition, _visibleBounds!))
                asMapLibreMarker(marker),
              for (final marker in visibleMarkers(
                  widget.markers.friendLocations, _visibleBounds!))
                asMapLibreMarker(marker),
              for (final marker in visibleMarkers(
                  widget.markers.spots, _visibleBounds!))
                asMapLibreMarker(marker),
            ],
          ),
      ],
    );
  }
}

List<ContourLine> _rainLines(WidgetRef ref) =>
    ref.watch(rainContoursProvider(ref.watch(rainLayerProvider))).value ??
    const [];

List<int> _rainLevels(WidgetRef ref) =>
    rainLevelsFor(ref.watch(rainLayerProvider));
