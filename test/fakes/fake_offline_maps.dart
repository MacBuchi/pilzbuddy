// In-Memory-Fake für die Offline-Karten: kein Netz, keine Dateien.
// Download "gelingt" sofort und registriert die Karte mit einem
// Fantasie-Pfad — der Offline-Style-Provider fällt dadurch in Tests
// bewusst auf die Online-Karte zurück (Datei existiert nicht).
import 'dart:io' show HttpException;

import 'package:pilzbuddy/features/offline_maps/offline_map_repository.dart';

class FakeOfflineMapRepository implements OfflineMapRepository {
  final available = <AvailableMap>[
    const AvailableMap(
      key: 'de_bayern',
      dateStamp: '20260320',
      sizeBytes: 1707 * 1024 * 1024,
      downloadUrl: 'https://example.invalid/de_bayern_20260320.pmtiles',
    ),
    const AvailableMap(
      key: 'de_berlin',
      dateStamp: '20260320',
      sizeBytes: 76 * 1024 * 1024,
      downloadUrl: 'https://example.invalid/de_berlin_20260320.pmtiles',
    ),
  ];

  final installed = <InstalledMap>[];

  @override
  Future<List<AvailableMap>> fetchAvailable() async => List.of(available);

  @override
  Future<List<InstalledMap>> listInstalled() async => List.of(installed);

  /// Simulierte Download-Dauer — lang genug, um in Tests währenddessen
  /// zu navigieren (Abbruch-Regression #38), kurz genug für settle().
  Duration stepDelay = const Duration(milliseconds: 150);

  /// So viele Download-Aufrufe schlagen fehl, bevor einer gelingt —
  /// simuliert schlechtes Netz für den geduldigen Download-Manager.
  int failuresBeforeSuccess = 0;
  int downloadCalls = 0;

  @override
  Stream<double> download(AvailableMap map,
      {bool Function()? isCancelled}) async* {
    downloadCalls++;
    yield 0.5;
    await Future<void>.delayed(stepDelay);
    if (isCancelled?.call() ?? false) throw const DownloadCancelled();
    if (downloadCalls <= failuresBeforeSuccess) {
      throw const HttpException('Verbindung abgerissen (Fake)');
    }
    installed.removeWhere((m) => m.key == map.key);
    installed.add(InstalledMap(
      key: map.key,
      dateStamp: map.dateStamp,
      sizeBytes: map.sizeBytes,
      filePath: '/fake/offline_maps/${map.key}_${map.dateStamp}.pmtiles',
    ));
    yield 1.0;
  }

  @override
  Future<void> delete(String key) async =>
      installed.removeWhere((m) => m.key == key);
}
