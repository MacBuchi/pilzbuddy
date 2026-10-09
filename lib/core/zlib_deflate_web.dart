import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getAdler32;

/// Längster Stored-Block, den Deflate kennt (LEN ist 16 Bit).
const _maxStored = 65535;

/// Schreibt [data] als zlib-Strom aus UNGEPACKTEN Blöcken (#689) —
/// [level] gilt im Browser nicht.
///
/// Gepackt hat hier bis 1.224.x `package:archive`, in Dart auf dem
/// Hauptthread: Beim Start mit Wald kostete das auf der Live-Seite
/// 1,4 s je Waldbild (docs/map-performance.md). Das PNG geht im Browser
/// nie durchs Netz und nie auf eine Platte, es wird sofort wieder
/// dekodiert — und das nativ. Größer zu sein kostet dort also nichts,
/// Packen kostet den Hänger. Jeder PNG-Leser versteht Stored-Blöcke
/// (RFC 1951, BTYPE 00).
Uint8List zlibDeflate(Uint8List data, {required int level}) {
  final blocks =
      data.isEmpty ? 1 : (data.length + _maxStored - 1) ~/ _maxStored;
  final out = Uint8List(2 + blocks * 5 + data.length + 4);
  out[0] = 0x78; // CM 8, Fenster 32 KB
  out[1] = 0x01; // FLEVEL 0, (0x78 << 8 | 0x01) % 31 == 0
  var o = 2;
  for (var b = 0; b < blocks; b++) {
    final start = b * _maxStored;
    final end = math.min(start + _maxStored, data.length);
    final len = end - start;
    out[o++] = b == blocks - 1 ? 1 : 0; // BFINAL, BTYPE 00
    out[o++] = len & 0xFF;
    out[o++] = len >> 8;
    out[o++] = ~len & 0xFF;
    out[o++] = (~len >> 8) & 0xFF;
    out.setRange(o, o + len, data, start);
    o += len;
  }
  final adler = getAdler32(data);
  out[o++] = (adler >> 24) & 0xFF;
  out[o++] = (adler >> 16) & 0xFF;
  out[o++] = (adler >> 8) & 0xFF;
  out[o] = adler & 0xFF;
  return out;
}
