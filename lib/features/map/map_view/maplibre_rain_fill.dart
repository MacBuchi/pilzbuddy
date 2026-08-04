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
/// `raster-resampling: linear` — **anders als beim DWD-Bild**, und die
/// Abweichung ist eine bewusste Kehrtwende:
///
/// Solange die Fläche nur ein Hauch unter den Linien war, galt dieselbe
/// Regel wie für das DWD-Bild — hart lassen, denn weichgezeichnet sieht
/// ein 1-km-Raster genauer aus, als es ist. Seit die Fläche die Aussage
/// trägt, kippt die Abwägung: Am Gerät gemessen (2026-08-04) traten bei
/// 55 % Deckkraft die 1-km-Treppenstufen an jeder Bandgrenze hervor —
/// grob, und im Widerspruch zu den geglätteten Konturen, die aus
/// **demselben** Feld kommen und die Beschriftung tragen. Zwei
/// Darstellungen desselben Felds dürfen nicht verschieden aussehen.
///
/// Die Genauigkeit geht dabei nicht verloren: Der Wert am Spot kommt aus
/// dem ROHEN Gitter (`rain_stack.dart`), nicht aus diesem Bild. Weich
/// ist hier eine Aussage über die Darstellung, nicht über die Daten.
///
/// Das Radarbild des DWD bleibt hart — dort zeichnen wir nicht selbst.
ml.RasterStyleLayer rainFillStyleLayer() => const ml.RasterStyleLayer(
      id: rainFillLayerId,
      sourceId: rainFillSourceId,
      paint: {'raster-opacity': 1.0, 'raster-resampling': 'linear'},
    );

/// Hängt die Fläche ein, tauscht sie aus oder nimmt sie weg — und
/// liefert die URL zurück, die danach auf der Karte liegt (`null` =
/// keine).
///
/// [appliedUrl] ist die URL des letzten Aufrufs; ist sie gleich, passiert
/// nichts. Nach einem `setStyle` ist alles Imperative weg — dann ruft die
/// Ansicht mit `appliedUrl: null` erneut auf.
///
/// Seit 1.48.0 wird die Fläche schlicht angehängt: Über ihr liegt nichts
/// Eigenes mehr. Bis 1.47.0 musste sie unter die Höhenlinien, die der
/// LayerManager des Pakets als `maplibre-layer-0` anlegte — die gibt es
/// nicht mehr. Die Marker sind Flutter-Widgets und liegen ohnehin über
/// der ganzen Karte.
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
  await style.addLayer(rainFillStyleLayer());
  return fill.url;
}
