import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// Packt [data] als zlib-Strom — nativ über das zlib der Plattform.
Uint8List zlibDeflate(Uint8List data, {required int level}) {
  final out = ZLibCodec(level: level).encode(data);
  return out is Uint8List ? out : Uint8List.fromList(out);
}
