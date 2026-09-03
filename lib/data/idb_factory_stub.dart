import 'package:idb_shim/idb_shim.dart';

/// Alles außer dem Browser: IndexedDB gibt es hier nicht — und es fehlt
/// auch nichts, denn auf Android liegt der Zwischenspeicher als Datei.
IdbFactory? browserIdbFactory() => null;
