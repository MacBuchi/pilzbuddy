// Bereiche auf der Karte zeichnen und radieren (#630, Stufe 2b;
// übernommen aus TrailBuddy, dort „Stufe C"). Pur bis auf die Provider
// am Ende: aus einem Fingerstrich die Kacheln bei [kAreaShapeZoom], und
// der Entwurf, der Striche zum gespeicherten Bestand addiert oder davon
// abzieht, bis er gespeichert wird.
//
// **Ein Strich ist eine Fläche.** Er wird geschlossen (Ende zum Anfang),
// und dazu gehört jede Kachel, die der Rand berührt oder die innen liegt.
// Ein offener Zickzack ergibt damit eine dünne Fläche — seine Kacheln
// sind die, über die er läuft. Das ist dieselbe Regel für beides, und sie
// macht den Radierer zu einem Werkzeug, das genau wegnimmt, worüber man
// gewischt hat.
//
// **Der Entwurf bearbeitet den ganzen Bestand**, nicht einen neuen
// Bereich: „Dazu" nimmt nur, was noch nicht liegt, „Weg" nur, was liegt.
// Gespeichert wird beides in einem Schritt — erst das Herausschreiben
// (ohne Netz, area_trim.dart), dann der Download des Neuen.
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_view/marker_culling.dart' show MapViewBounds;
import '../map/rain_grid.dart' show latFromMercatorY, mercatorY;
import 'area_plan.dart';
import 'area_providers.dart' show storedAreasProvider;

/// Web-Mercator endet hier; ein Strich darüber hinaus wird gekappt.
const _kMercatorMaxLat = 85.05112878;

/// Größer als so viele Kacheln (Rahmen des Strichs, bei Zoom 13) wird
/// ein Strich nicht ausgewertet: ein Kreis um halb Europa ist ein
/// Versehen, und ihn Kachel für Kachel zu prüfen hielte die Oberfläche
/// an. Weit über [kAreaMaxTiles], damit das Abziehen aus einem großen
/// Entwurf nicht daran scheitert.
const kAreaDrawMaxSpanTiles = 250000;

/// Wie viele Schritte ein Entwurf zurücknehmen kann.
const kAreaDraftHistory = 20;

double _tileX(double lon, int n) => (lon + 180) / 360 * n;

double _tileY(double lat, int n) {
  final r = lat.clamp(-_kMercatorMaxLat, _kMercatorMaxLat) * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
}

/// Die Kacheln bei [zoom] (Schlüssel wie [TileSetShape.keyOf]), die die
/// geschlossene Fläche [ring] berührt oder umschließt. Null, wenn der
/// Rahmen des Strichs mehr als [maxSpanTiles] Kacheln umfasst — leer bei
/// weniger als zwei Punkten.
Set<int>? tilesTouchedByRing(List<LatLng> ring,
    {int zoom = kAreaShapeZoom, int maxSpanTiles = kAreaDrawMaxSpanTiles}) {
  if (ring.length < 2) return <int>{};
  final n = 1 << zoom;
  final pts = [
    for (final p in ring) (x: _tileX(p.longitude, n), y: _tileY(p.latitude, n))
  ];
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final span =
      (maxX.floor() - minX.floor() + 1) * (maxY.floor() - minY.floor() + 1);
  if (span > maxSpanTiles) return null;

  final keys = <int>{};
  void add(int x, int y) {
    if (x < 0 || y < 0 || x >= n || y >= n) return;
    keys.add(TileSetShape.keyOf(x, y, zoom));
  }

  // Der Rand: jede Kante in Schritten von höchstens einer Zehntelkachel
  // abgetastet. Eine Ecke, die eine Kachel um weniger streift, fehlt —
  // die harmlose Richtung.
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    final len = math.max((b.x - a.x).abs(), (b.y - a.y).abs());
    final steps = math.max(1, (len / 0.1).ceil());
    for (var k = 0; k <= steps; k++) {
      final f = k / steps;
      add((a.x + (b.x - a.x) * f).floor(), (a.y + (b.y - a.y) * f).floor());
    }
  }

  // Das Innere: je Kachelzeile die Schnittpunkte der Mittellinie mit den
  // Kanten (gerade-ungerade), dazwischen jede Kachel, deren Mitte innen
  // liegt. Was innen UND am Rand liegt, hat die Abtastung schon.
  for (var row = minY.floor(); row <= maxY.floor(); row++) {
    final yc = row + 0.5;
    final xs = <double>[];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      if ((a.y <= yc) != (b.y <= yc)) {
        xs.add(a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y));
      }
    }
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i += 2) {
      for (var col = (xs[i] - 0.5).ceil();
          col <= (xs[i + 1] - 0.5).floor();
          col++) {
        add(col, row);
      }
    }
  }
  return keys;
}

/// Ein Bildschirmpunkt der Karte als Koordinate — aus dem Sichtfenster
/// des letzten Stillstands und der Größe der Kartenfläche. Beide Engines
/// spannen das Bild linear in Web-Mercator auf (ohne Drehung — die ist in
/// PilzBuddy aus), also ist das die Umkehrung ihrer Projektion.
///
/// **Das gilt nur, solange die Karte steht**, und genau dafür liegt die
/// Zeichenfläche: Sie fängt jede Berührung ab, die Karte darunter kann
/// sich währenddessen nicht bewegen.
LatLng unprojectFromBounds(MapViewBounds bounds, Size size, Offset p) {
  final lon = bounds.west + p.dx / size.width * (bounds.east - bounds.west);
  final top = mercatorY(bounds.north);
  final bottom = mercatorY(bounds.south);
  final lat = latFromMercatorY(top + p.dy / size.height * (bottom - top));
  return LatLng(lat, lon);
}

/// Wie ein Strich wirkt: dazu oder weg.
enum AreaDrawTool { add, remove }

/// Der Entwurf: was zum gespeicherten Bestand DAZUKOMMT und was davon
/// WEGFÄLLT. Beides als Kacheln bei [kAreaShapeZoom]; [adds] enthält nie
/// eine gespeicherte, [removes] nur gespeicherte Kacheln — dafür sorgt der
/// Notifier.
@immutable
class AreaDraft {
  AreaDraft(
      {Set<int> adds = const {},
      Set<int> removes = const {},
      this.history = const [],
      this.tool})
      : adds = Set.unmodifiable(adds),
        removes = Set.unmodifiable(removes);

  final Set<int> adds;
  final Set<int> removes;
  final List<({Set<int> adds, Set<int> removes})> history;

  /// Das Werkzeug für den NÄCHSTEN Strich — null heißt: die Karte lässt
  /// sich verschieben.
  final AreaDrawTool? tool;

  /// Was geladen wird — geht so in den Plan.
  TileSetShape get addShape => TileSetShape(zoom: kAreaShapeZoom, keys: adds);

  bool get isEmpty => adds.isEmpty && removes.isEmpty;

  AreaDraft _with({AreaDrawTool? tool, bool clearTool = false}) => AreaDraft(
        adds: adds,
        removes: removes,
        history: history,
        tool: clearTool ? null : (tool ?? this.tool),
      );

  static bool _same(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  /// Ein neuer Stand; der alte wandert in die Geschichte. Ohne Änderung
  /// kein Schritt — „Rückgängig" soll immer etwas tun.
  AreaDraft _step(Set<int> nextAdds, Set<int> nextRemoves) {
    if (_same(nextAdds, adds) && _same(nextRemoves, removes)) {
      return _with(clearTool: true);
    }
    final h = [...history, (adds: adds, removes: removes)];
    return AreaDraft(
      adds: nextAdds,
      removes: nextRemoves,
      history: h.length > kAreaDraftHistory
          ? h.sublist(h.length - kAreaDraftHistory)
          : h,
    );
  }
}

/// Der gespeicherte Bestand als Kacheln bei [kAreaShapeZoom] — gegen ihn
/// rechnet der Entwurf („kommt dazu" nur, was nicht schon liegt).
final storedTileKeysProvider = Provider<Set<int>>((ref) {
  final areas = ref.watch(storedAreasProvider).valueOrNull ?? const [];
  return {for (final a in areas) ...a.shape.keysAt(kAreaShapeZoom)};
});

/// Ist die Werkzeugleiste offen? Nur solange zeigt die Karte Maske und
/// Entwurf, und nur solange lebt der Entwurf.
final areaToolsOpenProvider = StateProvider<bool>((ref) => false);

/// Der Entwurf — null heißt leer. Er lebt, solange die Werkzeugleiste
/// offen ist; beim Schließen wird er verworfen (mit Rückfrage, wenn etwas
/// darin steht — area_tool_rail.dart).
class AreaDraftNotifier extends Notifier<AreaDraft?> {
  @override
  AreaDraft? build() => null;

  AreaDraft get _draft => state ?? AreaDraft();

  /// Steht etwas im Entwurf, das noch nicht gespeichert ist?
  bool get hasChanges => !(state?.isEmpty ?? true);

  void start() => state ??= AreaDraft();

  /// Das Werkzeug für den NÄCHSTEN Strich; derselbe Knopf noch einmal
  /// nimmt es zurück. Nach dem Strich ist es wieder weg — die Karte lässt
  /// sich zwischen zwei Strichen verschieben, ohne umzuschalten.
  void arm(AreaDrawTool tool) {
    final d = _draft;
    state = d.tool == tool ? d._with(clearTool: true) : d._with(tool: tool);
  }

  void disarm() {
    final d = state;
    if (d != null && d.tool != null) state = d._with(clearTool: true);
  }

  /// Ein Strich: seine Kacheln dazu oder weg, je nach Werkzeug.
  void applyStroke(Set<int> stroke) {
    final d = state;
    if (d == null || d.tool == null) return;
    d.tool == AreaDrawTool.add ? addAll(stroke) : removeAll(stroke);
  }

  /// Dazu: was nicht schon liegt, kommt dazu; was wegfallen sollte, bleibt.
  void addAll(Set<int> keys) {
    final d = _draft;
    final stored = ref.read(storedTileKeysProvider);
    state = d._step(
      {...d.adds, ...keys.where((k) => !stored.contains(k))},
      {...d.removes}..removeAll(keys),
    );
  }

  /// Weg: was dazukommen sollte, kommt nicht; was liegt, fällt weg.
  void removeAll(Set<int> keys) {
    final d = _draft;
    final stored = ref.read(storedTileKeysProvider);
    state = d._step(
      {...d.adds}..removeAll(keys),
      {...d.removes, ...keys.where(stored.contains)},
    );
  }

  void undo() {
    final d = state;
    if (d == null || d.history.isEmpty) return;
    final last = d.history.last;
    state = AreaDraft(
        adds: last.adds,
        removes: last.removes,
        history: d.history.sublist(0, d.history.length - 1));
  }

  void discard() => state = null;

  /// Nach dem Speichern: ein leerer Entwurf, die Leiste bleibt offen.
  void clear() => state = AreaDraft();

  /// Das Entfernen ist gespeichert, das Laden nicht: Nur „kommt dazu"
  /// bleibt offen (Rückgängig kann nicht hinter Gespeichertes zurück).
  void dropRemoves() {
    final d = state;
    if (d == null) return;
    state = AreaDraft(adds: d.adds);
  }
}

final areaDraftProvider =
    NotifierProvider<AreaDraftNotifier, AreaDraft?>(AreaDraftNotifier.new);

/// Die Kacheln bei [zoom], die [bounds] berühren — der „Ausschnitt" als
/// Strich. Null über [maxSpanTiles] (weit draußen wäre das halb
/// Mitteleuropa bei Zoom 13).
Set<int>? tilesInBounds(AreaBounds bounds,
    {int zoom = kAreaShapeZoom, int maxSpanTiles = kAreaDrawMaxSpanTiles}) {
  if (countTilesCovering(bounds, minZoom: zoom, maxZoom: zoom) >
      maxSpanTiles) {
    return null;
  }
  return {
    for (final t in tilesCovering(bounds, minZoom: zoom, maxZoom: zoom))
      TileSetShape.keyOf(t.x, t.y, zoom),
  };
}
