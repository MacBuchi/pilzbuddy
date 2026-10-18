// Ohne Flutter: Auch die Kartenflächen rechnen mit dem Sichtfenster, und
// die laufen im Browser in einem Web Worker (#689, B2).

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
