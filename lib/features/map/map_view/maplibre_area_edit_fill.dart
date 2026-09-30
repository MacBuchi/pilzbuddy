// Maske und Entwurf der Kartenbereiche (#630, Stufe 2b) in der
// MapLibre-Engine. Mechanik in `maplibre_image_fill.dart` — hier nur Ids
// und Resampling.
import 'package:maplibre/maplibre.dart' as ml;

import '../../offline_areas/area_edit_fill.dart';
import 'maplibre_image_fill.dart';

/// Dürfen mit nichts aus `composeMapLibreStyle` und keiner anderen
/// Fläche kollidieren.
const areaEditFillSourceId = 'bereiche-bearbeiten';
const areaEditFillLayerId = 'bereiche-bearbeiten';

/// `nearest`: Die Schraffur sind einzelne Bildpunkte, weichgezeichnet
/// würde sie zum Grauschleier.
const areaEditFillResampling = 'nearest';

/// Hängt das Bild ein, tauscht es aus oder nimmt es weg — Verhalten wie
/// [applyImageFill]. Es gehört ZUOBERST; wer eine andere Fläche danach
/// anhängt, legt es neu (maplibre_map_view.dart).
Future<String?> applyAreaEditFill(
  ml.StyleController style, {
  required ({String url, AreaEditFill fill})? fill,
  required String? appliedUrl,
}) =>
    applyImageFill(
      style,
      sourceId: areaEditFillSourceId,
      layerId: areaEditFillLayerId,
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
      resampling: areaEditFillResampling,
    );
