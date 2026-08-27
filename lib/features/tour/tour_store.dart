// Wo die laufende Pilztour liegt (#338) — auf der Platte, Zeile für
// Zeile, während sie entsteht.
//
// **Warum nicht am Stück am Ende.** Drei Stunden Gehen dürfen nicht daran
// hängen, dass Android den Prozess am Leben lässt — dass es das nicht tut,
// belegt Issue #147 mit gemessenen Speicher-Kills. Eine Tour, die
// verlorengeht, weil das Telefon in der Tasche aufgeräumt wurde, ist
// schlimmer als gar keine Tour: Man hat sich auf sie verlassen.
//
// **Warum JSON Lines und nicht die Bauform des Ausgangskorbs.** `outbox`
// liest, ändert und schreibt die ganze Datei neu — richtig für eine
// Handvoll Aufträge, falsch für 720 Punkte einer Dreistundentour: Das
// wären 720 Neuschriften mit wachsender Länge. Hier wird angehängt. Der
// Preis ist, dass ein Abbruch mitten im Schreiben eine halbe LETZTE Zeile
// hinterlassen kann — und genau die wirft [read] weg, ohne dass der Rest
// der Tour etwas davon merkt. Beim Korb wäre derselbe Abbruch eine halbe
// DATEI, deshalb steht dort `.part` + `rename`.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import 'tour_track.dart';

/// Eine aufgezeichnete Tour: wann sie begann und was seither gemessen wurde.
typedef RecordedTour = ({DateTime startedAt, List<TourPoint> points});

abstract interface class TourStore {
  /// Beginnt eine Tour und verwirft, was vorher dalag.
  ///
  /// **Wirft**, wenn sich nichts anlegen lässt: Eine Tour zu starten, die
  /// gar nicht aufgezeichnet werden kann, wäre ein Versprechen, das erst
  /// drei Stunden später auffliegt.
  Future<void> begin({required String uid, required DateTime startedAt});

  /// Hängt einen Punkt an. **Wirft nie** — ein verlorener Fix ist ein
  /// verlorener Fix, kein Grund, die laufende Tour abzubrechen.
  Future<void> appendPoint(TourPoint point);

  /// Die laufende Tour, oder `null`. Wirft nie.
  Future<RecordedTour?> read({required String uid});

  Future<void> clear();
}

class FileTourStore implements TourStore {
  FileTourStore({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;

  /// Muss in `backup_rules.xml` UND `full_backup_content.xml` stehen.
  /// Ein Track ist ein Bewegungsprofil — es hat in Googles Cloud so wenig
  /// verloren wie die Fundstellen in `spot_cache/`.
  static const dirName = 'tours';

  /// Schreibvorgänge in einer Kette. Der Tick hängt an, während der
  /// Abschluss liest — ohne die Kette verlöre einer von beiden seinen
  /// Stand.
  Future<void> _lock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/active.jsonl');
  }

  @override
  Future<void> begin({
    required String uid,
    required DateTime startedAt,
  }) =>
      _serialized(() async {
        final file = await _file();
        await file.writeAsString(
          '${jsonEncode({
                'uid': uid,
                'startedAt': startedAt.toUtc().toIso8601String(),
              })}\n',
          flush: true,
        );
      });

  @override
  Future<void> appendPoint(TourPoint point) => _serialized(() async {
        try {
          final file = await _file();
          await file.writeAsString(
            '${jsonEncode(point.toJson())}\n',
            mode: FileMode.append,
            flush: true,
          );
        } catch (e, stackTrace) {
          // Bewusst gemeldet und nicht geschluckt: Anders als ein
          // fehlender Zwischenspeicher ist das echter Datenverlust. Aber
          // eben einer, der die Tour weiterlaufen lässt.
          logError('Tour-Punkt anhängen', e, stackTrace);
        }
      });

  @override
  Future<RecordedTour?> read({required String uid}) =>
      _serialized(() async {
        try {
          final file = await _file();
          if (!await file.exists()) return null;
          final lines = const LineSplitter()
              .convert(await file.readAsString())
              .where((line) => line.isNotEmpty)
              .toList();
          if (lines.isEmpty) return null;

          final head = jsonDecode(lines.first);
          if (head is! Map<String, dynamic>) return null;
          // Fremdes Konto: Die Tour eines anderen Nutzers darf niemals in
          // einer fremden Sitzung zu Leergängen werden — dieselbe Regel
          // wie im Ausgangskorb.
          if (head['uid'] != uid) return null;
          final startedAt =
              DateTime.tryParse(head['startedAt'] as String? ?? '');
          if (startedAt == null) return null;

          final points = <TourPoint>[];
          for (final line in lines.skip(1)) {
            // Eine abgeschnittene LETZTE Zeile ist der Normalfall nach
            // einem Prozess-Kill, kein Fehler — sie fällt hier weg, und
            // der Rest der Tour bleibt heil.
            try {
              final json = jsonDecode(line);
              if (json is! Map<String, dynamic>) continue;
              final point = TourPoint.fromJson(json);
              if (point != null) points.add(point);
            } catch (_) {
              continue;
            }
          }
          return (startedAt: startedAt.toUtc(), points: points);
        } catch (_) {
          // Unlesbar heißt „keine Tour". Kein `logError`: Das wäre ein
          // Bericht pro App-Start (siehe worthReporting).
          return null;
        }
      });

  @override
  Future<void> clear() => _serialized(() async {
        try {
          final file = await _file();
          if (await file.exists()) await file.delete();
        } catch (e, stackTrace) {
          // Bleibt die Datei liegen, böte die App beim nächsten Start
          // eine Tour an, die längst abgeschlossen ist — das gehört
          // gemeldet.
          logError('Tour verwerfen', e, stackTrace);
        }
      });
}
