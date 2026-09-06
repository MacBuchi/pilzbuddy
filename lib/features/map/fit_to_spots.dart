import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../models/spot.dart';

/// Wohin die Kamera muss, damit die übergebenen Spots alle im Bild sind
/// (#399).
///
/// **Der Zoom kommt als DELTA, nie als absolute Zahl** — das ist die
/// tragende Entscheidung dieser Datei. MapLibre zählt Zoomstufen in
/// 512-dp-Kacheln, flutter_map in 256ern; dieselbe Zahl bedeutet auf
/// Android und im Web zwei verschiedene Maßstäbe, und genau daran lag
/// 1.98.0 auf dem Gerät durchweg eine Stufe daneben (CLAUDE.md). Eine
/// hier berechnete Zoomstufe wäre auf einer der beiden Engines falsch.
///
/// Eine VERDOPPLUNG ist dagegen auf beiden Seiten eine Verdopplung.
/// Deshalb geht die Rechnung über [currentMetersPerPixel] — eine
/// engine-neutrale Größe, die die Karte im Stillstand ohnehin schon
/// meldet (`mapIdleGroundResolutionProvider`) — und liefert den neuen
/// Zoom als `aktuell + log2(Verhältnis)`.
class FitToSpots {
  const FitToSpots({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;
}

/// Die kleinste Spanne, auf die gezoomt wird: 600 m.
///
/// Ohne sie hätte ein einzelner Spot eine Spanne von 0 und der Zoom liefe
/// gegen unendlich. Aber auch zwei Spots, die zehn Meter auseinander
/// liegen, wollen nicht formatfüllend — man sähe zwei Nadeln und keinen
/// Wald. 600 m ist etwa das, was man beim Absuchen eines Hangs überblickt.
const double kFitMinimumSpanMeters = 600;

/// Wie viel vom Bild Rand bleibt: 15 % auf jeder Seite.
///
/// Ein Spot genau auf der Kante zählt formal als „im Bild" und ist
/// trotzdem halb unter der Knopfspalte oder dem Banner. Der Rand ist
/// bewusst großzügig, weil die Karte oben Banner und unten die
/// Reiterleiste trägt.
const double kFitPaddingFactor = 1.3;

/// `null` **nur**, wenn es nichts zu zeigen gibt.
///
/// [currentZoom] und [currentMetersPerPixel] beschreiben die Kamera, wie
/// sie JETZT steht; [viewportWidthPixels] ist die Breite der Karte in
/// logischen Pixeln. [minZoom]/[maxZoom] sind die Grenzen der Karte —
/// ohne sie liefe der Zoom bei zwei dicht beieinander liegenden Spots
/// über das hinaus, was die Kacheln hergeben.
///
/// **Ohne brauchbare Auflösung wird trotzdem zentriert**, nur eben ohne
/// den Zoom zu ändern. Die Karte meldet ihren Maßstab erst im ersten
/// Stillstand; wer gleich nach dem Start auf das Ampel-Banner tippt,
/// bekäme sonst gar keine Bewegung. „Wo" ist die halbe Antwort und immer
/// zu haben — „wie nah" braucht die Kamera.
FitToSpots? fitToSpots({
  required List<Spot> spots,
  required double currentZoom,
  required double? currentMetersPerPixel,
  required double viewportWidthPixels,
  required double minZoom,
  required double maxZoom,
}) {
  if (spots.isEmpty) return null;
  final scaleKnown = currentMetersPerPixel != null &&
      currentMetersPerPixel.isFinite &&
      currentMetersPerPixel > 0 &&
      viewportWidthPixels > 0;

  var west = spots.first.lng;
  var east = spots.first.lng;
  var south = spots.first.lat;
  var north = spots.first.lat;
  for (final spot in spots) {
    west = math.min(west, spot.lng);
    east = math.max(east, spot.lng);
    south = math.min(south, spot.lat);
    north = math.max(north, spot.lat);
  }

  final center = LatLng((north + south) / 2, (east + west) / 2);
  if (!scaleKnown) return FitToSpots(center: center, zoom: currentZoom);

  // Breite und Höhe in Metern. Die Breite schrumpft mit dem Breitengrad —
  // dieselbe Umrechnung wie in `groundResolution`, damit beide Seiten
  // dieselbe Erde meinen.
  final metersPerDegreeLng =
      111320 * math.cos(center.latitude * math.pi / 180);
  final widthMeters = (east - west) * metersPerDegreeLng;
  final heightMeters = (north - south) * 111320;

  // Die Höhe zählt über das Seitenverhältnis mit: Ein Nord-Süd-Band
  // passt in die Breite und trotzdem nicht ins Bild. Ohne die
  // Viewport-Höhe wäre das nicht exakt zu rechnen; der Faktor unten ist
  // die ehrliche Näherung — ein Handy ist höher als breit, die Höhe ist
  // also nie die knappere Achse, solange man sie durch 2 teilt.
  final span = math.max(widthMeters, heightMeters / 2) * kFitPaddingFactor;
  final targetMetersPerPixel =
      math.max(span, kFitMinimumSpanMeters) / viewportWidthPixels;

  final zoom = currentZoom +
      (math.log(currentMetersPerPixel / targetMetersPerPixel) / math.ln2);
  return FitToSpots(
    center: center,
    zoom: zoom.clamp(minZoom, maxZoom),
  );
}
