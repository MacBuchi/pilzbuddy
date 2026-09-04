// Der Ausgangskorb im Browser (#386).
//
// Dieselbe Aufgabe wie `FileOutbox`, nur ohne Dateisystem. Und derselbe
// Unterschied zum Zwischenspeicher wie dort: **Der Korb trägt das
// Original.** Kommt der Auftrag nicht unter, ist der Fund weg — also
// wirft [append], und der Aufrufer meldet daraufhin den ursprünglichen
// Netzfehler. „Gespeichert" zu behaupten wäre die schlimmste aller
// Varianten.
//
// Was im Browser dazukommt und auf Android nicht vorkommt: **Der
// Speicher darf ohne Vorwarnung geräumt werden.** Dagegen hilft nur
// `navigator.storage.persist()` — und wenn der Browser ablehnt, muss die
// App es sagen (`browser_storage.dart`, Streifen in `map_banners.dart`).
// Deshalb wird trotzdem abgelegt: Chrome lehnt in einem gewöhnlichen Tab
// regelmäßig ab, und dann wäre der Fund SOFORT verloren statt vielleicht
// später.
import 'dart:async';

import 'browser_db.dart';
import 'browser_storage.dart';
import 'outbox.dart';

/// Welcher Korb zu dieser Plattform gehört.
///
/// Als Funktion und nicht als `if (kIsWeb)` im Provider, damit die
/// Entscheidung prüfbar ist — dieselbe Naht wie bei `chooseSpotCache`.
Outbox chooseOutbox({required bool web, required BrowserDb? db}) {
  if (!web) return FileOutbox();
  // Ohne IndexedDB gibt es keinen Ort für das Original. Sichtbar
  // scheitern ist dann richtig: `NoOutbox.append` wirft.
  if (db == null) return const NoOutbox();
  return IndexedDbOutbox(db);
}

/// Der Ausgangskorb in IndexedDB (Browser).
class IndexedDbOutbox implements Outbox {
  IndexedDbOutbox(this._db);

  final BrowserDb _db;

  /// Ein fester Schlüssel, das Konto steht IM Eintrag — wie in der Datei.
  static const _key = 'jobs';

  /// Lese-Ändern-Schreiben ist hier die Regel und nicht die Ausnahme:
  /// Die Wiedervorlage arbeitet den Korb ab, während die Nutzerin einen
  /// weiteren Fund einträgt. Ohne diese Kette verlöre einer der beiden
  /// seinen Stand.
  ///
  /// Bewusst auf Dart-Ebene und nicht als EINE IndexedDB-Transaktion,
  /// die liest und schreibt: Eine Transaktion, über die hinweg `await`et
  /// wird, schließt sich im Browser je nach Zeitpunkt von selbst. Die
  /// Kette hier ist dieselbe, die `FileOutbox` seit 1.79.0 benutzt.
  Future<void> _lock = Future.value();

  /// Einmal je Sitzung reicht: Der Browser merkt sich seine Antwort, und
  /// Firefox würde sonst bei jedem Eintrag erneut fragen.
  bool _askedForDurability = false;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    // Die Kette darf nicht an einem Fehler abreißen — sonst stünde der
    // Korb nach dem ersten Schreibfehler für immer.
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<List<OutboxJob>> read({required String uid}) =>
      _serialized(() => _readUnlocked(uid: uid));

  Future<List<OutboxJob>> _readUnlocked({required String uid}) async {
    try {
      final value =
          await _db.readStore(kOutboxStore, (store) => store.getObject(_key));
      if (value is! String) return const [];
      return decodeOutbox(value, uid: uid);
    } catch (_) {
      // Unlesbar heißt „kein Korb" — wie in der Datei. Bewusst kein
      // `logError`: Das wäre ein Bericht pro App-Start.
      _db.forget();
      return const [];
    }
  }

  @override
  Future<void> append(OutboxJob job, {required String uid}) =>
      _serialized(() async {
        // Der eine Moment, in dem eine Nachfrage erklärbar ist: Gerade
        // ist etwas entstanden, das noch nirgends liegt. Beim App-Start
        // wäre dieselbe Frage eine Zumutung ohne Anlass — dieselbe Linie
        // wie beim Standort (`positionFixProvider` fragt erst auf Tipp).
        //
        // Die Antwort ändert am Ablegen NICHTS. Sie entscheidet nur, ob
        // die Karte den Streifen zeigt.
        if (!_askedForDurability) {
          _askedForDurability = true;
          unawaited(requestDurableStorage());
        }
        final jobs = await _readUnlocked(uid: uid);
        await _writeUnlocked([...jobs, job], uid: uid);
      });

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) =>
      _serialized(() => _writeUnlocked(jobs, uid: uid));

  /// Anders als beim Zwischenspeicher wird hier **nichts geschluckt**:
  /// Ein Fehlschlag muss beim Aufrufer ankommen.
  Future<void> _writeUnlocked(List<OutboxJob> jobs,
          {required String uid}) async =>
      _db.writeStore(kOutboxStore,
          (store) => store.put(encodeOutbox(jobs, uid: uid), _key));

  @override
  Future<void> clear() => _serialized(() async {
        try {
          await _db.writeStore(kOutboxStore, (store) => store.clear());
        } catch (_) {
          // Wie beim Zwischenspeicher: Ein Löschfehler darf das Abmelden
          // nicht aufhalten.
          _db.forget();
        }
      });
}
