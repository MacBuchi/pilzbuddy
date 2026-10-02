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
