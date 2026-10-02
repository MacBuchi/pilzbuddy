import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder;

import 'gunzip_check.dart';

/// Packt gzip aus — im Browser in Dart, `dart:io` fehlt dort.
Uint8List gunzip(List<int> gzipped) {
  final out = GZipDecoder().decodeBytes(gzipped);
  final bytes = out is Uint8List ? out : Uint8List.fromList(out);
  checkGzipLength(gzipped, bytes);
  return bytes;
}
