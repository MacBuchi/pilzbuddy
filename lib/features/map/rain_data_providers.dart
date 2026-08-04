// Vom Release-Asset zur fertigen Höhenlinie.
//
// Zwei Provider mit klarer Arbeitsteilung: [rainGridProvider] holt die
// Zahlen (Netz, Platte, still degradierend), [rainContoursProvider]
// rechnet daraus die Linien. Getrennt, weil die Zahlen noch eine zweite
// Aufgabe haben — die Regensumme am Spot, die ohne Linien auskommt.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/rain_grid_repository.dart';
import 'rain_contours.dart';
import 'rain_fill.dart';
import 'rain_grid.dart';
import 'rain_layer.dart';
import 'rain_stack.dart';

final rainGridRepositoryProvider = Provider<RainGridRepository>(
    (ref) => RainGridRepository());

/// Wie ein Gitter beschafft wird. Dieselbe Test-Naht wie
/// `rainImageProviderFactory`: Ohne sie ginge jeder Flow-Test, der eine
/// Summenebene wählt, ins Netz — und `flutter test` ist netzfrei.
final rainGridLoaderProvider = Provider<Future<RainGrid?> Function(String)>(
    (ref) => ref.watch(rainGridRepositoryProvider).load);

/// Welche Ebenen ein eigenes Gitter haben. Radar hat keins: Der
/// 5-Minuten-Takt lässt sich nicht vorberechnen, und dort bleibt es beim
/// DWD-Bild in DWD-Farben — die Konvention, die jeder aus Wetter-Apps
/// kennt.
String? rainGridKeyFor(RainLayer layer) => switch (layer) {
      RainLayer.last24h => 'sf',
      RainLayer.last30d => 'w4',
      _ => null,
    };

/// Die Höhenstufen der Ebene.
List<int> rainLevelsFor(RainLayer layer) =>
    layer == RainLayer.last24h ? rainLevels24h : rainLevels30d;

/// Das rohe Wertegitter der aktiven Ebene — `null`, wenn es für sie
/// keines gibt oder nichts geladen werden konnte.
final rainGridProvider = FutureProvider.family<RainGrid?, RainLayer>(
  (ref, layer) async {
    final key = rainGridKeyFor(layer);
    if (key == null) return null;
    return ref.watch(rainGridLoaderProvider)(key);
  },
);

/// Die Höhenlinien der aktiven Ebene.
///
/// Gerechnet im Isolate: An echten Daten sind es 45 ms, und das ist
/// wenig — aber es ist Rechenzeit im Kartenpfad einer App, die schon
/// einmal an genau dieser Stelle in einen ANR gelaufen ist (#151).
/// Einmal beim Einschalten, nie je Kamerabewegung.
final rainContoursProvider =
    FutureProvider.family<List<ContourLine>, RainLayer>((ref, layer) async {
  final grid = await ref.watch(rainGridProvider(layer).future);
  if (grid == null) return const [];
  return compute(_contours, (grid: grid, levels: rainLevelsFor(layer)));
});

List<ContourLine> _contours(({RainGrid grid, List<int> levels}) input) =>
    rainContours(input.grid, levels: input.levels);

/// Die eingefärbte Fläche zwischen den Höhenlinien, als PNG — **samt
/// ihrer Ausdehnung**.
///
/// Die Grenzen kommen mit, weil sie NICHT die der DWD-Bildebene sind:
/// Das Gitter ist auf seine Zellen mit Daten beschnitten (w4:
/// 5,73–15,17°), die Bildebene deckt bewusst etwas mehr ab
/// (5,6–15,4°). Wer hier `RainLayer.bounds` einsetzt, verschiebt die
/// Fläche um rund zwanzig Kilometer gegen die Linien — sichtbar erst,
/// wenn man genau hinsieht, und dann falsch.
///
/// Im Isolate, wie die Linien: Es sind 550 000 Zellen, und das ist
/// Rechenzeit im Kartenpfad. Beide Provider hängen am selben Gitter,
/// geladen wird es also einmal und zweimal ausgewertet.
final rainFillProvider = FutureProvider.family<RainFill?, RainLayer>(
    (ref, layer) async {
  final grid = await ref.watch(rainGridProvider(layer).future);
  if (grid == null) return null;
  final png = await compute(_fill, (grid: grid, levels: rainLevelsFor(layer)));
  return RainFill(
    png: png,
    west: grid.west,
    east: grid.east,
    north: grid.north,
    south: grid.south,
    measured: grid.measured,
  );
});

/// Die Fläche und der Ausschnitt, auf den sie gehört.
class RainFill {
  const RainFill({
    required this.png,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.measured,
  });

  final Uint8List png;
  final double west;
  final double east;
  final double north;
  final double south;

  /// Der Messzeitpunkt des zugrunde liegenden Gitters — er unterscheidet
  /// zwei Flächen derselben Ebene und wird deshalb zum Dateinamen.
  final DateTime measured;
}

/// Dieselbe Fläche, aber als Datei auf Platte — der Weg für MapLibre,
/// dessen `image`-Quelle eine URL nimmt und keine Bytes.
///
/// Bewusst OHNE `family`: Die MapLibre-Ansicht hängt sich per `ref.listen`
/// daran, und ein Familienschlüssel, der beim Ebenenwechsel wechselt,
/// wäre dort ein zweiter Zuhörer statt eines geänderten Werts — die alte
/// Fläche bliebe auf der Karte liegen.
///
/// Auf dem Web-Pfad wird dieser Provider nie beobachtet; dort nimmt
/// flutter_map die Bytes direkt.
final rainFillFileProvider =
    FutureProvider<({String url, RainFill fill})?>((ref) async {
  final layer = ref.watch(rainLayerProvider);
  final key = rainGridKeyFor(layer);
  if (key == null) return null;
  final fill = await ref.watch(rainFillProvider(layer).future);
  if (fill == null) return null;
  final url = await ref
      .watch(rainGridRepositoryProvider)
      .writeFill(key, fill.measured, fill.png);
  return url == null ? null : (url: url, fill: fill);
});

Uint8List _fill(({RainGrid grid, List<int> levels}) input) =>
    rainFillPng(input.grid, levels: input.levels);

// ---------------------------------------------------------------------
// Der Tagesverlauf am Spot
// ---------------------------------------------------------------------

/// Wie der Tagesstapel beschafft wird. Dieselbe Test-Naht wie
/// [rainGridLoaderProvider] — ohne sie ginge jeder Flow-Test, der ein
/// Spot-Blatt öffnet, ins Netz.
final rainStackLoaderProvider =
    Provider<Future<RainStackData?> Function()>((ref) {
  final repository = ref.watch(rainGridRepositoryProvider);
  return () => repository.loadDailyStack();
});

/// Hat die Nutzerin dem Nachladen zugestimmt?
///
/// Aus den Einstellungen gelesen und dort auch geschrieben — die
/// Zustimmung überlebt den Neustart, sonst wäre sie eine Frage, die bei
/// jedem Spot neu käme.
final rainCourseEnabledProvider = StateProvider<bool>(
    (ref) => ref.watch(settingsProvider).rainCourseEnabled);

/// Der geladene Stapel — `null`, solange niemand zugestimmt hat.
final rainStackProvider = FutureProvider<RainStackData?>((ref) async {
  if (!ref.watch(rainCourseEnabledProvider)) return null;
  return ref.watch(rainStackLoaderProvider)();
});

/// Der Regenverlauf an einem Punkt.
///
/// Im Isolate: Es sind vierzehn Gitter auszupacken, und das ist
/// Rechenzeit in einem Blatt, das sich sofort öffnen soll. Der
/// Familienschlüssel ist der Punkt selbst, also wird je Spot einmal
/// gerechnet und danach aus dem Provider-Cache geliefert.
final rainCourseProvider =
    FutureProvider.family<RainCourse?, ({double lat, double lon})>(
        (ref, at) async {
  final stack = await ref.watch(rainStackProvider.future);
  if (stack == null) return null;
  return compute(_course, (stack: stack, lat: at.lat, lon: at.lon));
});

RainCourse _course(({RainStackData stack, double lat, double lon}) input) =>
    rainCourseFrom(
      input.stack.days,
      width: input.stack.info.width,
      height: input.stack.info.height,
      west: input.stack.info.west,
      east: input.stack.info.east,
      north: input.stack.info.north,
      south: input.stack.info.south,
      lat: input.lat,
      lon: input.lon,
    );

/// Die 30-Tage-Summe an einem Punkt, aus dem vorhandenen W4-Gitter.
///
/// Warum nicht aus dem Stapel: dreißig Tagesraster wären rund 1,5 MB,
/// und der DWD rechnet diese Summe ohnehin selbst. Warum überhaupt: Es
/// ist die Zahl der Forums-Faustregel (≥100 mm in 30 Tagen) und die
/// Größe, auf der der tschechische Wetterdienst seinen Pilzindex baut.
final rainMonthAtProvider =
    FutureProvider.family<int?, ({double lat, double lon})>((ref, at) async {
  if (!ref.watch(rainCourseEnabledProvider)) return null;
  final grid = await ref.watch(rainGridProvider(RainLayer.last30d).future);
  return grid?.mmAt(at.lat, at.lon);
});
