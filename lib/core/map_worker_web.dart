// Der Zeichen-Weg im Browser: ein Web Worker statt eines Isolates
// (#689, B2). Spuren, Fächer, Ruhe und Rückfall regelt `MapWorker` wie
// auf dem Gerät; hier wird nur kodiert, verschickt und zurückgelesen.
//
// Lädt `map_worker.js` nicht (fehlt im Build, Netz weg ohne Kopie im
// Service Worker) oder meldet er einen anderen Build, wirft [open], und
// der Rest der Sitzung rechnet auf dem Hauptthread — wie bis 1.225.x.
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'map_worker_build.dart';
import 'map_worker_task.dart';
import 'map_worker_transport.dart';
import 'wire.dart';

MapWorkerTransport? createWebWorkerTransport() => WebWorkerTransport(
    kMapWorkerBuild.isEmpty
        ? 'map_worker.js'
        : 'map_worker.js?v=$kMapWorkerBuild');

/// So lange darf der Worker zum Laden brauchen. Danach rechnet die
/// Sitzung ohne — die Ebene soll nicht länger auf ihn warten, als sie
/// auf dem Hauptthread brauchte.
const _readyTimeout = Duration(seconds: 15);



class WebWorkerTransport implements MapWorkerTransport {
  /// [url] relativ zur Seite — im Test ein anderer Ort als im Build.
  WebWorkerTransport(this.url);

  final String url;
  web.Worker? _worker;
  final _tasks = <int, MapWorkerTask<Object?, Object?>>{};

  /// Wie viele Ergebnisse aus dem Worker kamen — der Nachweis im Test,
  /// dass wirklich DORT gerechnet wurde.
  int resultsFromWorker = 0;

  @override
  Future<void> open(MapWorkerReplies replies) {
    final ready = Completer<void>();
    final worker = _worker = web.Worker(url.toJS);

    void onMessage(web.MessageEvent event) {
      if (!identical(_worker, worker)) return;
      final m = (event.data! as JSArray<JSAny?>).toDart;
      final head = m[0];
      if (head.isA<JSString>()) {
        final build = (m[1]! as JSString).toDart;
        if (ready.isCompleted) return;
        if (build == kMapWorkerBuild) {
          ready.complete();
        } else {
          ready.completeError(StateError(
              'map_worker.js aus Build „$build", die App ist „$kMapWorkerBuild"'));
        }
        return;
      }
      final id = (head! as JSNumber).toDartInt;
      final task = _tasks.remove(id);
      if (task == null) return;
      if ((m[1]! as JSBoolean).toDart) {
        final Object? value;
        try {
          value = task.decodeResult((
            buffer: (m[2]! as JSArrayBuffer).toDart,
            length: (m[3]! as JSNumber).toDartInt,
          ));
        } catch (e, s) {
          replies.error(id, 'Ergebnis von ${task.id} nicht lesbar: $e', '$s');
          return;
        }
        resultsFromWorker++;
        replies.result(id, value);
      } else {
        replies.error(
            id, (m[2]! as JSString).toDart, (m[3]! as JSString).toDart);
      }
    }

    void onError(web.Event event) {
      if (!identical(_worker, worker)) return;
      // Kein Eintrag in der Konsole als „Uncaught": Behandelt wird es hier.
      event.preventDefault();
      if (!ready.isCompleted) {
        ready.completeError(StateError('map_worker.js lädt nicht'));
        return;
      }
      replies.died();
    }

    worker
      ..onmessage = onMessage.toJS
      ..onerror = onError.toJS;
    return ready.future.timeout(_readyTimeout);
  }

  void _post(List<JSAny?> head, WireBytes bytes) {
    final buffer = bytes.buffer.toJS;
    _worker?.postMessage(
        <JSAny?>[...head, buffer, bytes.length.toJS].toJS,
        <JSAny?>[buffer].toJS);
  }

  @override
  void slot(MapWorkerTask<Object?, Object?> task, String name, Object? value) => _post(
      ['slot'.toJS, task.id.toJS, name.toJS],
      task.slotCodec(name).encode(value));

  @override
  void drop(String name) =>
      _worker?.postMessage(<JSAny?>['drop'.toJS, name.toJS].toJS);

  @override
  void job(int id, MapWorkerTask<Object?, Object?> task, Object? params) {
    _tasks[id] = task;
    _post(['job'.toJS, id.toJS, task.id.toJS], task.encodeParams(params));
  }

  @override
  void close() {
    final worker = _worker;
    _worker = null;
    _tasks.clear();
    worker?.terminate();
  }
}
