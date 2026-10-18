// Die Leitung zum Zeichen-Weg (#641, #689 B2): ein Isolate auf dem Gerät,
// ein Web Worker im Browser. Fächer, Spuren, Ruhe und Tode verwaltet
// `MapWorker` für beide gleich; hier steht nur, wie eine Nachricht
// hinüber- und eine Antwort zurückkommt.
import 'map_worker_task.dart';

/// Was die Leitung meldet.
typedef MapWorkerReplies = ({
  void Function(int id, Object? value) result,
  void Function(int id, String message, String stack) error,

  /// Die Gegenseite ist weg — mitten in der Arbeit oder vor dem Start.
  void Function() died,
});

abstract class MapWorkerTransport {
  /// Startet die Gegenseite und wartet, bis sie bereit ist. Wirft, wenn
  /// es keine gibt — dann rechnet der Rest der Sitzung ohne.
  Future<void> open(MapWorkerReplies replies);

  void slot(MapWorkerTask<Object?, Object?> task, String name, Object? value);
  void drop(String name);
  void job(int id, MapWorkerTask<Object?, Object?> task, Object? params);

  /// Kann die Gegenseite Gitter selbst laden ([MapWorkerLoad], #689 B3)?
  /// Nur der Web Worker — ein Isolate bekäme die Bytes doch wieder vom
  /// Hauptthread, und auf dem Gerät kostet das nichts Spürbares.
  bool get loadsAssets;

  /// Lädt [url] drüben, dekodiert mit [load] und legt das Gitter als Fach
  /// [slot] ab. Antwortet über `result` — mit dem Gitter, wenn [reply],
  /// sonst mit `null`.
  void load(int id, MapWorkerLoad<Object?> load,
      {String? slot,
      required String manifest,
      required String url,
      required bool reply});

  /// Beendet die Gegenseite, OHNE danach noch `died` zu melden.
  void close();
}
