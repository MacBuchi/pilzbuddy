// Die Regenfläche in der MapLibre-Engine — imperativ, nicht im Style.
//
// **Warum nicht im Style-Dokument**, wo die DWD-Bildebene liegt: Der
// Style entsteht einmal und ändert sich fast nie (Anti-Race aus der
// Spike-Autopsie, siehe `maplibre_style_provider.dart`); die Fläche
// ändert sich mehrmals täglich. Hinge der Style an ihr, käme bei jedem
// neuen Messwert ein vollständiges `setStyle` — für ein Bild, das sich
// auch einzeln austauschen lässt. Der Versuch hat außerdem neun Tests in
// eine Zeitüberschreitung laufen lassen: Sie halten
// `maplibreStyleProvider.future` fest, und ein Provider, der beim
// Auflösen der Fläche verworfen wird, erfüllt sie nie.
//
// Dieselbe Strecke trägt später das Ampel-Raster, das
// `map_style_composer.dart` schon als künftigen Fall nennt.
import 'package:maplibre/maplibre.dart' as ml;

import '../rain_data_providers.dart';

/// Id der Bildquelle und der Ebene. Beide dürfen mit nichts aus
/// `composeMapLibreStyle` kollidieren — dort heißen die Regen-Ids
/// `regen` (das DWD-Bild), hier bewusst anders.
const rainFillSourceId = 'regen-flaeche';
const rainFillLayerId = 'regen-flaeche';

/// Die erste Ebene, die `MapLibreMap.layers` anlegt (LayerManager im
/// Paket zählt ab null). Das sind unsere Höhenlinien — die Fläche gehört
/// darunter.
const firstAnnotationLayerId = 'maplibre-layer-0';

/// Die Bildquelle: das eingefärbte Gitter, verortet auf **seinen**
/// Grenzen. Nicht auf denen der DWD-Bildebene — das Gitter ist auf seine
/// Zellen mit Daten beschnitten, die Bildebene deckt etwas mehr ab, und
/// der Unterschied sind rund zwanzig Kilometer Versatz gegen die eigenen
/// Linien.
ml.ImageSource rainFillSource(String url, RainFill fill) => ml.ImageSource(
      id: rainFillSourceId,
      url: url,
      coordinates: ml.LngLatQuad(
        topLeft: ml.Geographic(lon: fill.west, lat: fill.north),
        topRight: ml.Geographic(lon: fill.east, lat: fill.north),
        bottomRight: ml.Geographic(lon: fill.east, lat: fill.south),
        bottomLeft: ml.Geographic(lon: fill.west, lat: fill.south),
      ),
    );

/// Die Rasterebene dazu.
///
/// `raster-opacity: 1` mit Absicht: Die Durchsichtigkeit steckt schon in
/// den Bildpunkten (`rainFillAlpha`). Zweimal abgeschwächt wäre die
/// Fläche nicht mehr zu sehen.
///
/// `raster-resampling: nearest` wie beim DWD-Bild und wie
/// `FilterQuality.none` auf dem flutter_map-Pfad: Die Daten sind ein
/// 1-km-Raster, weichgezeichnet sähen sie genauer aus, als sie sind.
ml.RasterStyleLayer rainFillStyleLayer() => const ml.RasterStyleLayer(
      id: rainFillLayerId,
      sourceId: rainFillSourceId,
      paint: {'raster-opacity': 1.0, 'raster-resampling': 'nearest'},
    );

/// Hängt die Fläche ein, tauscht sie aus oder nimmt sie weg — und
/// liefert die URL zurück, die danach auf der Karte liegt (`null` =
/// keine).
///
/// [appliedUrl] ist die URL des letzten Aufrufs; ist sie gleich, passiert
/// nichts. Nach einem `setStyle` ist alles Imperative weg — dann ruft die
/// Ansicht mit `appliedUrl: null` erneut auf.
///
/// **Die Reihenfolge ist der ganze Punkt.** Die Fläche muss unter die
/// Höhenlinien: Sie ist Orientierung, die Linien sind die Aussage. Der
/// Versuch mit [firstAnnotationLayerId] deckt den Fall ab, dass die
/// Linien schon liegen; scheitert er, gibt es noch keine, und Anhängen
/// ist genau richtig — der LayerManager legt sie gleich darüber.
Future<String?> applyRainFill(
  ml.StyleController style, {
  required ({String url, RainFill fill})? fill,
  required String? appliedUrl,
}) async {
  if (fill?.url == appliedUrl) return appliedUrl;

  if (appliedUrl != null) {
    await style.removeLayer(rainFillLayerId);
    await style.removeSource(rainFillSourceId);
  }
  if (fill == null) return null;

  await style.addSource(rainFillSource(fill.url, fill.fill));
  try {
    await style.addLayer(rainFillStyleLayer(),
        belowLayerId: firstAnnotationLayerId);
  } catch (_) {
    // Es gibt noch keine Linienebene, unter die die Fläche gehört (die
    // Engine wirft dann beim Einordnen). Anhängen ist hier kein
    // Notbehelf, sondern dasselbe Ergebnis: Die Linien kommen danach
    // und landen von selbst darüber.
    await style.addLayer(rainFillStyleLayer());
  }
  return fill.url;
}
