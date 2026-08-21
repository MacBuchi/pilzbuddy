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

/// Die Beschriftung sitzt auf DERSELBEN Quelle wie die Hauptlinien.
///
/// **Ohne Zahl ist eine Höhenlinie halb stumm** (Betreiber, 2026-08-21):
/// Sie sagt „hier ist es steiler als dort", aber nicht, ob es hinauf
/// oder hinunter geht. Beschriftet werden nur die Hauptlinien (etwa
/// alle 100 Höhenmeter, siehe `contourIndexStepM`) — die dazwischen
/// zählt man ab, so macht es jede topografische Karte.
const contourLabelLayerId = 'hoehenlinien-zahlen';

/// Die Schrift, die als Glyph-Datei mitgeliefert wird
/// (`assets/map_glyphs/`). Der Name ist der Ordnername, NICHT „Noto
/// Sans Medium" — `map_style_composer.dart` bildet die Stil-Namen auf
/// genau diese Ordner ab, und diese Ebene entsteht am Composer vorbei.
const contourLabelFont = 'noto-sans-medium';

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
  String labelColor = '#44515C',
}) async {
  if (geoJson?.key == appliedKey) return appliedKey;

  if (appliedKey != null) {
    // Ebenen vor ihren Quellen — andersherum hinge eine Ebene an einer
    // Quelle, die es nicht mehr gibt.
    await style.removeLayer(contourLabelLayerId);
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
    paint: {'line-color': color, 'line-opacity': 0.3, 'line-width': 0.9},
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
    paint: {'line-color': color, 'line-opacity': 0.6, 'line-width': 1.4},
  ));
  await style.addLayer(ml.SymbolStyleLayer(
    id: contourLabelLayerId,
    sourceId: contourIndexSourceId,
    layout: const {
      'symbol-placement': 'line',
      // Die alte Token-Schreibweise, nicht `["get", "m"]`: Ausdrücke
      // gehen bei `maplibre` 0.3.5 durch `toJObject()` und kämen in der
      // Engine als Object[] an, nicht als Ausdruck (siehe Kopf). Ein
      // String kommt an.
      'text-field': '{m}',
      'text-font': [contourLabelFont],
      'text-size': 11.0,
      // Weit auseinander: Auf einer langen Linie reichen wenige Zahlen,
      // und jede weitere kostet Platz, an dem die Karte liegt.
      'symbol-spacing': 420.0,
      'text-max-angle': 30.0,
      'text-padding': 4.0,
      'text-letter-spacing': 0.05,
      // Zahlen stehen nie auf dem Kopf, auch nicht auf der Südflanke.
      'text-keep-upright': true,
      'text-rotation-alignment': 'map',
      'text-pitch-alignment': 'viewport',
    },
    paint: {
      'text-color': labelColor,
      // Der Hof trennt die Zahl vom Untergrund, ohne eine Kachel Fläche
      // zu beanspruchen — Waldgrün, Ackerbeige und OSM-Raster liegen
      // alle darunter.
      'text-halo-color': '#FFFFFF',
      'text-halo-width': 1.4,
      'text-halo-blur': 0.4,
    },
  ));
  return geoJson.key;
}
