// Die Fundorte-Fläche (#467) in der MapLibre-Engine. Mechanik in
// `maplibre_image_fill.dart` — hier nur Ids und Resampling.
import 'package:maplibre/maplibre.dart' as ml;

import '../gbif_finds_providers.dart';
import 'maplibre_image_fill.dart';

/// Dürfen mit nichts aus `composeMapLibreStyle` und nicht mit
/// `wald-flaeche`/`regen-flaeche` kollidieren.
const gbifFillSourceId = 'fundorte-flaeche';
const gbifFillLayerId = 'fundorte-flaeche';

/// `linear`, anders als der Wald: Die Scheiben sind weiche Flächen,
/// keine Klötzchen — hart gerastert sähe eine 3-px-Scheibe aus wie ein
/// Pixelfehler.
const gbifFillResampling = 'linear';

/// Hängt die Fundorte ein, tauscht sie aus oder nimmt sie weg —
/// Verhalten wie [applyImageFill].
///
/// [belowLayerId]: Liegt die Regenfläche, kommen die Fundorte DARUNTER
/// (wie der Wald, #232) — Regen ist die flüchtige Information.
Future<String?> applyGbifFill(
  ml.StyleController style, {
  required ({String url, GbifFillImage fill})? fill,
  required String? appliedUrl,
  String? belowLayerId,
}) =>
    applyImageFill(
      style,
      sourceId: gbifFillSourceId,
      layerId: gbifFillLayerId,
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
      resampling: gbifFillResampling,
      belowLayerId: belowLayerId,
    );
