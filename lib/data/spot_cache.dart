// Der Zwischenspeicher der eigenen Spots — damit die Karte im Wald auch
// dann etwas zeigt, wenn die App dort ohne Empfang NEU startet.
//
// Warum es ihn braucht: `mySpotsProvider` holt alles aus Supabase. Ein
// fehlgeschlagener *Refresh* ist harmlos (Riverpod behält den vorherigen
// Wert), aber beim Kaltstart ohne Empfang gibt es keinen vorherigen Wert —
// und weil jeder Aufrufer den Fehler zu einer leeren Liste macht, stand
// die Karte bis 1.44.0 kommentarlos ohne Spots da. Genau im Wald, wofür
// die Offline-Karten extra da sind.
//
// Gespeichert werden die ROHEN Supabase-Zeilen, nicht die Modelle: `Spot`
// und `Find` haben nur `fromJson`, und ein `toJson` dazuzuschreiben hieße,
// zwei Abbildungen dauerhaft synchron zu halten. So liest derselbe
// `Spot.fromJson` die Daten zurück, den auch das Netz durchläuft.
//
// Voraussetzung, die an fremdem Code hängt: Supabase stellt die Sitzung
// beim Start aus dem lokalen Speicher wieder her, bevor die App läuft —
// ohne Netz und auch mit abgelaufenem Token. Fiele das weg, wäre die
// Nutzer-id beim Kaltstart null und dieses Feature stillschweigend tot.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';

/// Was im Zwischenspeicher lag: die Zeilen und wann sie geholt wurden.
typedef CachedSpotRows = ({List<Map<String, dynamic>> rows, DateTime savedAt});

/// Ergebnis eines Abrufs: die Zeilen und — falls sie aus dem
/// Zwischenspeicher stammen — deren Alter. `cachedAt == null` heißt frisch
/// aus dem Netz.
typedef SpotRowsResult = ({
  List<Map<String, dynamic>> rows,
  DateTime? cachedAt,
});

/// Was ein Schreibvorgang auf dem Server berührt hat: die Spot-ids, die
/// danach neu zu lesen sind ([touched]), und die, die es nicht mehr gibt
/// ([removed]). Siehe [fetchSpotRowsWithCache], Parameter `afterWrite`.
typedef SpotWrite = ({Set<String> touched, Set<String> removed});

/// Alle Methoden sind **total: sie werfen nie**. Eine fehlende
/// Offline-Kopie ist ein optionales Feature, das still degradieren darf
/// (CLAUDE.md) — sie darf aber niemals einen erfolgreichen Abruf
/// kaputtmachen.
abstract interface class SpotCache {
  Future<CachedSpotRows?> read(
      {required String uid, SpotCacheSlot slot = SpotCacheSlot.mine});

  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
    SpotCacheSlot slot = SpotCacheSlot.mine,
  });

  /// Räumt ALLE Fächer — beim Abmelden hat keines davon etwas auf dem
  /// Gerät verloren.
  Future<void> clear();
}

/// Welche Liste: die eigenen Spots oder die der Buddys (seit 1.217.0 —
/// Feldbefund: „die Buddy-Spots waren nicht offline verfügbar"). Zwei
/// Fächer statt einer gemeinsamen Liste, weil beide getrennt abgerufen
/// werden und ein Abruf nie die Kopie des anderen überschreiben darf.
enum SpotCacheSlot {
  mine('my_spots'),
  friends('friend_spots');

  const SpotCacheSlot(this.key);

  /// Dateiname (Android, mit `.json`) bzw. Schlüssel (IndexedDB).
  final String key;
}

/// Die Ablage-Form: EIN JSON-Text, egal wohin er wandert.
///
/// Bewusst geteilt zwischen Datei (Android) und IndexedDB (Browser) —
/// und im Browser bewusst als Text und nicht als Objekt. IndexedDB könnte
/// verschachtelte Maps direkt aufnehmen, gäbe sie aber als
/// `Map<String, Object?>` zurück; `Map<String, dynamic>` ist dazu NICHT
/// zuweisungskompatibel, und `Spot.fromJson` erwartet genau das. Ein Text
/// nimmt denselben Weg durch `jsonDecode` wie auf dem Telefon — eine
/// Abbildung, ein Ergebnis.
String encodeSpotCache({
  required String uid,
  required List<Map<String, dynamic>> rows,
  required DateTime savedAt,
}) =>
    jsonEncode({
      'uid': uid,
      'saved_at': savedAt.toIso8601String(),
      'rows': rows,
    });

/// Liest [text] zurück — oder `null`, wenn nichts Brauchbares darin steht
/// oder der Inhalt zu einem anderen Konto gehört.
CachedSpotRows? decodeSpotCache(String text, {required String uid}) {
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic>) return null;
  // Fremdes Konto: Die Spots eines anderen Nutzers dürfen niemals in
  // einer fremden Sitzung auftauchen.
  if (json['uid'] != uid) return null;
  final savedAt = DateTime.tryParse(json['saved_at'] as String? ?? '');
  if (savedAt == null) return null;
  final rows =
      (json['rows'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
  return (rows: rows, savedAt: savedAt);
}

/// Der Zwischenspeicher als Datei im App-Verzeichnis (Android).
class FileSpotCache implements SpotCache {
  FileSpotCache({Directory? baseDirOverride})
      : _baseDirOverride = baseDirOverride;

  final Directory? _baseDirOverride;

  /// Eigenes Verzeichnis, damit der Backup-Ausschluss in
  /// `backup_rules.xml` / `full_backup_content.xml` genau darauf zeigen
  /// kann — die Datei enthält die geheimen Fundstellen.
  static const dirName = 'spot_cache';

  Future<File> _file(SpotCacheSlot slot) async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${slot.key}.json');
  }

  /// Schreibt über `.part` + `rename`: Ein Abbruch mitten im Schreiben
  /// (Android beendet die App — dass das vorkommt, belegt Issue #147)
  /// darf keine halbe Datei hinterlassen. Sonst wäre das Ergebnis genau
  /// der Zustand, den dieses Feature beseitigen soll.
  @override
  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
    SpotCacheSlot slot = SpotCacheSlot.mine,
  }) async {
    try {
      final file = await _file(slot);
      final temp = File('${file.path}.part');
      await temp.writeAsString(
          encodeSpotCache(uid: uid, rows: rows, savedAt: savedAt));
      await temp.rename(file.path);
    } catch (_) {
      // Volle Platte, fehlende Rechte, kein Dateisystem: Dann gibt es
      // eben keine Offline-Kopie. Der Abruf selbst war erfolgreich und
      // darf daran nicht scheitern — genau dieser Fall hätte im
      // Web-Build sonst die ganze Karte geleert.
    }
  }

  /// Liefert die zwischengespeicherten Zeilen — oder `null`, wenn es
  /// keine gibt, sie zu einem anderen Konto gehören oder die Datei
  /// unlesbar ist.
  @override
  Future<CachedSpotRows?> read(
      {required String uid, SpotCacheSlot slot = SpotCacheSlot.mine}) async {
    try {
      final file = await _file(slot);
      if (!await file.exists()) return null;
      return decodeSpotCache(await file.readAsString(), uid: uid);
    } catch (_) {
      // Kaputte oder unlesbare Datei ist kein Fehlerfall, sondern
      // schlicht „kein Zwischenspeicher" — der nächste erfolgreiche
      // Abruf überschreibt sie. Bewusst NICHT über logError melden
      // (siehe worthReporting): Das wäre ein Bericht pro App-Start.
      return null;
    }
  }

  /// Beim Abmelden und beim Löschen des Kontos: Die Fundstellen des
  /// abgemeldeten Kontos haben auf dem Gerät nichts mehr verloren.
  @override
  Future<void> clear() async {
    try {
      for (final slot in SpotCacheSlot.values) {
        final file = await _file(slot);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Siehe write(): Ein Löschfehler darf das Abmelden nicht aufhalten.
    }
  }
}

/// Gar kein Zwischenspeicher — der ehrliche Fall, wenn es keinen Ort zum
/// Ablegen gibt.
///
/// Bis 1.114.5 war das der ganze Web-Zweig (`path_provider` hat im
/// Browser kein App-Verzeichnis); seit #385 liegt dort IndexedDB. Die
/// Klasse bleibt, weil es den Fall weiter gibt: In Tests ohne Ablage und
/// überall dort, wo ein Zwischenspeicher ausdrücklich NICHT gewollt ist,
/// ist ein stiller Nichtstuer richtiger als eine halbe Ablage.
class NoSpotCache implements SpotCache {
  const NoSpotCache();

  @override
  Future<CachedSpotRows?> read(
          {required String uid, SpotCacheSlot slot = SpotCacheSlot.mine}) async =>
      null;

  @override
  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
    SpotCacheSlot slot = SpotCacheSlot.mine,
  }) async {}

  @override
  Future<void> clear() async {}
}

/// Netz zuerst, Zwischenspeicher als Rückfalllinie.
///
/// Als freie Funktion und nicht im Repository, damit die Regel ohne
/// Supabase prüfbar ist: [fetch] ist im Test einfach eine Funktion, die
/// wirft.
///
/// **Nach einem Schreibvorgang ist der Rückfall nie älter als das
/// Geschriebene** (#706). Die Kopie trägt den Stand des letzten
/// erfolgreichen Vollabrufs. Geht bei wenig Empfang der kleine
/// Schreibzugriff durch und der große Neuabruf (alle Spots samt Funden
/// und Autoren) ins Zeitlimit, stünde hier der Stand von VOR dem
/// Schreiben: Der neue Spot wäre weder in der Liste noch im Ausgangskorb
/// und verschwände von der Karte, während die Oberfläche „gespeichert"
/// meldet. Deshalb nennt der Aufrufer in [afterWrite], was er berührt
/// hat, und [fetchRows] holt genau diese Zeilen nach — eine Anfrage von
/// wenigen Kilobyte, die durch denselben schwachen Empfang passt, an dem
/// die ganze Liste scheitert. Das Ergebnis wird in die Kopie eingesetzt
/// ([patchSpotRows]) und so auch ZURÜCKGESCHRIEBEN: Ein Neustart ohne
/// Empfang zeigt den Spot dann ebenfalls. Scheitert auch das Nachholen,
/// fliegt der Fehler weiter — `reloadAfterWrite` meldet dann
/// „gespeichert, sichtbar sobald die Liste wieder lädt" statt eines
/// frischen Stands, der keiner ist. Mit Empfang wird [fetchRows] nie
/// gerufen.
Future<SpotRowsResult> fetchSpotRowsWithCache({
  required Future<List<Map<String, dynamic>>> Function() fetch,
  required SpotCache cache,
  required String uid,
  required DateTime now,
  SpotCacheSlot slot = SpotCacheSlot.mine,
  SpotWrite? afterWrite,
  Future<List<Map<String, dynamic>>> Function(Set<String> ids)? fetchRows,
}) async {
  final List<Map<String, dynamic>> rows;
  try {
    rows = await fetch();
  } catch (error) {
    // NUR fehlender Empfang führt in den Zwischenspeicher. Ein
    // Serverfehler (Spalte umbenannt, RLS kaputt) muss sichtbar
    // scheitern — versteckte er sich hinter alten Daten, zeigten alle
    // Geräte stillschweigend Veraltetes, und niemand erführe vom
    // kaputten Deployment (Lehre aus Issue #80).
    if (!looksOffline(error)) rethrow;
    final cached = await _quietly(() => cache.read(uid: uid, slot: slot));
    // Ohne Kopie bleibt der Fehler ein Fehler: Eine leere Liste sähe aus
    // wie „du hast keine Spots" und wäre eine Lüge.
    if (cached == null) rethrow;
    if (afterWrite == null ||
        (afterWrite.touched.isEmpty && afterWrite.removed.isEmpty)) {
      return (rows: cached.rows, cachedAt: cached.savedAt);
    }
    // Nachholen, was gerade geschrieben wurde — bewusst NICHT still:
    // Scheitert das, ist die Kopie älter als das Geschriebene, und das
    // muss der Aufrufer erfahren (s. o.).
    final fresh = afterWrite.touched.isEmpty
        ? const <Map<String, dynamic>>[]
        : await (fetchRows ??
            (throw ArgumentError.notNull('fetchRows')))(afterWrite.touched);
    final patched = patchSpotRows(cached.rows, afterWrite, fresh);
    // Die Kopie behält ihr Datum: Der Rest der Liste ist weiter von damals.
    await _quietly(() async {
      await cache.write(
          uid: uid, rows: patched, savedAt: cached.savedAt, slot: slot);
      return null;
    });
    return (rows: patched, cachedAt: cached.savedAt);
  }
  // Der Erfolgspfad ist zugleich die einzige Schreibstelle: Alle
  // Mutationen laufen über `invalidateSelf()` und landen wieder hier.
  //
  // Bewusst gekapselt: Ein erfolgreicher Abruf darf niemals daran
  // scheitern, dass sich die Kopie nicht schreiben lässt. Die
  // Offline-Kopie ist ein optionales Feature und darf still degradieren
  // (CLAUDE.md); der Abruf selbst ist der Kernpfad.
  await _quietly(() async {
    await cache.write(uid: uid, rows: rows, savedAt: now, slot: slot);
    return null;
  });
  return (rows: rows, cachedAt: null);
}

/// Setzt das Ergebnis eines Schreibvorgangs in zwischengespeicherte Zeilen
/// ein. Pur, damit die Regel für sich prüfbar ist:
/// - eine berührte id, die [fresh] liefert, ersetzt ihre alte Zeile an
///   derselben Stelle (die Reihenfolge ist die Zeichen-Stapelung der Karte);
/// - eine neue id kommt hinten an — sie ist die jüngste, und die Liste ist
///   nach `created_at` aufsteigend sortiert;
/// - [SpotWrite.removed] und berührte ids, die der Server NICHT mehr
///   liefert, fallen weg (gelöscht — oder ein Freundes-Spot, der in dieses
///   Fach nie gehörte).
List<Map<String, dynamic>> patchSpotRows(
  List<Map<String, dynamic>> rows,
  SpotWrite write,
  List<Map<String, dynamic>> fresh,
) {
  final byId = {for (final row in fresh) row['id'] as String: row};
  final result = <Map<String, dynamic>>[];
  for (final row in rows) {
    final id = row['id'] as String;
    if (write.removed.contains(id)) continue;
    if (write.touched.contains(id)) {
      final replacement = byId.remove(id);
      if (replacement != null) result.add(replacement);
      continue;
    }
    result.add(row);
  }
  result.addAll(byId.values);
  return result;
}

/// Führt einen Zwischenspeicher-Zugriff aus und schluckt jeden Fehler.
/// Die Schnittstelle sagt zwar zu, nie zu werfen — aber der Kernpfad soll
/// sich nicht darauf verlassen müssen.
Future<CachedSpotRows?> _quietly(Future<CachedSpotRows?> Function() run) async {
  try {
    return await run();
  } catch (_) {
    return null;
  }
}
