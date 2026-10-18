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
//   zurück: ['ready', build]
//           [id, true, puffer, länge] | [id, false, meldung, stack]
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'core/map_worker_build.dart';
import 'core/map_worker_host.dart';
import 'core/wire.dart';
import 'features/map/map_worker_tasks.dart';

void main() {
  final scope = globalContext as web.DedicatedWorkerGlobalScope;
  final host = MapWorkerHost(mapWorkerTasks);

  WireBytes bytesAt(List<JSAny?> m, int i) => (
        buffer: (m[i]! as JSArrayBuffer).toDart,
        length: (m[i + 1]! as JSNumber).toDartInt,
      );

  void handle(web.MessageEvent event) {
    final m = (event.data! as JSArray<JSAny?>).toDart;
    switch ((m[0]! as JSString).toDart) {
      case 'slot':
        host.slot((m[1]! as JSString).toDart, (m[2]! as JSString).toDart,
            bytesAt(m, 3));
      case 'drop':
        host.drop((m[1]! as JSString).toDart);
      case 'job':
        final id = m[1]!;
        try {
          final out =
              host.run((m[2]! as JSString).toDart, bytesAt(m, 3));
          final buffer = out.buffer.toJS;
          scope.postMessage(
              <JSAny?>[id, true.toJS, buffer, out.length.toJS].toJS,
              <JSAny?>[buffer].toJS);
        } catch (e, s) {
          scope.postMessage(
              <JSAny?>[id, false.toJS, '$e'.toJS, '$s'.toJS].toJS);
        }
    }
  }

  scope.onmessage = handle.toJS;
  scope.postMessage(<JSAny?>['ready'.toJS, kMapWorkerBuild.toJS].toJS);
}
