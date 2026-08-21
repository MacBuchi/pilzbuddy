// Die Höhenlinien in der MapLibre-Engine — imperativ, wie die
// Bildflächen und aus demselben Grund (`maplibre_image_fill.dart`): Der
// Style entsteht einmal und darf sich nicht bei jedem Kamera-Stillstand
// neu setzen.
//
// **Warum imperativ und nicht als `ml.PolylineLayer` unter
// `MapLibreMap.children`:** Die deklarativen Ebenen legt das Paket im
// `onStyleLoaded` an — also BEVOR die asynchrone Kette dieser Ansicht
// die Wald- und Regenflächen einhängt. Die Linien lägen damit unter
// einer 55-%-Fläche, und eine Linie unter einer Fläche ist keine Linie
// mehr. Angehängt an dieselbe Warteschlange liegen sie zuverlässig
// obenauf; über ihnen sind nur die Marker, und die sind
// Flutter-Widgets über der ganzen Karte.
import 'package:maplibre/maplibre.dart' as ml;

/// Zwei Quellen, zwei Ebenen: normale Linien und Hauptlinien.
///
/// **Warum nicht eine Ebene mit einem Ausdruck auf `line-width`:**
/// `maplibre` 0.3.5 schickt Paint-Werte durch `toJObject()`, das
/// String, Zahl, Bool, Liste und Map kennt — ein Style-Ausdruck käme
/// als `Object[]` in der Engine an und nicht als Ausdruck. Skalare
/// kommen an, also zwei Ebenen mit je einem Skalar.
const contourSourceId = 'hoehenlinien';
const contourIndexSourceId = 'hoehenlinien-haupt';
const contourLayerId = 'hoehenlinien';
const contourIndexLayerId = 'hoehenlinien-haupt';

/// Die Quellenangabe, die an den Linien hängt — dieselbe Fassung wie im
/// Blatt und in `map_data_license.dart`.
const contourAttribution = '© Europäische Union, Copernicus DEM';

/// Das GeoJSON beider Ebenen samt der Kennung, auf die dieser Aufruf
/// idempotent ist.
typedef ContourGeoJson = ({String normal, String index, String key});

/// Hängt die Linien ein, tauscht sie aus oder nimmt sie weg — und
/// liefert die Kennung zurück, die danach auf der Karte liegt.
///
/// [appliedKey] ist die Kennung des letzten Aufrufs; ist sie gleich,
/// passiert nichts. Nach einem `setStyle` ist alles Imperative weg —
/// dann ruft die Ansicht mit `appliedKey: null` erneut auf.
Future<String?> applyContourLines(
  ml.StyleController style, {
  required ContourGeoJson? geoJson,
  required String? appliedKey,
  String color = '#5B6B7A',
}) async {
  if (geoJson?.key == appliedKey) return appliedKey;

  if (appliedKey != null) {
    // Ebenen vor ihren Quellen — andersherum hinge eine Ebene an einer
    // Quelle, die es nicht mehr gibt.
    await style.removeLayer(contourIndexLayerId);
    await style.removeLayer(contourLayerId);
    await style.removeSource(contourIndexSourceId);
    await style.removeSource(contourSourceId);
  }
  if (geoJson == null) return null;

  await style.addSource(ml.GeoJsonSource(
    id: contourSourceId,
    data: geoJson.normal,
    attribution: contourAttribution,
  ));
  await style.addLayer(ml.LineStyleLayer(
    id: contourLayerId,
    sourceId: contourSourceId,
    layout: const {'line-cap': 'round', 'line-join': 'round'},
    paint: {'line-color': color, 'line-opacity': 0.55, 'line-width': 1.0},
  ));
  await style.addSource(ml.GeoJsonSource(
    id: contourIndexSourceId,
    data: geoJson.index,
    attribution: contourAttribution,
  ));
  await style.addLayer(ml.LineStyleLayer(
    id: contourIndexLayerId,
    sourceId: contourIndexSourceId,
    layout: const {'line-cap': 'round', 'line-join': 'round'},
    paint: {'line-color': color, 'line-opacity': 0.85, 'line-width': 1.6},
  ));
  return geoJson.key;
}
