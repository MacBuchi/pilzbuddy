// Im Browser packt der Browser aus (#689, Hebel B1).
//
// `compute` rechnet im Browser auf dem Hauptthread, also auch jedes
// `gunzip` darin. Gemessen auf der Live-Seite beim Start mit Wald und
// Höhenlinien: gut 5 s reines Entpacken in `package:archive`, der
// größte Einzelposten des Start-Hängers (docs/map-performance.md).
// `DecompressionStream` packt nativ aus und blockiert dabei nicht.
//
// Weil das asynchron ist und die Dekodierer synchron bleiben sollen
// (auf Android laufen sie im Isolate), packt [preInflate] VOR dem
// `boundedCompute` aus und legt das Ergebnis am gepackten Objekt ab;
// `gunzip` nimmt es dort. Geht etwas schief (alter Browser ohne
// `DecompressionStream`, kaputte Daten), liegt nichts bereit, und
// `gunzip` packt wie bisher selbst aus — samt derselben Fehler.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'gunzip_web.dart';

export 'gunzip_web.dart' show gunzip;

/// Packt [gzipped] nativ aus und legt es für den nächsten `gunzip`
/// desselben Objekts bereit. Wirft nie.
Future<void> preInflate(Uint8List gzipped) async {
  try {
    final inflate = web.DecompressionStream('gzip');
    final blob = web.Blob(<web.BlobPart>[gzipped.toJS].toJS);
    final stream = blob.stream().pipeThrough(web.ReadableWritablePair(
      readable: inflate.readable,
      writable: inflate.writable,
    ));
    final buffer = await web.Response(stream).arrayBuffer().toDart;
    rememberInflated(gzipped, buffer.toDart.asUint8List());
  } catch (_) {
    // Kein `DecompressionStream` (Safari < 16.4) oder kaputte Daten:
    // Dann packt `gunzip` selbst aus und meldet den Fehler dort, wo er
    // bisher auch auffiel. Siehe Kopf der Datei.
  }
}
