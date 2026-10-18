// Was auf dem Gerät liegt und was der Entwurf ändert — als EIN Bild über
// der Karte, solange die Werkzeugleiste der Kartenbereiche offen ist
// (#630, Stufe 2b).
//
// **Warum ein Bild und keine Polygone:** TrailBuddy zeichnet Maske,
// Schraffur und gestrichelte Ränder als Polygone und Linien seiner
// Kartenfassade. PilzBuddys Fassade kann keine Polygone, und beide
// Engines darum zu erweitern wäre die größere Baustelle als der Rest
// dieser Stufe. Ein Bild über den bewährten Weg der Wald- und
// Fundorte-Fläche (Isolate, `overlayPng`, in MapLibre `writeFill` +
// `applyImageFill`) können beide schon — und es liegt in Kartenkoordinaten,
// wandert also beim Verschieben mit.
//
// Die Regel aus TrailBuddy („Design Turn 2") bleibt: **Helligkeit = was
// auf dem Gerät liegt, Schraffur = offene Änderung.** Was nicht liegt,
// ist abgedunkelt; „kommt dazu" trägt helle Striche `/` auf dem Dunkel,
// „fällt weg" dunkle Striche `\` auf dem Hellen, beide mit einem Rand
// in derselben Tinte. Keine neue Farbe: Grün heißt auf dieser Karte Wald
// und Hauptaktion, Rot gibt es nicht.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/map_worker.dart';
import '../map/forest_data_providers.dart' show mapIdleBoundsProvider;
import '../map/forest_fill_window.dart';
import '../map/rain_data_providers.dart' show rainGridRepositoryProvider;
import 'area_draw.dart';
import 'area_edit_png.dart';

export 'area_edit_png.dart';

/// Der Bildausschnitt — Gedächtnis wie bei den anderen Flächen, geplant
/// über der ganzen Welt (Bereiche gibt es überall, wo der Host Kacheln
/// hat). Ohne offene Leiste null: dann rechnet hier nichts.
class AreaEditWindowNotifier extends Notifier<FillWindow?> {
  FillWindow? _last;

  @override
  FillWindow? build() {
    if (!ref.watch(areaToolsOpenProvider)) return _last = null;
    final bounds = ref.watch(mapIdleBoundsProvider);
    if (bounds == null) return _last;
    _last = planFillWindow(
          previous: _last,
          viewport: bounds,
          gridWest: -180,
          gridEast: 180,
          gridNorth: 85,
          gridSouth: -85,
        ) ??
        _last;
    return _last;
  }
}

final areaEditWindowProvider =
    NotifierProvider<AreaEditWindowNotifier, FillWindow?>(
        AreaEditWindowNotifier.new);

class AreaEditFill {
  const AreaEditFill({
    required this.png,
    required this.window,
    required this.revision,
  });

  final Uint8List png;
  final FillWindow window;

  /// Wechselt mit jedem Inhalt — gehört in den Dateinamen, weil die
  /// MapLibre-Strecke auf der URL idempotent ist.
  final String revision;

  double get west => window.west;
  double get east => window.east;
  double get north => window.north;
  double get south => window.south;
}

/// Das gemalte Bild — nur bei offener Leiste. Während der Neurechnung
/// behält `valueOrNull` den alten Stand.
final areaEditFillProvider = FutureProvider<AreaEditFill?>((ref) async {
  if (!ref.watch(areaToolsOpenProvider)) return null;
  final window = ref.watch(areaEditWindowProvider);
  if (window == null) return null;
  final stored = ref.watch(storedTileKeysProvider);
  final draft = ref.watch(areaDraftProvider);
  final adds = draft?.adds ?? const <int>{};
  final removes = draft?.removes ?? const <int>{};
  // Im Zeichen-Isolate (#641). Der Bestand ändert sich selten und liegt
  // dort als Fach; der Entwurf ist klein und reist mit.
  final png = await runOnMapWorker(ref, 'areaEdit', _paint,
      (window: window, adds: adds, removes: removes),
      slots: {'areaStored': stored});
  final revision = [
    stored.length,
    Object.hashAllUnordered(stored),
    adds.length,
    Object.hashAllUnordered(adds),
    removes.length,
    Object.hashAllUnordered(removes),
  ].map((v) => (v & 0x7fffffff).toRadixString(36)).join('-');
  return AreaEditFill(png: png, window: window, revision: revision);
});

Uint8List _paint(MapWorkerSlots slots,
        ({FillWindow window, Set<int> adds, Set<int> removes}) i) =>
    areaEditFillPng(
        window: i.window,
        stored: slots.get<Set<int>>('areaStored'),
        adds: i.adds,
        removes: i.removes);

/// Dasselbe Bild als Datei — der Weg für MapLibre.
final areaEditFillFileProvider =
    FutureProvider<({String url, AreaEditFill fill})?>((ref) async {
  final fill = await ref.watch(areaEditFillProvider.future);
  if (fill == null) return null;
  final url = await ref.watch(rainGridRepositoryProvider).writeFill(
      'bereiche', DateTime.utc(2026, 1, 1), fill.png,
      variant: '${fill.window.key}_${fill.revision}');
  return url == null ? null : (url: url, fill: fill);
});
