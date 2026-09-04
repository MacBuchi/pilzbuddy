import 'package:idb_shim/idb_shim.dart';

/// Ein IndexedDB-Zugang, bei dem grundsätzlich nichts geht — er steht für
/// den privaten Modus mancher Browser, einen vollen Speicher und einen
/// `file://`-Kontext.
///
/// Frei von `dart:io`, damit ihn auch die Tests benutzen können, die auf
/// dart2js laufen.
class BrokenIdbFactory implements IdbFactory {
  @override
  Future<Database> open(String dbName,
          {int? version,
          OnUpgradeNeededFunction? onUpgradeNeeded,
          OnBlockedFunction? onBlocked}) async =>
      throw StateError('kein IndexedDB');

  @override
  Future<IdbFactory> deleteDatabase(String name,
          {OnBlockedFunction? onBlocked}) async =>
      throw StateError('kein IndexedDB');

  @override
  int cmp(Object first, Object second) => 0;

  @override
  String get name => 'kaputt';

  @override
  bool get persistent => false;

  @override
  bool get supportsDatabaseNames => false;

  @override
  Future<List<String>> getDatabaseNames() async => const [];
}
