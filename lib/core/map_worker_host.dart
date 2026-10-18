// Die Gegenseite des Zeichen-Wegs im Web Worker (#689, B2) — ohne
// Browser-Bezug, damit der Test sie auf der VM fahren kann. Die Hülle,
// die Nachrichten annimmt und verschickt, ist `lib/map_worker_main.dart`.
import 'dart:typed_data';

import 'map_worker_task.dart';
import 'wire.dart';

class MapWorkerHost {
  MapWorkerHost(Iterable<MapWorkerTask<Object?, Object?>> tasks,
      [Iterable<MapWorkerLoad<Object?>> loads = const []])
      : _tasks = {for (final t in tasks) t.id: t},
        _loads = {for (final l in loads) l.id: l};

  final Map<String, MapWorkerTask<Object?, Object?>> _tasks;
  final Map<String, MapWorkerLoad<Object?>> _loads;
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

  /// Dekodiert ein selbst geladenes Gitter (#689, B3) und legt es als
  /// Fach [slot] ab — ohne Fach nur dekodiert. Gibt das kodierte Ergebnis
  /// zurück, wenn [reply]; beim Wiederherstellen nach einer Ruhe hat die
  /// App es schon. Ein `null`-Gitter (Asset unbekannt oder kaputt) räumt
  /// das Fach. Wirft, was die Dekodierung wirft — dann ist das Fach
  /// kaputt, und der nächste Auftrag sagt es.
  WireBytes? load(String loadId, String? slot, String manifest,
      Uint8List gzipped, {required bool reply}) {
    final load =
        _loads[loadId] ?? (throw StateError('Laden $loadId kennt der Worker nicht'));
    final Object? value;
    try {
      value = load.call(manifest, gzipped);
    } catch (e) {
      if (slot != null) {
        _slots.remove(slot);
        _broken[slot] = '$e';
      }
      rethrow;
    }
    if (slot != null) {
      _broken.remove(slot);
      if (value == null) {
        _slots.remove(slot);
      } else {
        _slots[slot] = value;
      }
    }
    return reply ? load.encodeResult(value) : null;
  }

  /// Ein Fach, dessen Laden scheiterte — für die Leitung, die das Laden
  /// nicht selbst ausführt (Abruf fehlgeschlagen).
  void markBroken(String slot, String reason) {
    _slots.remove(slot);
    _broken[slot] = reason;
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
