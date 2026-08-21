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

import '../elevation_contour_providers.dart';
import '../forest_data_providers.dart';
import '../rain_data_providers.dart';
import '../rain_layer.dart';
import 'flutter_map_view.dart';
import 'map_view.dart';
import 'maplibre_contour_lines.dart';
import 'maplibre_forest_fill.dart';
import 'maplibre_image_fill.dart' show fillRemovalNeedsNudge;
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
  /// Höhenstufen noch etwas aussagen — dieselbe Stelle und derselbe Takt
  /// wie das Marker-Culling: bei Idle, nicht je Bild.
  ///
  /// **Nicht 0 als Startwert** (Fehler bis 1.47.0, am Gerät gefunden):
  /// `rainContoursAtZoom` rechnet daraus, wie lang eine Linie auf dem
  /// Schirm wäre. Bei Zoom 0 sind das 0,01 Bildpunkte je Kilometer —
  /// eine Kontur müsste rund 3900 km lang sein, um die 40-Pixel-Hürde zu
  /// nehmen. Es überlebte fast nichts, und weil ein Kamera-Idle beim
  /// ersten Aufbau nicht zwingend feuert, blieb es dabei, bis jemand die
  /// Karte bewegte. Der Startwert ist deshalb die Zoomstufe, mit der die
  /// Karte tatsächlich aufgebaut wird.
  late double _idleZoom = widget.controller.zoom;

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

  /// Dasselbe für die Waldfläche (#213) — eigener Merker, weil beide
  /// Ebenen unabhängig kommen und gehen.
  String? _appliedForestUrl;

  /// Analog für die Pilzwetter-Fläche (Ampel-Vorschau).

  /// Die Kennung der zuletzt gelegten Höhenlinien — Fenster plus
  /// Äquidistanz. Eigener Merker, aus demselben Grund wie bei den
  /// Flächen.
  String? _appliedContourKey;

  /// Reiht die Änderungen BEIDER Flächen auf. Ohne das könnten zwei rasch
  /// aufeinanderfolgende Wechsel (Ebene umschalten, während die Fläche
  /// noch lädt) sich überholen — und übrig bliebe eine Quelle ohne
  /// Ebene oder eine Ebene ohne Quelle. EINE Warteschlange für beide:
  /// Auch Regen-gegen-Wald-Wechsel sollen sich nicht überholen können.
  Future<void> _fillWork = Future.value();

  /// Bittet die Engine um ein neues Bild.
  ///
  /// **Warum das nötig ist** (am Emulator gemessen, 2026-08-04):
  /// maplibre-native zeichnet nach dem *Entfernen* einer Ebene nicht von
  /// selbst neu. „Regen aus" ließ Linien und Fläche stehen, bis jemand
  /// die Karte verschob — ein Rebuild ohne Kamerabewegung reichte
  /// nachweislich nicht (Banner weggeklickt, Bild pixelgleich). Beim
  /// *Hinzufügen* passiert es von selbst, weil die neue Quelle lädt und
  /// dabei anstößt. Ein öffentliches `triggerRepaint` hat das Paket
  /// nicht; die Kamera auf ihren eigenen Wert zu setzen ist der
  /// vorhandene Weg.
  ///
  /// Nach dem Frame, nicht in ihm: Entfernt werden die Linienebenen im
  /// `didUpdateWidget` des Pakets, also erst nach diesem Build.
  void _requestRepaint() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _nudgeEngine());
  }

  /// Der eigentliche Stups: Kamera auf ihren eigenen Wert setzen.
  ///
  /// Aus der [_fillWork]-Kette DIREKT aufrufen, nicht über
  /// [_requestRepaint]: Ein Post-Frame-Callback wartet auf den nächsten
  /// Frame — und nach dem asynchronen Entfernen einer Fläche ist keiner
  /// geplant, genau deshalb blieb sie ja stehen (#230).
  void _nudgeEngine() {
    final controller = _ml;
    final camera = controller?.camera;
    if (controller == null || camera == null || !mounted) return;
    unawaited(
        controller.moveCamera(center: camera.center, zoom: camera.zoom));
  }

  void _syncRainFill() {
    final style = _style;
    if (style == null) return;
    final fill = ref.read(rainFillFileProvider).valueOrNull;
    _fillWork = _fillWork.then((_) async {
      try {
        final before = _appliedFillUrl;
        _appliedFillUrl = await applyRainFill(style,
            fill: fill, appliedUrl: _appliedFillUrl);
        // Nach dem WIRKLICHEN Entfernen anstoßen — der Listener-Stups
        // beim Provider-Wechsel kommt zu früh, weil diese Kette
        // asynchron hinterherläuft (#230: „Ebene aus" ließ die Fläche
        // stehen, bis jemand zoomte).
        if (fillRemovalNeedsNudge(
            before: before, after: _appliedFillUrl)) {
          _nudgeEngine();
        }
      } catch (_) {
        // Die Fläche ist eine Zugabe zu den Linien; ein Fehlschlag beim
        // Ein- oder Aushängen darf die Karte nicht mitnehmen. Still,
        // weil ein Eintrag je Kartenwechsel den Wochendigest zuschüttet
        // (Lehre aus #124/#136).
      }
    });
  }

  void _syncForestFill() {
    final style = _style;
    if (style == null) return;
    final fill = ref.read(forestFillFileProvider).valueOrNull;
    _fillWork = _fillWork.then((_) async {
      try {
        final before = _appliedForestUrl;
        _appliedForestUrl = await applyForestFill(style,
            fill: fill,
            appliedUrl: _appliedForestUrl,
            // Liegt die Regenfläche, kommt der Wald darunter (#232) —
            // sonst landete er beim Einschalten obenauf. Umgekehrt ist
            // nichts zu tun: Ein späterer Regen wird angehängt und
            // liegt damit von selbst über dem Wald.
            belowLayerId:
                _appliedFillUrl != null ? rainFillLayerId : null);
        if (fillRemovalNeedsNudge(
            before: before, after: _appliedForestUrl)) {
          _nudgeEngine();
        }
      } catch (_) {
        // Wie beim Regen: still degradieren, Begründung oben.
      }
    });
  }

  /// Die Höhenlinien — GANZ ANS ENDE derselben Warteschlange.
  ///
  /// Die Reihenfolge ist die Aussage: Angehängt nach beiden Flächen
  /// liegen die Linien über ihnen. Eine Linie unter einer 55-%-Fläche
  /// ist keine Linie mehr, und genau deshalb hängen sie nicht als
  /// deklarative Ebene in `children` (siehe maplibre_contour_lines.dart).
  void _syncContours() {
    final style = _style;
    if (style == null) return;
    final geoJson = ref.read(contourGeoJsonProvider).valueOrNull;
    _fillWork = _fillWork.then((_) async {
      try {
        final before = _appliedContourKey;
        _appliedContourKey = await applyContourLines(style,
            geoJson: geoJson, appliedKey: _appliedContourKey);
        if (fillRemovalNeedsNudge(
            before: before, after: _appliedContourKey)) {
          _nudgeEngine();
        }
      } catch (_) {
        // Wie bei den Flächen: still degradieren. Die Karte ohne
        // Höhenlinien ist eine Karte; eine Ausnahme von hier nähme sie
        // ganz mit.
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
    ref.listen(forestFillFileProvider, (previous, next) => _syncForestFill());
    ref.listen(contourGeoJsonProvider, (previous, next) => _syncContours());
    // Jeder Wechsel der Regenebene nimmt etwas von der Karte: die Fläche
    // hier, die Linienebenen im LayerManager des Pakets. Beides braucht
    // danach einen Anstoß — siehe [_requestRepaint].
    ref.listen(rainLayerProvider, (previous, next) => _requestRepaint());
    ref.listen(
        forestLayerEnabledProvider, (previous, next) => _requestRepaint());

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
        _appliedForestUrl = null;
        _appliedContourKey = null;
        _syncRainFill();
        _syncForestFill();
        // Zuletzt, damit die Linien über den Flächen liegen.
        _syncContours();
      },
      onMapCreated: (controller) {
        _ml = controller;
        _appliedStyle = style;
        _idleZoom = controller.camera?.zoom ?? _idleZoom;
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
        // Am selben Ereignis hängen die Fadenkreuz-Werte (#235) — auch
        // sie rechnen bewusst nur bei Stillstand.
        if (event is ml.MapEventCameraIdle) {
          _updateVisibleBounds();
          final camera = _ml?.camera;
          final bounds = _visibleBounds;
          if (camera != null && bounds != null) {
            widget.config.onCameraIdle?.call(
                LatLng(camera.center.lat.toDouble(),
                    camera.center.lon.toDouble()),
                camera.zoom.toDouble(),
                bounds);
          }
        }
      },
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


