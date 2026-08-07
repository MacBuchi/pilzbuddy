// Die Regenfläche in der MapLibre-Engine.
//
// Die Mechanik (imperativ statt im Style, Idempotenz auf der URL, die
// Grenzen vom Bild statt aus einer Konstante) liegt seit der
// Waldtypen-Ebene (#213) in `maplibre_image_fill.dart` — hier stehen nur
// noch die Regen-Belange: die Ids und das Resampling.
import 'package:maplibre/maplibre.dart' as ml;

import '../rain_data_providers.dart';
import 'maplibre_image_fill.dart';

/// Id der Bildquelle und der Ebene. Beide dürfen mit nichts aus
/// `composeMapLibreStyle` kollidieren — dort heißen die Regen-Ids
/// `regen` (das DWD-Bild), hier bewusst anders.
const rainFillSourceId = 'regen-flaeche';
const rainFillLayerId = 'regen-flaeche';

/// `linear`, **anders als beim DWD-Bild**, und die Abweichung ist eine
/// bewusste Kehrtwende: Seit die Fläche die Aussage trägt (1.48.0),
/// traten bei 55 % Deckkraft die 1-km-Treppenstufen an jeder Bandgrenze
/// hervor — im Widerspruch zu den geglätteten Werten aus demselben Feld.
/// Die Genauigkeit leidet nicht: Der Wert am Spot kommt aus dem ROHEN
/// Gitter, nicht aus diesem Bild. Das Radarbild des DWD bleibt hart —
/// dort zeichnen wir nicht selbst.
const rainFillResampling = 'linear';

/// Hängt die Regenfläche ein, tauscht sie aus oder nimmt sie weg —
/// Verhalten wie [applyImageFill], siehe dort.
Future<String?> applyRainFill(
  ml.StyleController style, {
  required ({String url, RainFill fill})? fill,
  required String? appliedUrl,
}) =>
    applyImageFill(
      style,
      sourceId: rainFillSourceId,
      layerId: rainFillLayerId,
      fill: fill == null
          ? null
          : (
              url: fill.url,
              west: fill.fill.west,
              east: fill.fill.east,
              north: fill.fill.north,
              south: fill.fill.south,
            ),
      appliedUrl: appliedUrl,
      resampling: rainFillResampling,
    );
