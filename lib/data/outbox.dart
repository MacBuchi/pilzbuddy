// Der Ausgangskorb (#267): Funde, die ohne Empfang entstanden sind,
// warten hier auf die nächste Verbindung.
//
// Warum es ihn braucht: Lesen ohne Empfang kann die App seit 1.44.0
// (`spot_cache.dart`), Schreiben nicht — `addSpot`/`addFinds` gingen
// direkt nach Supabase und scheiterten im Wald mit „Keine Verbindung".
// Der Fund war damit weg, wenn ihn niemand zu Hause noch einmal eintippt.
// Genau falsch herum: Der Wald ist der Ort, an dem Funde entstehen, UND
// der Ort ohne Netz.
//
// **Der entscheidende Unterschied zum Zwischenspeicher:** Der darf still
// scheitern, weil er nur eine Kopie ist. Dieser hier trägt das Original.
// Kommt der Auftrag nicht auf die Platte, ist der Fund verloren — also
// wirft [Outbox.append], und der Aufrufer sagt es der Nutzerin.
//
// Gespeichert wird eine eigene Darstellung und nicht die rohen
// Supabase-Zeilen (anders als beim Cache): Ein Auftrag IST noch keine
// Zeile — ihm fehlt die id, die erst der Server vergibt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../core/dates.dart';
import '../models/find_position.dart';
import 'spot_repository.dart' show NewFind;

/// Eine UUID v4 aus dem kryptografischen Zufall des Systems — die
/// Kennung, unter der ein Auftrag in der Datenbank landet
/// (`client_id`, Patch 016).
///
/// Ohne Paket: Das wären ein paar hundert Zeilen fremder Code für zehn
/// eigene. Die Kennung muss eindeutig sein, mehr nicht — normkonform ist
/// sie trotzdem.
String newClientId([Random? random]) {
  final rnd = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variante RFC 4122
  final hex = [
    for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Ein wartender Eintrag als JSON.
///
/// Je Eintrag eine eigene Kennung und nicht eine je Auftrag: Ein Sammler
/// legt drei Arten an einem Ort in EINEM Rutsch an (#211), und der
/// Unique-Index in der Datenbank zählt je Zeile.
Map<String, dynamic> _findToJson(NewFind find) => {
      'client_id': find.clientId,
      'species': find.species,
      'count': find.count,
      'found_on': isoDate(find.foundOn),
      'note': find.note,
      'blank': find.blank,
      // Ein verschachtelter Schlüssel statt dreier flacher: eine Stelle
      // zum Vergessen statt drei, und zwei vergessene von drei Feldern
      // wären der stille Fall.
      'position': find.position?.toJson(),
    };

NewFind? _findFromJson(Map<String, dynamic> json) {
  try {
    final foundOn = DateTime.tryParse(json['found_on'] as String? ?? '');
    final clientId = json['client_id'] as String?;
    // Ohne Kennung wäre die Wiedervorlage nicht wiederholbar — genau der
    // Zweck des Korbs. Lieber gar nicht als ohne.
    if (foundOn == null || clientId == null) return null;
    final blank = json['blank'] as bool? ?? false;
    // Fehlt der Schlüssel, stammt der Korb aus einem älteren Stand —
    // anders als bei `client_id` ist das kein Grund, den Eintrag
    // wegzuwerfen: Ein Fund ohne eigene Stelle ist ein gültiger Fund.
    // Beide Zweige reichen sie durch; auch ein Leergang hat einen Ort.
    final position =
        FindPosition.fromJson(json['position'] as Map<String, dynamic>?);
    return blank
        ? NewFind.blank(
            foundOn: foundOn,
            note: json['note'] as String?,
            clientId: clientId,
            position: position)
        : NewFind(
            species: json['species'] as String?,
            count: json['count'] as int?,
            foundOn: foundOn,
            note: json['note'] as String?,
            clientId: clientId,
            position: position,
          );
  } catch (_) {
    return null;
  }
}

/// Ein Auftrag im Korb. Genau zwei Arten — die beiden Schreibwege, die
/// draußen vorkommen. Korrigieren, Löschen, Zusammenführen und der
/// GPX-Import scheitern weiterhin sichtbar: Das ist Schreibtischarbeit
/// im WLAN, und ein Löschauftrag, der Tage später zuschlägt, wäre
/// unangenehmer als eine Fehlermeldung.
sealed class OutboxJob {
  const OutboxJob({
    required this.id,
    required this.createdAt,
    required this.finds,
    this.attempts = 0,
    this.failure,
  });

  /// Zugleich die `client_id` des Spots und der Anker, an dem wartende
  /// Funde hängen, die zu diesem Spot gehören.
  final String id;

  final DateTime createdAt;
  final List<NewFind> finds;

  /// Wie oft die Wiedervorlage es schon versucht hat.
  final int attempts;

  /// Gesetzt heißt: endgültig abgelehnt, wird nicht mehr versucht. Der
  /// Text ist für die Nutzerin, nicht fürs Log.
  final String? failure;

  Map<String, dynamic> toJson();

  OutboxJob copyWith({int? attempts, String? failure});

  static OutboxJob? tryParse(Map<String, dynamic> json) {
    try {
      final id = json['id'] as String?;
      final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
      if (id == null || createdAt == null) return null;
      final finds = <NewFind>[];
      for (final raw in json['finds'] as List<dynamic>? ?? const []) {
        final find = _findFromJson(raw as Map<String, dynamic>);
        // Ein unlesbarer Eintrag macht den ganzen Auftrag ungültig: Einen
        // Spot mit weniger Funden anzulegen, als eingetragen wurden, wäre
        // schlimmer als ihn zu verlieren — es sähe vollständig aus.
        if (find == null) return null;
        finds.add(find);
      }
      final attempts = json['attempts'] as int? ?? 0;
      final failure = json['failure'] as String?;
      return switch (json['kind']) {
        'spot' => NewSpotJob(
            id: id,
            createdAt: createdAt,
            finds: finds,
            lat: (json['lat'] as num).toDouble(),
            lng: (json['lng'] as num).toDouble(),
            name: json['name'] as String?,
            attempts: attempts,
            failure: failure,
          ),
        'finds' => NewFindsJob(
            id: id,
            createdAt: createdAt,
            finds: finds,
            spotId: json['spot_id'] as String,
            spotIsPending: json['spot_is_pending'] as bool? ?? false,
            attempts: attempts,
            failure: failure,
          ),
        _ => null, // Ein Auftragstyp, den dieser Stand nicht kennt.
      };
    } catch (_) {
      return null;
    }
  }
}

/// Ein neuer Spot samt seiner ersten Einträge.
class NewSpotJob extends OutboxJob {
  const NewSpotJob({
    required super.id,
    required super.createdAt,
    required super.finds,
    required this.lat,
    required this.lng,
    this.name,
    super.attempts,
    super.failure,
  });

  final double lat;
  final double lng;
  final String? name;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'spot',
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'lat': lat,
        'lng': lng,
        'name': name,
        'attempts': attempts,
        'failure': failure,
        'finds': [for (final find in finds) _findToJson(find)],
      };

  @override
  NewSpotJob copyWith({int? attempts, String? failure}) => NewSpotJob(
        id: id,
        createdAt: createdAt,
        finds: finds,
        lat: lat,
        lng: lng,
        name: name,
        attempts: attempts ?? this.attempts,
        failure: failure ?? this.failure,
      );
}

/// Einträge an einem Spot, den es schon gibt — oder an einem, der selbst
/// noch im Korb liegt ([spotIsPending], dann ist [spotId] die [id] jenes
/// Auftrags).
class NewFindsJob extends OutboxJob {
  const NewFindsJob({
    required super.id,
    required super.createdAt,
    required super.finds,
    required this.spotId,
    this.spotIsPending = false,
    super.attempts,
    super.failure,
  });

  final String spotId;
  final bool spotIsPending;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'finds',
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'spot_id': spotId,
        'spot_is_pending': spotIsPending,
        'attempts': attempts,
        'failure': failure,
        'finds': [for (final find in finds) _findToJson(find)],
      };

  @override
  NewFindsJob copyWith({int? attempts, String? failure}) => NewFindsJob(
        id: id,
        createdAt: createdAt,
        finds: finds,
        spotId: spotId,
        spotIsPending: spotIsPending,
        attempts: attempts ?? this.attempts,
        failure: failure ?? this.failure,
      );

  /// Nach dem Anlegen des wartenden Spots: Die lokale Referenz wird durch
  /// die echte id ersetzt.
  NewFindsJob resolvedTo(String realSpotId) => NewFindsJob(
        id: id,
        createdAt: createdAt,
        finds: finds,
        spotId: realSpotId,
        attempts: attempts,
        failure: failure,
      );
}

/// Die Ablage-Form des Korbs: EIN JSON-Text, egal wohin er wandert.
///
/// Geteilt zwischen Datei (Android) und IndexedDB (Browser, #386) — und
/// im Browser bewusst als Text und nicht als Objekt: IndexedDB nähme die
/// verschachtelten Aufträge direkt an, gäbe sie aber als
/// `Map<String, Object?>` zurück, worauf `Map<String, dynamic>` nicht
/// zuweisbar ist. Dieselbe Begründung wie bei `encodeSpotCache`.
String encodeOutbox(List<OutboxJob> jobs, {required String uid}) => jsonEncode({
      'uid': uid,
      'jobs': [for (final job in jobs) job.toJson()],
    });

/// Liest [text] zurück — oder `const []`, wenn nichts Brauchbares darin
/// steht oder der Inhalt zu einem anderen Konto gehört.
///
/// Wirft nie: Unlesbar heißt „kein Korb". Ein einzelner unlesbarer
/// Auftrag fällt weg (`OutboxJob.tryParse`), der Rest bleibt.
List<OutboxJob> decodeOutbox(String text, {required String uid}) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return const [];
    // Fremdes Konto: Die Aufträge eines anderen Nutzers dürfen niemals
    // in einer fremden Sitzung hochgehen — sie trügen sonst dessen
    // Fundstellen in mein Konto.
    if (json['uid'] != uid) return const [];
    final jobs = <OutboxJob>[];
    for (final raw in json['jobs'] as List<dynamic>? ?? const []) {
      final job = OutboxJob.tryParse(raw as Map<String, dynamic>);
      if (job != null) jobs.add(job);
    }
    return jobs;
  } catch (_) {
    return const [];
  }
}

/// Der Korb wirft beim Lesen nie, beim **Schreiben** aber sehr wohl —
/// siehe Kopf dieser Datei.
abstract interface class Outbox {
  Future<List<OutboxJob>> read({required String uid});

  /// Hängt einen Auftrag an. Wirft, wenn er nicht sicher liegt.
  Future<void> append(OutboxJob job, {required String uid});

  /// Schreibt den ganzen Korb neu — der Weg der Wiedervorlage, weil
  /// „Auftrag erledigt" und „lokale Referenzen auflösen" GEMEINSAM
  /// gültig werden müssen.
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid});

  Future<void> clear();
}

/// Der Korb als Datei im App-Verzeichnis (Android).
class FileOutbox implements Outbox {
  FileOutbox({Directory? baseDirOverride})
      : _baseDirOverride = baseDirOverride;

  final Directory? _baseDirOverride;

  /// Eigenes Verzeichnis, damit der Backup-Ausschluss in
  /// `backup_rules.xml` / `full_backup_content.xml` genau darauf zeigen
  /// kann — hier stehen die geheimen Fundstellen, bevor sie irgendwo
  /// anders stehen.
  static const dirName = 'outbox';

  /// Lese-Ändern-Schreiben ist hier die Regel und nicht die Ausnahme:
  /// Die Wiedervorlage arbeitet den Korb ab, während die Nutzerin einen
  /// weiteren Fund einträgt. Ohne diese Kette verlöre einer der beiden
  /// seinen Stand.
  Future<void> _lock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    // Die Kette darf nicht an einem Fehler abreißen — sonst stünde der
    // Korb nach dem ersten Schreibfehler für immer.
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/jobs.json');
  }

  @override
  Future<List<OutboxJob>> read({required String uid}) =>
      _serialized(() => _readUnlocked(uid: uid));

  Future<List<OutboxJob>> _readUnlocked({required String uid}) async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      return decodeOutbox(await file.readAsString(), uid: uid);
    } catch (_) {
      // Unlesbar heißt „kein Korb". Bewusst kein `logError`: Das wäre
      // ein Bericht pro App-Start (siehe worthReporting).
      return const [];
    }
  }

  @override
  Future<void> append(OutboxJob job, {required String uid}) =>
      _serialized(() async {
        final jobs = await _readUnlocked(uid: uid);
        await _writeUnlocked([...jobs, job], uid: uid);
      });

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) =>
      _serialized(() => _writeUnlocked(jobs, uid: uid));

  /// Schreibt über `.part` + `rename`: Ein Abbruch mitten im Schreiben
  /// (Android beendet die App — dass das vorkommt, belegt Issue #147)
  /// darf keine halbe Datei hinterlassen. Anders als beim
  /// Zwischenspeicher wird hier **nichts geschluckt**.
  Future<void> _writeUnlocked(List<OutboxJob> jobs,
      {required String uid}) async {
    final file = await _file();
    final temp = File('${file.path}.part');
    await temp.writeAsString(encodeOutbox(jobs, uid: uid), flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> clear() => _serialized(() async {
        try {
          final file = await _file();
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Wie beim Zwischenspeicher: Ein Löschfehler darf das Abmelden
          // nicht aufhalten.
        }
      });
}

/// Kein Ort zum Ablegen, also kein Korb. [append] wirft — und der
/// Aufrufer meldet daraufhin den ursprünglichen Netzfehler, so wie vor
/// diesem Feature. Still „gespeichert" zu melden wäre die schlimmste
/// aller Varianten.
///
/// Bis 1.115.0 war das der ganze Web-Zweig; seit #386 liegt dort
/// IndexedDB. Übrig bleibt der Fall, in dem es auch das nicht gibt —
/// privater Modus mancher Browser, `file://`.
class NoOutbox implements Outbox {
  const NoOutbox();

  @override
  Future<List<OutboxJob>> read({required String uid}) async => const [];

  @override
  Future<void> append(OutboxJob job, {required String uid}) async =>
      throw const OutboxUnavailable();

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) async {}

  @override
  Future<void> clear() async {}
}

class OutboxUnavailable implements Exception {
  const OutboxUnavailable();

  @override
  String toString() => 'Auf dieser Plattform gibt es keinen Ausgangskorb';
}
