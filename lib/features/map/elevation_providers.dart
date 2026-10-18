// Das Höhengitter auf dem Gerät — Asset im APK, kein Download, keine
// Zustimmung, exakt das Muster von `forest_species_providers.dart`:
// Die Temperaturkorrektur soll dort funktionieren, wo kein Empfang ist.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/map_worker.dart';

import 'asset_grid_loader.dart';
import 'elevation_grid.dart';
import 'map_worker_tasks.dart';

/// Wie das Gitter beschafft wird — die Test-Naht:
/// `test/fakes/test_app.dart` überschreibt sie auf `null`, sonst läse
/// jeder Flow-Test das echte Asset.
final elevationLoaderProvider =
    Provider<Future<ElevationGrid?> Function()>((ref) {
  final worker = ref.watch(mapWorkerProvider);
  return () => _loadFromAssets(worker);
});

/// Lädt Manifest + Gitter aus den Assets, packt im Isolate aus.
///
/// `null` bei jedem Fehler — stille Degradation wie überall auf der
/// Karte: Ohne Höhengitter rechnet die Temperatur wie bisher
/// unkorrigiert weiter, und die Stationshöhe steht ja daneben.
Future<ElevationGrid?> _loadFromAssets(MapWorker worker) async {
  try {
    return await loadAssetGrid(worker, elevationLoad,
        manifestPath: 'assets/elevation/elevation_manifest.json',
        gridPath: 'assets/elevation/elevation.bin.gz',
        slot: 'elevation');
  } catch (_) {
    // Fehlendes/kaputtes Asset ⇒ keine Korrektur. Begründung oben.
    return null;
  }
}

/// Das geladene Gitter — einmal je App-Lauf, danach aus dem Cache.
final elevationGridProvider =
    FutureProvider<ElevationGrid?>((ref) => ref.watch(elevationLoaderProvider)());

/// Die Wabenhöhe an einem Punkt — die Form, in der Blatt und Ampel sie
/// brauchen. `null`: keine Korrektur möglich (kein Gitter, außerhalb).
final elevationAtProvider =
    FutureProvider.family<int?, ({double lat, double lon})>((ref, at) async {
  final grid = await ref.watch(elevationGridProvider.future);
  return grid?.heightMetersAt(at.lat, at.lon);
});
