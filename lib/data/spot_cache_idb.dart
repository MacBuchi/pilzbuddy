// Der Zwischenspeicher der eigenen Spots im Browser (#385).
//
// Dieselbe Aufgabe wie `FileSpotCache`, nur ohne Dateisystem: Bricht im
// geöffneten Tab die Verbindung ab, soll die Spot-Liste nicht leer
// werden. Bis 1.114.5 stand dort `NoSpotCache` — `path_provider` hat im
// Browser kein App-Verzeichnis, und damit gab es überhaupt keine Ablage.
//
// Warum IndexedDB und nicht `localStorage`: Dort liegen schon die
// Sitzungs-Token, der Platz ist knapp (übliche 5 MB je Origin) und jeder
// Zugriff hält den Haupt-Thread an. IndexedDB ist asynchron, deutlich
// größer bemessen — und es ist der Speicher, den `navigator.storage
// .persist()` in Stufe 3 (#386) gegen das Aufräumen des Browsers
// abzusichern versucht.
//
// Was hier NICHT gilt und auf Android gilt: Ein Browser darf seinen
// Speicher ohne Vorwarnung räumen. Für eine KOPIE ist das verkraftbar —
// der nächste erfolgreiche Abruf füllt sie wieder. Für das Original
// (Ausgangskorb) wäre es das nicht, und genau deshalb ist das eine
// eigene Stufe.
import 'package:idb_shim/idb_shim.dart';

import 'spot_cache.dart';

/// Welcher Zwischenspeicher zu dieser Plattform gehört.
///
/// Als Funktion und nicht als `if (kIsWeb)` im Provider, damit die
/// Entscheidung prüfbar ist: `kIsWeb` ist eine Konstante und unter
/// `flutter test` immer falsch — dieselbe Naht wie bei
/// `webChannelProvider` und `offlineMapsSupportedProvider`.
SpotCache chooseSpotCache({required bool web, required IdbFactory? idb}) {
  if (!web) return FileSpotCache();
  // Kein IndexedDB (privater Modus, `file://`): dann eben keiner.
  if (idb == null) return const NoSpotCache();
  return IndexedDbSpotCache(idb);
}

/// Der Zwischenspeicher in IndexedDB (Browser).
///
/// Wie die Schnittstelle es verlangt: **wirft nie**. Jeder Fehlschlag
/// endet als „kein Zwischenspeicher", nicht als Ausnahme — ein
/// erfolgreicher Abruf darf niemals daran scheitern, dass sich die Kopie
/// nicht ablegen lässt.
class IndexedDbSpotCache implements SpotCache {
  IndexedDbSpotCache(this._factory);

  final IdbFactory _factory;

  /// Eine Datenbank für die ganze App, ein Speicher je Zweck. Stufe 3
  /// (#386) legt hier `outbox` daneben und erhöht dafür [dbVersion] —
  /// [_upgrade] legt an, was fehlt, und lässt Vorhandenes in Ruhe.
  static const dbName = 'pilzbuddy';
  static const dbVersion = 1;
  static const storeName = 'spot_cache';

  /// Ein fester Schlüssel, das Konto steht IM Eintrag — genau wie in der
  /// Datei auf Android. Nach der Nutzer-id zu schlüsseln wäre verlockend,
  /// hinterließe aber die Spots jedes früher angemeldeten Kontos im
  /// Browser liegen; so überschreibt der nächste Abruf sie.
  static const _key = 'my_spots';

  Database? _db;

  Future<Database> _open() async {
    final open = _db;
    if (open != null) return open;
    final db = await _factory.open(dbName,
        version: dbVersion, onUpgradeNeeded: _upgrade);
    try {
      // Ein zweiter Tab, der auf eine neue Version hebt, bleibt sonst
      // hängen, solange diese Verbindung offen ist — und zwar stumm.
      // Hier aufzugeben ist billig: Der nächste Zugriff öffnet neu.
      db.onVersionChange.listen((_) {
        _db = null;
        db.close();
      });
    } catch (_) {
      // Eigener Fang, und der Grund ist gemessen: Die Speicher-Fassung
      // von idb_shim (die im Test läuft) wirft hier „not implemented
      // yet". Ohne diesen Fang wäre JEDER Zugriff still gescheitert —
      // und weil die Schnittstelle nie werfen darf, hätte niemand es
      // gemerkt. Die Absicherung ist ein Zusatz, keine Bedingung.
    }
    return _db = db;
  }

  static void _upgrade(VersionChangeEvent event) {
    final db = event.database;
    if (!db.objectStoreNames.contains(storeName)) {
      db.createObjectStore(storeName);
    }
  }

  @override
  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
  }) async {
    try {
      final db = await _open();
      final txn = db.transaction(storeName, idbModeReadWrite);
      await txn
          .objectStore(storeName)
          .put(encodeSpotCache(uid: uid, rows: rows, savedAt: savedAt), _key);
      await txn.completed;
    } catch (_) {
      // Kein Platz, gesperrter Speicher, privater Modus: Dann gibt es
      // eben keine Offline-Kopie. Siehe FileSpotCache.write().
      _db = null;
    }
  }

  @override
  Future<CachedSpotRows?> read({required String uid}) async {
    try {
      final db = await _open();
      final txn = db.transaction(storeName, idbModeReadOnly);
      final value = await txn.objectStore(storeName).getObject(_key);
      await txn.completed;
      if (value is! String) return null;
      return decodeSpotCache(value, uid: uid);
    } catch (_) {
      // Kaputter oder unerreichbarer Speicher ist kein Fehlerfall,
      // sondern schlicht „kein Zwischenspeicher".
      _db = null;
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final db = await _open();
      final txn = db.transaction(storeName, idbModeReadWrite);
      await txn.objectStore(storeName).clear();
      await txn.completed;
    } catch (_) {
      // Siehe write(): Ein Löschfehler darf das Abmelden nicht aufhalten.
      _db = null;
    }
  }
}
