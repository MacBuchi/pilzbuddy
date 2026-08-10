// Die feine Waldstufe ohne Netz und ohne Platte (#253/#264).
//
// Warum ein Fake und nicht das echte Repository mit Temp-Verzeichnis:
// Echtes Datei-IO läuft in `testWidgets` an der Fake-Uhr vorbei — die
// Futures lösen sich erst mit echter Zeit auf, und `pump()` sieht davon
// nichts. Was auf der Platte landet, beweist deshalb
// `forest_block_repository_test.dart` gegen einen MockClient; hier geht
// es um das Zusammenspiel von Bildschirm, Notifier und Zustimmung.
import 'package:pilzbuddy/data/forest_block_repository.dart';
import 'package:pilzbuddy/features/map/forest_blocks.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';

/// Ein Katalog mit [blockCount] gleich großen Blöcken.
ForestBlockCatalog fakeForestCatalog({int blockCount = 4, int bytes = 1000}) {
  const lonStep = 0.004;
  const latStep = 0.003;
  return ForestBlockCatalog(
    referenceYear: 2024,
    hexLonStep: lonStep,
    hexLatStep: latStep,
    west: 10,
    north: 50,
    gridWidth: 2 * blockCount,
    gridHeight: 2,
    blocks: [
      for (var i = 0; i < blockCount; i++)
        ForestBlockInfo(
          file: 'forest_block_x${i * 2}_y0.bin.gz',
          width: 2,
          height: 2,
          west: 10 + i * 2 * lonStep,
          north: 50,
          east: 10 + (i * 2 + 2.5) * lonStep,
          south: 50 - 3 * latStep,
          bytes: bytes,
          sha256: 'sha-$i',
          hx0: i * 2,
          hy0: 0,
        ),
    ],
  );
}

class FakeForestBlockRepository implements ForestBlockRepository {
  FakeForestBlockRepository({
    ForestBlockCatalog? catalog,
    this.stepDelay = Duration.zero,
    this.failAt,
    this.catalogReachable = true,
  }) : catalog = catalog ?? fakeForestCatalog();

  final ForestBlockCatalog catalog;

  /// Wartezeit je Block — damit ein Test den laufenden Zustand
  /// (Fortschrittsbalken, Anhalten) überhaupt zu sehen bekommt.
  final Duration stepDelay;

  /// Ab diesem Block scheitert der Download (0 = gleich der erste).
  final int? failAt;

  /// false heißt: noch nie einen Katalog gesehen und gerade kein Netz.
  final bool catalogReachable;

  /// Dateinamen der Blöcke, die „auf dem Gerät liegen".
  final installed = <String>{};

  @override
  Future<ForestBlockCatalog?> loadCatalog() async =>
      catalogReachable ? catalog : null;

  @override
  Future<ForestGrid?> loadBlock(
          ForestBlockCatalog catalog, ForestBlockInfo info) async =>
      null;

  @override
  Future<ForestBlocksOnDisk> installedOf(ForestBlockCatalog catalog) async {
    final present = catalog.blocks.where((b) => installed.contains(b.file));
    return (
      blocks: present.length,
      bytes: present.fold<int>(0, (sum, b) => sum + b.bytes),
    );
  }

  @override
  Stream<double> downloadAll(ForestBlockCatalog catalog,
      {bool Function()? isCancelled}) async* {
    final cancelled = isCancelled ?? () => false;
    final total = catalog.blocks.fold<int>(0, (sum, b) => sum + b.bytes);
    var done = catalog.blocks
        .where((b) => installed.contains(b.file))
        .fold<int>(0, (sum, b) => sum + b.bytes);
    yield done / total;

    for (final (index, block) in catalog.blocks.indexed) {
      if (installed.contains(block.file)) continue;
      if (cancelled()) return;
      if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
      if (failAt != null && index >= failAt!) {
        throw ForestBlockDownloadFailed(block.file);
      }
      installed.add(block.file);
      done += block.bytes;
      yield done / total;
    }
  }

  @override
  Future<int> deleteBlocks() async {
    final freed = catalog.blocks
        .where((b) => installed.contains(b.file))
        .fold<int>(0, (sum, b) => sum + b.bytes);
    installed.clear();
    return freed;
  }
}
