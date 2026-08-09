// Die Pilzwetter-Fläche in der MapLibre-Engine (Ampel-Vorschau).
// Mechanik in `maplibre_image_fill.dart` — hier nur Ids und Resampling.
import 'package:maplibre/maplibre.dart' as ml;

import '../../ampel/ampel_fill.dart';
import 'maplibre_image_fill.dart';

/// Id der Bildquelle und der Ebene — darf mit nichts aus
/// `composeMapLibreStyle`, `regen-flaeche` und `wald-flaeche`
/// kollidieren.
const ampelFillSourceId = 'ampel-flaeche';
const ampelFillLayerId = 'ampel-flaeche';

/// `nearest` wie der Wald: Die Kilometer-Zellen SIND die Daten, und die
/// drei Stufen sind Klassen — weichgezeichnet sähe das Gitter genauer
/// aus, als es ist.
const ampelFillResampling = 'nearest';

/// Hängt die Pilzwetter-Fläche ein, tauscht sie aus oder nimmt sie weg
/// — Verhalten wie [applyImageFill], siehe dort.
///
/// Kein `belowLayerId`: Die Fläche ersetzt die Regenfläche (im Blatt
/// wechselseitig exklusiv) und liegt wie diese ÜBER dem Wald — sie ist
/// die flüchtige Information, der Wald der Grund darunter (#232).
Future<String?> applyAmpelFill(
  ml.StyleController style, {
  required ({String url, AmpelFill fill})? fill,
  required String? appliedUrl,
}) =>
    applyImageFill(
      style,
      sourceId: ampelFillSourceId,
      layerId: ampelFillLayerId,
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
      resampling: ampelFillResampling,
    );
