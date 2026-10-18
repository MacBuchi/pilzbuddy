// Ohne Flutter und ohne `pmtiles`: Der Entwurf der Kartenbereiche wird im
// Browser in einem Web Worker gemalt (#689, B2), und `area_plan.dart`
// zieht über `pmtiles` `dart:io` mit.

/// Der Zoom, in dem eine `TileSetShape` ihre Kacheln merkt — fest, damit
/// die Form nicht vom Zoom des Hosts abhängt: Ein höherer Zoom des
/// Archivs sind die Kinder dieser Kacheln, ein niedrigerer die Eltern.
const kAreaShapeZoom = 13;

/// Der Schlüssel einer Kachel bei [zoom] — `TileSetShape.keyOf`.
int areaTileKey(int x, int y, int zoom) => (x << zoom) | y;
