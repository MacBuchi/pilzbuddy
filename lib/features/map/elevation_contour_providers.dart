// Die Provider der Höhenlinien-Ebene: Schalter, Bodenauflösung,
// Fenster mit Gedächtnis, und der Isolate-Lauf.
//
// Aufgeteilt wie beim Wald (`forest_data_providers.dart`): Die Rechnung
// steht flutter-frei in `elevation_contours.dart`, hier steht nur, WANN
// sie läuft.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bounded_compute.dart';
import '../../core/map_worker.dart';
import '../../core/settings.dart';

import 'contours.dart' show ContourLine;
import 'elevation_contours.dart';
import 'elevation_providers.dart';
import 'map_overlays.dart';
import 'map_worker_tasks.dart' show contoursTask;
import 'forest_data_providers.dart' show mapIdleBoundsProvider;
import 'forest_fill_window.dart';

/// Ist die Ebene an? Gemerkt wie `forestLayerEnabledProvider` und aus
/// demselben Grund — Begründung bei [Settings.forestLayerEnabled].
///
/// Von allen vier Ebenen ist diese die billigste zum Merken: Sie lädt
/// nichts nach, sie rechnet nur, und das erst bei Kamera-Stillstand.
final contourLayerEnabledProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.contourLayerEnabled,
    write: (s, v) => s.setContourLayerEnabled(v),
    label: 'Höhenlinien merken',
  ),
);

/// Meter Gelände je logischem Bildschirmpixel beim letzten
/// Kamera-Stillstand — Geschwister von `mapIdleCenterProvider` (#235)
/// und [mapIdleBoundsProvider] (#249).
///
/// **Bewusst keine Zoomstufe.** Bis 1.98.0 stand hier eine, und sie war
/// zweideutig: MapLibre zählt in 512er-Kacheln, flutter_map in 256ern,
/// dieselbe Zahl heißt auf Android und Web also ein Faktor zwei im
/// Maßstab. Die Höhenlinien-Regeln rechneten in der 256er-Zählung und
/// lagen auf Android damit durchweg eine Stufe daneben (am 2026-08-21
/// nachgemessen: Karte auf 12,0, Regel rechnete mit 11).
///
/// Meter je Pixel kennt diese Zweideutigkeit nicht. Gerechnet wird der
/// Wert dort, wo beide Zutaten liegen — Sichtfenster und Breite des
/// Kartenfensters —, also im Karten-Screen.
final mapIdleGroundResolutionProvider = StateProvider<double?>((ref) => null);

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

/// Die Linien — `null`, solange die Ebene aus ist, ein Pixel mehr
/// Boden abdeckt als eine Wabe breit ist, oder es kein Gitter gibt.
///
/// **Warum das Gitter erst nach den billigen Prüfungen geholt wird:**
/// `elevationGridProvider` packt 13,6 MB aus. Wer die Ebene nie
/// einschaltet, soll das nie bezahlen.
final elevationContoursProvider =
    FutureProvider<ElevationContours?>((ref) async {
  if (!ref.watch(contourLayerEnabledProvider)) return null;
  // Wie beim Wald: Vorhang zu heißt gar nicht erst rechnen (#464).
  // `contourLabelsProvider` und `contourGeoJsonProvider` hängen an
  // diesem Provider und folgen deshalb ohne eigene Abfrage.
  if (ref.watch(mapOverlaysHiddenProvider)) return null;
  final metersPerPixel = ref.watch(mapIdleGroundResolutionProvider);
  if (metersPerPixel == null ||
      metersPerPixel > contourMaxMetersPerPixel) {
    return null;
  }
  final window = ref.watch(contourWindowProvider);
  if (window == null) return null;
  final grid = await ref.watch(elevationGridProvider.future);
  if (grid == null) return null;
  // Im Zeichen-Isolate (#641): Das Höhengitter (13,6 MB) liegt dort im
  // selben Fach wie für das Leuchten der Ampel — einmal hinüber für beide.
  return runOnMapWorker(ref, 'contours', contoursTask,
      (window: window, metersPerPixel: metersPerPixel),
      slots: {'elevation': grid});
});

/// „Erst näher dran" — die Ebene ist an, aber es liegt nichts auf der
/// Karte, weil der Maßstab zu grob für dieses Gelände ist.
///
/// **Steht hier und nicht in der Oberfläche**, weil die Antwort seit
/// 1.99.0 nicht mehr aus einer Zahl folgt: Ob 200 m Äquidistanz noch
/// zwei Linien oder schon eine Schraffur ergeben, hängt am Gefälle im
/// Fenster. Nur der Lauf selbst weiß es. Legende und Blatt sollen
/// dieselbe Antwort geben, also fragen beide hier.
///
/// Bewusst NICHT wahr, solange gerechnet wird: „erst näher dran" wäre
/// dann eine Behauptung über ein Ergebnis, das es noch nicht gibt.
final contourTooFarOutProvider = Provider<bool>((ref) {
  if (!ref.watch(contourLayerEnabledProvider)) return false;
  if (ref.watch(mapIdleGroundResolutionProvider) == null) return false;
  final contours = ref.watch(elevationContoursProvider);
  return contours.hasValue && contours.valueOrNull == null;
});

/// Die Äquidistanz, die die Legende nennen soll — aus dem Ergebnis,
/// nicht aus der Zoomregel: Die Punktschranke kann vergröbert haben,
/// und die Legende muss sagen, was WIRKLICH auf der Karte liegt.
final contourEquidistanceProvider = Provider<int?>((ref) =>
    ref.watch(elevationContoursProvider).valueOrNull?.equidistanceM);

/// Die Zahlen an den Hauptlinien — nur für die flutter_map-Strecke.
///
/// MapLibre setzt sie selbst (`symbol-placement: line`), der
/// Canvas-Renderer kann das nicht; dort ist eine Zahl ein Marker mit
/// einem Winkel. Auf dem Haupt-Thread und ohne Isolate: Es sind ein
/// paar Dutzend Punkte, und der Sprung in ein Isolate kostete mehr als
/// die Rechnung.
final contourLabelsProvider = Provider<List<ContourLabel>>((ref) {
  final contours = ref.watch(elevationContoursProvider).valueOrNull;
  final metersPerPixel = ref.watch(mapIdleGroundResolutionProvider);
  if (contours == null || metersPerPixel == null) return const [];
  return contourLabels(contours.lines, metersPerPixel: metersPerPixel);
});

/// Die Linien als GeoJSON — nur für die MapLibre-Strecke.
///
/// Gerechnet im selben Auftrag wie die Linien ([contoursTask], #689 B2):
/// Bei 40 000 Punkten sind das ein paar Hunderttausend Zeichen, und die
/// gehören nicht auf den UI-Thread. Ein eigener Auftrag schickte die
/// Linien dafür zurück in den Worker — im Browser kodiert, auf dem
/// Hauptthread. Fehlt das GeoJSON (Linien von woanders), rechnet ein
/// einzelnes `boundedCompute` es nach.
final contourGeoJsonProvider =
    FutureProvider<({String normal, String index, String key})?>((ref) async {
  final contours = await ref.watch(elevationContoursProvider.future);
  if (contours == null || contours.lines.isEmpty) return null;
  final ({String normal, String index}) geoJson =
      contours.geoJson ?? await boundedCompute(_geoJson, contours.lines);
  return (normal: geoJson.normal, index: geoJson.index, key: contours.key);
});

({String normal, String index}) _geoJson(List<ContourLine> lines) => (
      normal: contourGeoJson(lines, index: false),
      index: contourGeoJson(lines, index: true),
    );
