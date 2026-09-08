import 'dart:math' as math;

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

  /// Das Sichtfenster bei der aktuellen Kamera (#420).
  ///
  /// Gerechnet wie flutter_map: Web-Mercator mit 256-dp-Kacheln, also
  /// `156543,03 · cos(Breite) / 2^Zoom` Meter je Pixel. Die Zahl muss
  /// nicht auf den Meter stimmen — sie muss sich mit dem Zoom ÄNDERN,
  /// und zwar in derselben Richtung wie bei einer echten Karte. Alles,
  /// was am Stillstand hängt, rechnet aus diesem Fenster seine
  /// Bodenauflösung.
  ///
  /// [size] ist die Kantenlänge der Karte, nicht die des Bildschirms:
  /// gemessen wird gegen die eigene Hülle.
  MapViewBounds boundsFor(Size size) {
    final latRad = _center.latitude * math.pi / 180;
    final metersPerPixel =
        156543.03392 * math.cos(latRad) / math.pow(2, _zoom);
    final halfLng = metersPerPixel * size.width / 2 / (111320 * math.cos(latRad));
    final halfLat = metersPerPixel * size.height / 2 / 111320;
    return MapViewBounds(
      west: _center.longitude - halfLng,
      east: _center.longitude + halfLng,
      south: _center.latitude - halfLat,
      north: _center.latitude + halfLat,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.markers;
    return ColoredBox(
      color: widget.config.backgroundColor,
      child: Wrap(
        children: [
          // Linienzüge ganz unten, wie in beiden echten Engines (#340).
          // Als schlichte Kästchen: Der Fake zeichnet keine Geometrie,
          // aber eine Linie, die hier fehlt, wäre im Test unsichtbar —
          // genau der blinde Fleck, den er nicht haben darf.
          for (final line in m.polylines)
            SizedBox(
                key: const ValueKey('fake-polyline'),
                width: 1,
                height: 1,
                child: ColoredBox(color: line.color)),
          // Dieselbe Reihenfolge wie die echten Engines: Tour-Spur ganz
          // unten. Ohne diese Gruppe hier wäre eine Spur, die auf der
          // Karte fehlt, im Test unsichtbar — genau der blinde Fleck,
          // den der Fake nicht haben darf.
          for (final marker in m.tourTrack)
            SizedBox(
                width: marker.width, height: marker.height,
                child: marker.child),
          // Freunde UNTER der eigenen Position (#403) — wie in beiden
          // echten Engines. Dreht das jemand hier um, prüfen die Tests
          // eine Stapelung, die es auf der Karte nicht gibt.
          for (final marker in m.friendLocations)
            SizedBox(
                width: marker.width, height: marker.height,
                child: marker.child),
          for (final marker in m.myPosition)
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

/// Meldet den Kamerastillstand, wie beide echten Engines es nach jeder
/// Fahrt tun — der Fake tut es NICHT von selbst.
///
/// **Warum nicht von selbst:** Ein automatischer Stillstand nach jedem
/// `move` würde jedem Bestandstest eine Bodenauflösung unterschieben,
/// die er nie bestellt hat, und damit Höhenlinien und Wald-Ausschnitt
/// in Tests einschalten, die von beidem nichts wissen. Wer den
/// Stillstand braucht, sagt es.
///
/// **Warum es ihn überhaupt geben muss:** Bis #420 konnte der Fake gar
/// nicht ausdrücken, dass die Kamera zur Ruhe kommt. Damit war
/// `mapIdleGroundResolutionProvider` im Test immer `null` — und der
/// Zoom-Fit, der aus ihm sein Delta rechnet, zentrierte bloß, statt zu
/// zoomen. Der Fehler aus #420 (jeder weitere Tipp addiert dasselbe
/// Delta erneut) konnte hier deshalb prinzipiell nicht auffallen.
Future<void> simulateCameraIdle(WidgetTester tester) async {
  final finder = find.byType(FakeMapView);
  final fake = tester.widget<FakeMapView>(finder);
  final state = tester.state<FakeMapViewState>(finder);
  fake.config.onCameraIdle?.call(state.center, state.boundsFor(tester.getSize(finder)));
  await tester.pump();
}
