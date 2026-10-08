import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibEncoder;

/// Packt [data] als zlib-Strom — im Browser in Dart, `dart:io` fehlt dort.
Uint8List zlibDeflate(Uint8List data, {required int level}) =>
    Uint8List.fromList(const ZLibEncoder().encode(data, level: level));
