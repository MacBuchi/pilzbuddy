import 'dart:io' show gzip;
import 'dart:typed_data';

import 'gunzip_check.dart';

/// Packt gzip aus — nativ über das zlib der Plattform.
Uint8List gunzip(List<int> gzipped) {
  final out = gzip.decode(gzipped);
  final bytes = out is Uint8List ? out : Uint8List.fromList(out);
  checkGzipLength(gzipped, bytes);
  return bytes;
}

/// Nur im Browser tut das etwas (`gunzip_stream_web.dart`); hier packt
/// `gunzip` ohnehin nativ aus, und zwar im Isolate.
Future<void> preInflate(Uint8List gzipped) async {}
