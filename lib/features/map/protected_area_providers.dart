// Laden der Schutzgebiete (#580) — Muster wie beim Waldgitter.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/map_worker.dart';

import 'asset_grid_loader.dart';
import 'map_worker_tasks.dart';
import 'protected_areas.dart';

/// Wie die Schutzgebiete beschafft werden — die Test-Naht:
/// `test/fakes/test_app.dart` überschreibt sie auf `null`, sonst läse
/// jeder Flow-Test das echte Asset.
final protectedAreasLoaderProvider =
    Provider<Future<ProtectedAreas?> Function()>((ref) {
  final worker = ref.watch(mapWorkerProvider);
  return () => _loadFromAssets(worker);
});

/// Lädt Manifest und Läufe aus den Assets, packt im Isolate aus.
///
/// `null` bei jedem Fehler — ohne Schutzgebiete malt die Fläche wie vor
/// 1.201.0 und der Hinweis beim Eintragen bleibt weg. Das ist die
/// harmlose Richtung NICHT: Ein fehlender Hinweis sieht aus wie „hier
/// ist keins". Deshalb prüft `test/protected_areas_asset_test.dart`, dass
/// das echte Asset lädt — ein kaputtes Asset ist ein Baufehler und soll
/// in CI auffallen, nicht im Wald.
Future<ProtectedAreas?> _loadFromAssets(MapWorker worker) async {
  try {
    return await loadAssetGrid(worker, protectedLoad,
        manifestPath: 'assets/protected/protected_manifest.json',
        gridPath: 'assets/protected/protected_grid.bin.gz',
        slot: 'protected');
  } catch (_) {
    // Fehlendes/kaputtes Asset ⇒ keine Schutzgebiete. Begründung oben.
    return null;
  }
}

/// Die geladenen Schutzgebiete — einmal je App-Lauf.
///
/// **Beobachten ist laden**: Wer das beobachtet, packt 0,6 MB Läufe und
/// 0,6 MB Namen aus. Die Fläche tut es nur, wenn Wald oder Ampel
/// ohnehin malen; der Hinweis nur im offenen Eintrage-Blatt.
final protectedAreasProvider = FutureProvider<ProtectedAreas?>(
    (ref) => ref.watch(protectedAreasLoaderProvider)());
