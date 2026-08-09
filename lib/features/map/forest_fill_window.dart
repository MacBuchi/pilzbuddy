// Das Sichtfenster der Waldfläche (#249): Welcher Ausschnitt des Gitters
// wird als Bild gemalt, und in welcher Pixelgröße?
//
// Bis 1.68.x war die Antwort „ganz DACH, ein Pixel je Zelle" — ein
// 52-MB-RGBA-Puffer bei jedem Einfärben, der größte Puffer der App
// (`docs/map-performance.md`). Feinere Gitter (100 m: 324 MB) und
// Sechseck-Zeichnung (mehrere Pixel je Zelle) sprengen dieses Modell
// unabhängig voneinander — deshalb malt die Fläche seither nur noch, was
// sichtbar ist, mit festem Pixelbudget.
//
// Reines Dart ohne Flutter, wie `forest_grid.dart`: Die Entscheidung
// „neu malen oder das alte Bild behalten?" ist eine Rechnung, und sie
// soll ohne Karte testbar sein.
import 'dart:math' as math;

import 'map_view/marker_culling.dart' show MapViewBounds;
import 'rain_grid.dart' show mercatorY;

/// Ein geplanter Bildausschnitt: geographische Box plus Pixelmaße.
class FillWindow {
  const FillWindow({
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.width,
    required this.height,
  });

  final double west;
  final double east;
  final double north;
  final double south;

  /// Bildgröße in Pixeln — die Zeilen liegen Mercator-verteilt
  /// (`forestFillPng`), die Spalten grad-linear.
  final int width;
  final int height;

  /// Deterministische Kurzform für Dateinamen: Die MapLibre-Strecke ist
  /// idempotent auf der URL, ein neuer Ausschnitt braucht also einen
  /// neuen Namen. Gerundet auf ~11 m — feiner unterscheiden sich zwei
  /// Planungen nie, weil der Planer nur in Viewport-Schritten denkt.
  String get key => [
        (west * 10000).round(),
        (east * 10000).round(),
        (north * 10000).round(),
        (south * 10000).round(),
        width,
        height,
      ].join('_');
}

/// Längste Bildkante des Fensters. 1536 px ⇒ höchstens ~9,4 MB
/// RGBA-Puffer (1536² × 4) statt 52 MB für ganz DACH — und beim
/// Hineinzoomen wird die Fläche SCHÄRFER statt hochskaliert, weil
/// dieselben Pixel dann weniger Kilometer abdecken.
const fillWindowBudget = 1536;

/// Rand um das Sichtfenster als Anteil seiner Spanne je Seite (50 % ⇒
/// gerendert wird die doppelte Breite). Der Rand ist der Grund, warum
/// kleines Schieben KEIN Neumalen auslöst: Erst wenn das Sichtfenster
/// den gerenderten Kasten verlässt, wird neu geplant.
const fillWindowMargin = 0.5;

/// Ab diesem Verhältnis „Fensterspanne zu Sichtfenster-Spanne" wird beim
/// Hineinzoomen neu geplant: Das alte Bild wäre dann auf weniger als ein
/// Drittel seiner Pixel gestreckt. 3,5 statt 3,0, damit der Wert nicht
/// GENAU auf der Grenze des frisch geplanten Fensters liegt (Rand 50 %
/// ⇒ Spanne 2× Sichtfenster) und jede Zoom-Raste neu malt.
const fillWindowZoomFactor = 3.5;

/// Plant den Bildausschnitt für [viewport] — oder gibt `null` zurück,
/// wenn [previous] noch trägt (Sichtfenster liegt im alten Kasten und
/// ist nicht zu klein geworden) oder wenn der Viewport das Gitter gar
/// nicht schneidet.
///
/// Der Aufrufer behält bei `null` das alte Fenster — dieselbe Instanz,
/// damit stromabwärts niemand neu rechnet.
FillWindow? planFillWindow({
  FillWindow? previous,
  required MapViewBounds viewport,
  required double gridWest,
  required double gridEast,
  required double gridNorth,
  required double gridSouth,
  int budget = fillWindowBudget,
}) {
  // Sichtfenster aufs Gitter beschneiden. Ohne Schnitt gibt es nichts
  // NEU zu malen: `null` heißt für den Aufrufer „behalte, was du hast" —
  // beim ersten Mal also nichts, sonst das alte (ohnehin unsichtbare)
  // Fenster.
  final west = math.max(viewport.west, gridWest);
  final east = math.min(viewport.east, gridEast);
  final north = math.min(viewport.north, gridNorth);
  final south = math.max(viewport.south, gridSouth);
  if (west >= east || south >= north) return null;

  if (previous != null) {
    final contained = west >= previous.west &&
        east <= previous.east &&
        north <= previous.north &&
        south >= previous.south;
    final tooSmall =
        (east - west) * fillWindowZoomFactor < previous.east - previous.west;
    if (contained && !tooSmall) return null;
  }

  final lonSpan = east - west;
  final latSpan = north - south;
  final windowWest = math.max(gridWest, west - lonSpan * fillWindowMargin);
  final windowEast = math.min(gridEast, east + lonSpan * fillWindowMargin);
  final windowNorth = math.min(gridNorth, north + latSpan * fillWindowMargin);
  final windowSouth = math.max(gridSouth, south - latSpan * fillWindowMargin);

  // Pixel-Seitenverhältnis aus MERCATOR-Spannen, damit ein Pixel auf der
  // Karte ungefähr quadratisch ist: x ist dort linear in Grad, y nicht.
  final mercWidth = (windowEast - windowWest) * math.pi / 180;
  final mercHeight =
      (mercatorY(windowNorth) - mercatorY(windowSouth)).abs() / 6378137.0;
  int width, height;
  if (mercWidth >= mercHeight) {
    width = budget;
    height = math.max(1, (budget * mercHeight / mercWidth).round());
  } else {
    height = budget;
    width = math.max(1, (budget * mercWidth / mercHeight).round());
  }

  return FillWindow(
    west: windowWest,
    east: windowEast,
    north: windowNorth,
    south: windowSouth,
    width: width,
    height: height,
  );
}
