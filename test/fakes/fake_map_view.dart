import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/map_view/map_view.dart';

/// Karten-Fake für Widget-Tests: rendert alle Marker-Kinder in einem
/// `Wrap` — nicht überlappend, damit `find.byTooltip(...)`-Taps das
/// richtige Widget treffen — und simuliert die Kamera synchron. Keine
/// Kacheln, kein Netz, keine Engine.
///
/// `pumpApp` hängt sie standardmäßig hinter die [mapViewBuilderProvider]-
/// Fassade; Tests, die flutter_map-Interna beweisen (Layer, Puffer,
/// Kamera-Wächter), pumpen mit `useRealMap: true`.
class FakeMapView extends StatefulWidget {
  const FakeMapView({
    super.key,
    required this.config,
    required this.controller,
    required this.markers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewMarkers markers;

  @override
  State<FakeMapView> createState() => FakeMapViewState();
}

/// Öffentlich, damit Tests die simulierte Kamera abfragen können
/// (`tester.state<FakeMapViewState>(...)`).
class FakeMapViewState extends State<FakeMapView>
    implements MapViewCameraDelegate {
  late LatLng _center = widget.config.initialCenter;
  late double _zoom = widget.config.initialZoom;

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

  // ---- MapViewCameraDelegate ----
  @override
  void move(LatLng center, double zoom) {
    _center = center;
    // Wie die echte Karte: Zoom-Grenzen gelten auch für programmatische
    // Bewegungen.
    _zoom = zoom.clamp(widget.config.minZoom, widget.config.maxZoom);
  }

  @override
  LatLng get center => _center;

  @override
  double get zoom => _zoom;

  @override
  Widget build(BuildContext context) {
    final m = widget.markers;
    return ColoredBox(
      color: widget.config.backgroundColor,
      child: Wrap(
        children: [
          for (final marker in m.myPosition)
            SizedBox(
                width: marker.width, height: marker.height,
                child: marker.child),
          for (final marker in m.friendLocations)
            SizedBox(
                width: marker.width, height: marker.height,
                child: marker.child),
          for (final marker in m.spots)
            SizedBox(
                width: marker.width, height: marker.height,
                child: marker.child),
        ],
      ),
    );
  }
}

/// Löst den Long-Press-Callback der Karte aus, als hätte der Nutzer auf
/// die Stelle [latLng] gedrückt gehalten.
Future<void> simulateMapLongPress(WidgetTester tester, LatLng latLng) async {
  final fake = tester.widget<FakeMapView>(find.byType(FakeMapView));
  fake.config.onLongPress?.call(latLng);
  await tester.pump();
}
