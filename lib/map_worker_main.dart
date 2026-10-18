// Der Web Worker des Zeichen-Wegs (#689, B2). Eigenes Programm, ohne
// Flutter übersetzt:
//
//     dart compile js -O2 -DMAP_WORKER_BUILD=<kennung> \
//         -o build/web/map_worker.js lib/map_worker_main.dart
//
// Die App spricht ihn über `lib/core/map_worker_web.dart` an. Hier steht
// nur die Hülle; was er tut, steht in `MapWorkerHost` und den Rechnungen
// (`features/map/map_worker_tasks.dart`).
//
// Nachrichten sind JS-Felder, die Nutzlast ein übergebener `ArrayBuffer`:
//   hin:    ['slot', aufgabe, fach, puffer, länge]
//           ['drop', fach]
//           ['job', id, aufgabe, puffer, länge]
//           ['load', id, laden, fach|null, manifest, adresse, antworten]
//   zurück: ['ready', build]
//           [id, true, puffer|null, länge] | [id, false, meldung, stack]
//
// Nachrichten werden STRENG der Reihe nach abgearbeitet, auch wenn ein
// Laden auf das Netz wartet: Ein Auftrag nach einem Laden findet dessen
// Fach vor (#689, B3).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'core/gunzip_stream_web.dart' show preInflate;
import 'core/map_worker_build.dart';
import 'core/map_worker_host.dart';
import 'core/wire.dart';
import 'features/map/map_worker_tasks.dart';

void main() {
  final scope = globalContext as web.DedicatedWorkerGlobalScope;
  final host = MapWorkerHost(mapWorkerTasks, mapWorkerLoads);

  void reply(JSAny? id, WireBytes? out) {
    if (out == null) {
      scope.postMessage(<JSAny?>[id, true.toJS, null, 0.toJS].toJS);
      return;
    }
    final buffer = out.buffer.toJS;
    scope.postMessage(<JSAny?>[id, true.toJS, buffer, out.length.toJS].toJS,
        <JSAny?>[buffer].toJS);
  }

  void fail(JSAny? id, Object e, StackTrace s) =>
      scope.postMessage(<JSAny?>[id, false.toJS, '$e'.toJS, '$s'.toJS].toJS);

  /// Holt das gepackte Asset (relativ zum Worker, also zur Seite — der
  /// Service Worker liefert es auch ohne Netz) und packt es nativ aus.
  Future<Uint8List> fetchGzipped(String url) async {
    final response = await scope.fetch(url.toJS).toDart;
    if (!response.ok) throw StateError('$url: HTTP ${response.status}');
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    await preInflate(bytes);
    return bytes;
  }

  Future<void> load(List<JSAny?> m) async {
    final id = m[1];
    final slot = (m[3] as JSString?)?.toDart;
    try {
      final gzipped = await fetchGzipped((m[5]! as JSString).toDart);
      reply(
          id,
          host.load((m[2]! as JSString).toDart, slot,
              (m[4]! as JSString).toDart, gzipped,
              reply: (m[6]! as JSBoolean).toDart));
    } catch (e, s) {
      if (slot != null) host.markBroken(slot, '$e');
      fail(id, e, s);
    }
  }

  WireBytes bytesAt(List<JSAny?> m, int i) => (
        buffer: (m[i]! as JSArrayBuffer).toDart,
        length: (m[i + 1]! as JSNumber).toDartInt,
      );

  Future<void> handle(web.MessageEvent event) async {
    final m = (event.data! as JSArray<JSAny?>).toDart;
    switch ((m[0]! as JSString).toDart) {
      case 'load':
        await load(m);
      case 'slot':
        host.slot((m[1]! as JSString).toDart, (m[2]! as JSString).toDart,
            bytesAt(m, 3));
      case 'drop':
        host.drop((m[1]! as JSString).toDart);
      case 'job':
        final id = m[1]!;
        try {
          reply(id, host.run((m[2]! as JSString).toDart, bytesAt(m, 3)));
        } catch (e, s) {
          fail(id, e, s);
        }
    }
  }

  var queue = Future<void>.value();
  void enqueue(web.MessageEvent event) =>
      // Eine Ausnahme darf die Reihe nicht abreißen — `handle` meldet
      // selbst, was einen Auftrag betrifft.
      queue = queue.then((_) => handle(event)).catchError((Object _) {});
  scope.onmessage = enqueue.toJS;
  scope.postMessage(<JSAny?>['ready'.toJS, kMapWorkerBuild.toJS].toJS);
}
