import 'package:pilzbuddy/data/spot_cache.dart';

/// Zwischenspeicher im Arbeitsspeicher. Ohne ihn liefe jeder Flow-Test in
/// eine `MissingPluginException`: `FileSpotCache` fragt `path_provider`
/// nach dem App-Verzeichnis, und diesen Kanal gibt es im Widget-Test
/// nicht.
///
/// [uid]/[rows]/[savedAt]/[writes] sind das Fach der EIGENEN Spots (wie
/// vor 1.217.0); die Buddy-Spots liegen daneben in [friends].
class FakeSpotCache implements SpotCache {
  FakeSpotCache({this.uid, this.rows, this.savedAt, this.friends});

  String? uid;
  List<Map<String, dynamic>>? rows;
  DateTime? savedAt;

  /// Das Fach der Buddy-Spots.
  ({String uid, List<Map<String, dynamic>> rows, DateTime savedAt})? friends;

  int writes = 0;
  bool cleared = false;

  @override
  Future<CachedSpotRows?> read(
      {required String uid, SpotCacheSlot slot = SpotCacheSlot.mine}) async {
    if (slot == SpotCacheSlot.friends) {
      final f = friends;
      if (f == null || f.uid != uid) return null;
      return (rows: f.rows, savedAt: f.savedAt);
    }
    if (rows == null || savedAt == null || this.uid != uid) return null;
    return (rows: rows!, savedAt: savedAt!);
  }

  @override
  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
    SpotCacheSlot slot = SpotCacheSlot.mine,
  }) async {
    if (slot == SpotCacheSlot.friends) {
      friends = (uid: uid, rows: rows, savedAt: savedAt);
      return;
    }
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
    friends = null;
  }
}
