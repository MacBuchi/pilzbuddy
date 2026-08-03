// Viewport-Culling für die MapLibre-Engine — pur und getestet
// (test/marker_culling_test.dart).
//
// Warum es das braucht: `ml.WidgetLayer` positioniert JEDEN übergebenen
// Marker in jedem Frame auf dem UI-Isolate (kein eigenes Culling, offenes
// TODO im Paket) — genau die Schicht, in der der ANR aus #151 saß. Der
// Spike hat deshalb nur −28 % Haupt-Thread-Last gemessen statt −50 %.
// Gefiltert wird bei Kamera-Idle (nicht pro Frame): Zwischen zwei
// Idle-Momenten bewegt die Engine die schon eingebauten Marker selbst.
import '../map_view/map_view.dart';

/// Sichtfenster in Grad — engine-neutral, damit die Funktion nicht am
/// maplibre-Typ `LngLatBounds` hängt (Web-Build!) und im Test ohne
/// Platform-View prüfbar ist.
class MapViewBounds {
  const MapViewBounds({
    required this.west,
    required this.east,
    required this.south,
    required this.north,
  });

  final double west;
  final double east;
  final double south;
  final double north;
}

/// Filtert Marker auf das Sichtfenster plus Rand.
///
/// [margin] ist der Puffer je Seite als Anteil der Fensterspanne
/// (Standard 25 %): Ohne ihn ploppen Marker beim Wischen sichtbar am
/// Bildschirmrand auf — mit ihm sind sie schon eingebaut, bevor sie ins
/// Bild wandern. Die Reihenfolge bleibt erhalten, sie ist die
/// Zeichen-Stapelung der Fassade (Position < Freunde < Spots).
///
/// Bewusst ohne Antimeridian-Behandlung: Die App zeigt DACH-Regionen
/// und Spots ihrer Nutzer — ein Sichtfenster über ±180° Länge kommt
/// hier nicht vor, und die Übersichtskarte endet ohnehin in Europa.
List<MapViewMarker> visibleMarkers(
  List<MapViewMarker> markers,
  MapViewBounds bounds, {
  double margin = 0.25,
}) {
  final lonPad = (bounds.east - bounds.west) * margin;
  final latPad = (bounds.north - bounds.south) * margin;
  final west = bounds.west - lonPad;
  final east = bounds.east + lonPad;
  final south = bounds.south - latPad;
  final north = bounds.north + latPad;
  return [
    for (final marker in markers)
      if (marker.point.longitude >= west &&
          marker.point.longitude <= east &&
          marker.point.latitude >= south &&
          marker.point.latitude <= north)
        marker,
  ];
}
