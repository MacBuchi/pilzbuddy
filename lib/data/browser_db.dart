// Die eine Datenbank der App im Browser — ein Speicher je Zweck.
//
// Warum das hier steht und nicht bei seinen Nutzern: Name und Version
// müssen EINEN Besitzer haben. Öffnete der Zwischenspeicher v1 und der
// Ausgangskorb v2, blockierte der Upgrade — im selben Tab, dauerhaft,
// ohne Fehlermeldung. Ein neuer Speicher heißt deshalb: hier eintragen,
// [kBrowserDbVersion] erhöhen, fertig; [_upgrade] legt an, was fehlt,
// und lässt Vorhandenes in Ruhe.
import 'package:idb_shim/idb_shim.dart';

/// Eine Datenbank für die ganze App.
const kBrowserDbName = 'pilzbuddy';

/// v1: `spot_cache` (#385). v2: `outbox` (#386).
const kBrowserDbVersion = 2;

/// Der Zwischenspeicher der eigenen Spots (`spot_cache_idb.dart`).
const kSpotCacheStore = 'spot_cache';

/// Der Ausgangskorb (`outbox_idb.dart`).
const kOutboxStore = 'outbox';

const _stores = [kSpotCacheStore, kOutboxStore];

/// Der geteilte Zugang zur Datenbank: EINE Verbindung je Sitzung, egal
/// wie viele Speicher sie benutzen.
///
/// Wirft, wenn sich nichts öffnen lässt — was daraus folgt, entscheidet
/// der Aufrufer: Der Zwischenspeicher schluckt es (er ist eine Kopie),
/// der Ausgangskorb reicht es weiter (er trägt das Original).
class BrowserDb {
  BrowserDb(this._factory);

  final IdbFactory _factory;

  Database? _db;

  Future<Database> open() async {
    final open = _db;
    if (open != null) return open;
    final db = await _factory.open(kBrowserDbName,
        version: kBrowserDbVersion, onUpgradeNeeded: _upgrade);
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
      // und weil der Zwischenspeicher nie werfen darf, hätte niemand es
      // gemerkt. Die Absicherung ist ein Zusatz, keine Bedingung.
    }
    return _db = db;
  }

  /// Nach einem Fehlschlag: Die gemerkte Verbindung wegwerfen, damit der
  /// nächste Zugriff neu öffnet.
  void forget() => _db = null;

  /// Ein Lesezugriff auf einen Speicher, Transaktion inklusive.
  ///
  /// Als Methode hier und nicht als drei Zeilen bei jedem Aufrufer: Wer
  /// `txn.completed` vergisst, bekommt keinen Fehler, sondern eine
  /// Schreiboperation, die vielleicht noch läuft, wenn die nächste
  /// beginnt. Einmal richtig ist besser als achtmal gleich.
  Future<T> readStore<T>(
          String store, Future<T> Function(ObjectStore) action) =>
      _inStore(store, idbModeReadOnly, action);

  /// Ein Schreibzugriff auf einen Speicher, Transaktion inklusive.
  Future<T> writeStore<T>(
          String store, Future<T> Function(ObjectStore) action) =>
      _inStore(store, idbModeReadWrite, action);

  Future<T> _inStore<T>(
      String store, String mode, Future<T> Function(ObjectStore) action) async {
    final db = await open();
    final txn = db.transaction(store, mode);
    final result = await action(txn.objectStore(store));
    await txn.completed;
    return result;
  }

  static void _upgrade(VersionChangeEvent event) {
    final db = event.database;
    for (final store in _stores) {
      if (!db.objectStoreNames.contains(store)) db.createObjectStore(store);
    }
  }
}
