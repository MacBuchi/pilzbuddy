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
// .persist()` beim Ausgangskorb (#386) gegen das Aufräumen des Browsers
// abzusichern versucht.
//
// Was hier NICHT gilt und auf Android gilt: Ein Browser darf seinen
// Speicher ohne Vorwarnung räumen. Für eine KOPIE ist das verkraftbar —
// der nächste erfolgreiche Abruf füllt sie wieder. Für das Original
// (Ausgangskorb) ist es das nicht, und genau daran hängt der Unterschied
// zwischen den beiden Dateien.
import 'browser_db.dart';
import 'spot_cache.dart';

/// Welcher Zwischenspeicher zu dieser Plattform gehört.
///
/// Als Funktion und nicht als `if (kIsWeb)` im Provider, damit die
/// Entscheidung prüfbar ist: `kIsWeb` ist eine Konstante und unter
/// `flutter test` immer falsch — dieselbe Naht wie bei
/// `webChannelProvider` und `offlineMapsSupportedProvider`.
SpotCache chooseSpotCache({required bool web, required BrowserDb? db}) {
  if (!web) return FileSpotCache();
  // Kein IndexedDB (privater Modus, `file://`): dann eben keiner.
  if (db == null) return const NoSpotCache();
  return IndexedDbSpotCache(db);
}

/// Der Zwischenspeicher in IndexedDB (Browser).
///
/// Wie die Schnittstelle es verlangt: **wirft nie**. Jeder Fehlschlag
/// endet als „kein Zwischenspeicher", nicht als Ausnahme — ein
/// erfolgreicher Abruf darf niemals daran scheitern, dass sich die Kopie
/// nicht ablegen lässt.
class IndexedDbSpotCache implements SpotCache {
  IndexedDbSpotCache(this._db);

  final BrowserDb _db;

  /// Ein fester Schlüssel, das Konto steht IM Eintrag — genau wie in der
  /// Datei auf Android. Nach der Nutzer-id zu schlüsseln wäre verlockend,
  /// hinterließe aber die Spots jedes früher angemeldeten Kontos im
  /// Browser liegen; so überschreibt der nächste Abruf sie.
  static const _key = 'my_spots';

  @override
  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
  }) async {
    try {
      await _db.writeStore(
          kSpotCacheStore,
          (store) => store.put(
              encodeSpotCache(uid: uid, rows: rows, savedAt: savedAt), _key));
    } catch (_) {
      // Kein Platz, gesperrter Speicher, privater Modus: Dann gibt es
      // eben keine Offline-Kopie. Siehe FileSpotCache.write().
      _db.forget();
    }
  }

  @override
  Future<CachedSpotRows?> read({required String uid}) async {
    try {
      final value = await _db.readStore(
          kSpotCacheStore, (store) => store.getObject(_key));
      if (value is! String) return null;
      return decodeSpotCache(value, uid: uid);
    } catch (_) {
      // Kaputter oder unerreichbarer Speicher ist kein Fehlerfall,
      // sondern schlicht „kein Zwischenspeicher".
      _db.forget();
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _db.writeStore(kSpotCacheStore, (store) => store.clear());
    } catch (_) {
      // Siehe write(): Ein Löschfehler darf das Abmelden nicht aufhalten.
      _db.forget();
    }
  }
}
