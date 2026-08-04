// Vom Release-Asset zur fertigen Höhenlinie.
//
// Zwei Provider mit klarer Arbeitsteilung: [rainGridProvider] holt die
// Zahlen (Netz, Platte, still degradierend), [rainContoursProvider]
// rechnet daraus die Linien. Getrennt, weil die Zahlen noch eine zweite
// Aufgabe haben — die Regensumme am Spot, die ohne Linien auskommt.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/rain_grid_repository.dart';
import 'rain_contours.dart';
import 'rain_grid.dart';
import 'rain_layer.dart';

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
