// Die Waldtypen-Fläche in der MapLibre-Engine (#213). Mechanik in
// `maplibre_image_fill.dart` — hier nur die Wald-Belange: Ids und
// Resampling.
import 'package:maplibre/maplibre.dart' as ml;

import '../forest_data_providers.dart';
import 'maplibre_image_fill.dart';

/// Id der Bildquelle und der Ebene — dürfen mit nichts aus
/// `composeMapLibreStyle` und nicht mit `regen-flaeche` kollidieren.
const forestFillSourceId = 'wald-flaeche';
const forestFillLayerId = 'wald-flaeche';

/// `nearest`, anders als der Regen: Die 250-m-Klötzchen SIND die Daten —
/// weichgezeichnet sähe das Gitter genauer aus, als es ist. Dieselbe
/// Regel, nach der das DWD-Radarbild hart bleibt.
const forestFillResampling = 'nearest';

/// Hängt die Waldfläche ein, tauscht sie aus oder nimmt sie weg —
/// Verhalten wie [applyImageFill], siehe dort.
///
/// [belowLayerId]: Liegt die Regenfläche schon, gehört der Wald
/// DARUNTER (#232) — Regen ist die flüchtige Information, sie bleibt
/// obenauf lesbar.
Future<String?> applyForestFill(
  ml.StyleController style, {
  required ({String url, ForestFillImage fill})? fill,
  required String? appliedUrl,
  String? belowLayerId,
}) =>
    applyImageFill(
      style,
      sourceId: forestFillSourceId,
      layerId: forestFillLayerId,
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
      resampling: forestFillResampling,
      belowLayerId: belowLayerId,
    );
