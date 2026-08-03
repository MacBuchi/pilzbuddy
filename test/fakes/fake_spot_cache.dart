import 'package:pilzbuddy/data/spot_cache.dart';

/// Zwischenspeicher im Arbeitsspeicher. Ohne ihn liefe jeder Flow-Test in
/// eine `MissingPluginException`: `FileSpotCache` fragt `path_provider`
/// nach dem App-Verzeichnis, und diesen Kanal gibt es im Widget-Test
/// nicht.
class FakeSpotCache implements SpotCache {
  FakeSpotCache({this.uid, this.rows, this.savedAt});

  String? uid;
  List<Map<String, dynamic>>? rows;
  DateTime? savedAt;

  int writes = 0;
  bool cleared = false;

  @override
  Future<CachedSpotRows?> read({required String uid}) async {
    if (rows == null || savedAt == null || this.uid != uid) return null;
    return (rows: rows!, savedAt: savedAt!);
  }

  @override
  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
  }) async {
    writes++;
    this.uid = uid;
    this.rows = rows;
    this.savedAt = savedAt;
  }

  @override
  Future<void> clear() async {
    cleared = true;
    uid = null;
    rows = null;
    savedAt = null;
  }
}
