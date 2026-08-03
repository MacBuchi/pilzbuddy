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

import 'flutter_map_view.dart';
import 'map_view.dart';
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

  /// Liest das Sichtfenster der Engine und stößt bei Änderung den
  /// Rebuild an, der die Markerliste neu filtert.
  void _updateVisibleBounds() {
    final controller = _ml;
    if (controller == null || !mounted) return;
    final region = controller.getVisibleRegion();
    setState(() {
      _visibleBounds = MapViewBounds(
        west: region.longitudeWest,
        east: region.longitudeEast,
        south: region.latitudeSouth,
        north: region.latitudeNorth,
      );
    });
  }

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
      children: [
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
