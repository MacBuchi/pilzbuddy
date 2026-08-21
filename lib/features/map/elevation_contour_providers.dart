// Die Provider der Höhenlinien-Ebene: Schalter, Stillstands-Zoom,
// Fenster mit Gedächtnis, und der Isolate-Lauf.
//
// Aufgeteilt wie beim Wald (`forest_data_providers.dart`): Die Rechnung
// steht flutter-frei in `elevation_contours.dart`, hier steht nur, WANN
// sie läuft.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'elevation_contours.dart';
import 'elevation_grid.dart';
import 'elevation_providers.dart';
import 'forest_data_providers.dart' show mapIdleBoundsProvider;
import 'forest_fill_window.dart';

/// Ist die Ebene an?
///
/// Sitzungslokal wie `forestLayerEnabledProvider` und aus demselben
/// Grund: Eine über Nacht vergessene Ebene verwirrt mehr, als der eine
/// Tipp zum Wiedereinschalten kostet. Anders als bei Wald und Regen
/// kostet sie zwar keinen Download — aber sie legt Linien über die
/// Karte, und das ist derselbe Handel.
final contourLayerEnabledProvider = StateProvider<bool>((ref) => false);

/// Die Zoomstufe beim letzten Kamera-Stillstand — Geschwister von
/// `mapIdleCenterProvider` (#235) und [mapIdleBoundsProvider] (#249).
///
/// Sie entscheidet die Äquidistanz. Aus dem Sichtfenster ableiten ginge
/// nicht: Dafür bräuchte es die Pixelbreite des Schirms, und die kennt
/// ein Provider nicht.
final mapIdleZoomProvider = StateProvider<double?>((ref) => null);

/// Der geplante Ausschnitt der Höhenlinien.
///
/// Ein Notifier mit Gedächtnis, wortgleich zu `ForestFillWindowNotifier`
/// und aus demselben Grund: Kleines Schieben innerhalb des gerenderten
/// Kastens gibt DIESELBE Instanz zurück, und Riverpod lässt daraufhin
/// alles stromabwärts in Ruhe. Ohne das wäre jeder Kamera-Stillstand
/// ein Isolate-Lauf.
class ContourWindowNotifier extends Notifier<FillWindow?> {
  FillWindow? _last;

  @override
  FillWindow? build() {
    final bounds = ref.watch(mapIdleBoundsProvider);
    final grid = ref.watch(elevationGridProvider).valueOrNull;
    if (bounds == null || grid == null) return _last;
    _last = planFillWindow(
          previous: _last,
          viewport: bounds,
          gridWest: grid.west,
          gridEast: grid.east,
          gridNorth: grid.north,
          gridSouth: grid.south,
        ) ??
        _last;
    return _last;
  }
}

final contourWindowProvider =
    NotifierProvider<ContourWindowNotifier, FillWindow?>(
        ContourWindowNotifier.new);

/// Die Linien — `null`, solange die Ebene aus ist, der Zoom zu weit
/// draußen liegt oder es kein Gitter gibt.
///
/// **Warum das Gitter erst nach den billigen Prüfungen geholt wird:**
/// `elevationGridProvider` packt 13,6 MB aus. Wer die Ebene nie
/// einschaltet, soll das nie bezahlen.
final elevationContoursProvider =
    FutureProvider<ElevationContours?>((ref) async {
  if (!ref.watch(contourLayerEnabledProvider)) return null;
  final zoom = ref.watch(mapIdleZoomProvider);
  if (zoom == null || contourEquidistanceM(zoom) == null) return null;
  final window = ref.watch(contourWindowProvider);
  if (window == null) return null;
  final grid = await ref.watch(elevationGridProvider.future);
  if (grid == null) return null;
  return compute(_contours, (grid: grid, window: window, zoom: zoom));
});

ElevationContours? _contours(
        ({ElevationGrid grid, FillWindow window, double zoom}) input) =>
    contourLinesFor(input.grid, window: input.window, zoom: input.zoom);

/// Die Äquidistanz, die die Legende nennen soll — aus dem Ergebnis,
/// nicht aus der Zoomregel: Die Punktschranke kann vergröbert haben,
/// und die Legende muss sagen, was WIRKLICH auf der Karte liegt.
final contourEquidistanceProvider = Provider<int?>((ref) =>
    ref.watch(elevationContoursProvider).valueOrNull?.equidistanceM);

/// Die Linien als GeoJSON — nur für die MapLibre-Strecke.
///
/// Eigener Provider und eigener Isolate-Lauf: Bei 40 000 Punkten sind
/// das ein paar Hunderttausend Zeichen, und die gehören nicht auf den
/// UI-Thread. Genau dieselbe Trennung wie beim Wald zwischen Fläche und
/// `forestFillFileProvider`.
final contourGeoJsonProvider =
    FutureProvider<({String normal, String index, String key})?>((ref) async {
  final contours = await ref.watch(elevationContoursProvider.future);
  if (contours == null || contours.lines.isEmpty) return null;
  return compute(_geoJson, contours);
});

({String normal, String index, String key}) _geoJson(
        ElevationContours contours) =>
    (
      normal: contourGeoJson(contours.lines, index: false),
      index: contourGeoJson(contours.lines, index: true),
      key: contours.key,
    );
