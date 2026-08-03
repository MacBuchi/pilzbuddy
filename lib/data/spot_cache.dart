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

/// Alle Methoden sind **total: sie werfen nie**. Eine fehlende
/// Offline-Kopie ist ein optionales Feature, das still degradieren darf
/// (CLAUDE.md) — sie darf aber niemals einen erfolgreichen Abruf
/// kaputtmachen.
abstract interface class SpotCache {
  Future<CachedSpotRows?> read({required String uid});

  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
  });

  Future<void> clear();
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

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/my_spots.json');
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
  }) async {
    try {
      final file = await _file();
      final temp = File('${file.path}.part');
      await temp.writeAsString(jsonEncode({
        'uid': uid,
        'saved_at': savedAt.toIso8601String(),
        'rows': rows,
      }));
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
  Future<CachedSpotRows?> read({required String uid}) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      // Fremdes Konto: Die Spots eines anderen Nutzers dürfen niemals in
      // einer fremden Sitzung auftauchen.
      if (json['uid'] != uid) return null;
      final savedAt = DateTime.tryParse(json['saved_at'] as String? ?? '');
      if (savedAt == null) return null;
      final rows = (json['rows'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      return (rows: rows, savedAt: savedAt);
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
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Siehe write(): Ein Löschfehler darf das Abmelden nicht aufhalten.
    }
  }
}

/// Web: `path_provider` hat dort kein App-Verzeichnis, und die
/// Offline-Geschichte der App ist ohnehin Android (Offline-Karten,
/// Foreground-Service). Statt bei jedem Seitenaufruf zu scheitern, wird
/// hier gar nichts erst versucht.
class NoSpotCache implements SpotCache {
  const NoSpotCache();

  @override
  Future<CachedSpotRows?> read({required String uid}) async => null;

  @override
  Future<void> write({
    required String uid,
    required List<Map<String, dynamic>> rows,
    required DateTime savedAt,
  }) async {}

  @override
  Future<void> clear() async {}
}

/// Netz zuerst, Zwischenspeicher als Rückfalllinie.
///
/// Als freie Funktion und nicht im Repository, damit die Regel ohne
/// Supabase prüfbar ist: [fetch] ist im Test einfach eine Funktion, die
/// wirft.
Future<SpotRowsResult> fetchSpotRowsWithCache({
  required Future<List<Map<String, dynamic>>> Function() fetch,
  required SpotCache cache,
  required String uid,
  required DateTime now,
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
    final cached = await _quietly(() => cache.read(uid: uid));
    // Ohne Kopie bleibt der Fehler ein Fehler: Eine leere Liste sähe aus
    // wie „du hast keine Spots" und wäre eine Lüge.
    if (cached == null) rethrow;
    return (rows: cached.rows, cachedAt: cached.savedAt);
  }
  // Der Erfolgspfad ist zugleich die einzige Schreibstelle: Alle
  // Mutationen laufen über `invalidateSelf()` und landen wieder hier.
  //
  // Bewusst gekapselt: Ein erfolgreicher Abruf darf niemals daran
  // scheitern, dass sich die Kopie nicht schreiben lässt. Die
  // Offline-Kopie ist ein optionales Feature und darf still degradieren
  // (CLAUDE.md); der Abruf selbst ist der Kernpfad.
  await _quietly(() async {
    await cache.write(uid: uid, rows: rows, savedAt: now);
    return null;
  });
  return (rows: rows, cachedAt: null);
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
