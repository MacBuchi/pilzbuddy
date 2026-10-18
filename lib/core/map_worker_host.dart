// Die Gegenseite des Zeichen-Wegs im Web Worker (#689, B2) — ohne
// Browser-Bezug, damit der Test sie auf der VM fahren kann. Die Hülle,
// die Nachrichten annimmt und verschickt, ist `lib/map_worker_main.dart`.
import 'map_worker_task.dart';
import 'wire.dart';

class MapWorkerHost {
  MapWorkerHost(Iterable<MapWorkerTask<Object?, Object?>> tasks)
      : _tasks = {for (final t in tasks) t.id: t};

  final Map<String, MapWorkerTask<Object?, Object?>> _tasks;
  final _slots = <String, Object?>{};

  /// Fächer, die nicht zu lesen waren — der nächste Auftrag sagt es,
  /// statt an einem fehlenden Fach mit einem nichtssagenden Cast zu
  /// scheitern.
  final _broken = <String, String>{};

  MapWorkerTask<Object?, Object?> _task(String id) =>
      _tasks[id] ?? (throw StateError('Rechnung $id kennt der Worker nicht'));

  void slot(String taskId, String name, WireBytes bytes) {
    try {
      _slots[name] = _task(taskId)
          .slotCodec(name)
          .decode(bytes.buffer, bytes.length);
      _broken.remove(name);
    } catch (e) {
      _slots.remove(name);
      _broken[name] = '$e';
    }
  }

  void drop(String name) {
    _slots.remove(name);
    _broken.remove(name);
  }

  /// Rechnet und gibt das kodierte Ergebnis zurück. Wirft, was die
  /// Rechnung wirft.
  WireBytes run(String taskId, WireBytes params) {
    if (_broken.isNotEmpty) {
      throw StateError('Fach nicht lesbar: ${_broken.entries.first}');
    }
    final task = _task(taskId);
    return task.encodeResult(
        task.call(MapWorkerSlots(_slots), task.decodeParams(params)));
  }

  /// Welche Fächer gerade liegen — für den Test.
  Set<String> get slotNames => _slots.keys.toSet();
}
