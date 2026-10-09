// Nativ und im Browser dasselbe Bild (#662): `zlibDeflate` packt auf
// Android mit dem zlib der Plattform statt mit `package:archive`. Die
// gepackten Bytes dürfen sich unterscheiden (zwei Deflate-Umsetzungen),
// das Ausgepackte nicht — und ein PNG aus `overlayPng` muss mit beiden
// Entpackern dieselben Bildzeilen ergeben.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibDecoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/zlib_deflate_io.dart' as native;
import 'package:pilzbuddy/core/zlib_deflate_web.dart' as web;
import 'package:pilzbuddy/features/map/overlay_png.dart';

/// Wie die Overlays: viel Durchsichtiges, dazwischen Flächen.
Uint8List overlayLike(int length, int seed) {
  final r = Random(seed);
  final raw = Uint8List(length);
  for (var i = 0; i < raw.length; i++) {
    raw[i] = r.nextInt(6) == 0 ? r.nextInt(256) : 0;
  }
  return raw;
}

void main() {
  test('beide Wege packen zu denselben Bytes aus', () {
    final raw = overlayLike(300000, 7);
    for (final packed in [
      native.zlibDeflate(raw, level: 1),
      web.zlibDeflate(raw, level: 1),
    ]) {
      expect(const ZLibDecoder().decodeBytes(packed), raw);
      expect(zlib.decode(packed), raw);
    }
  });

  test('overlayPng: Bildzeilen kommen unverändert zurück', () {
    const width = 37, height = 23;
    final scanlines = overlayLike(height * (width * 4 + 1), 11);
    for (var y = 0; y < height; y++) {
      scanlines[y * (width * 4 + 1)] = 0; // Filter „None"
    }
    final png = overlayPng(width, height, scanlines);
    // Signatur (8), IHDR (12 + 13), dann der IDAT-Chunk.
    final view = ByteData.view(png.buffer);
    const idat = 8 + 25;
    final length = view.getUint32(idat);
    expect(String.fromCharCodes(png.sublist(idat + 4, idat + 8)), 'IDAT');
    final data = png.sublist(idat + 8, idat + 8 + length);
    expect(const ZLibDecoder().decodeBytes(data), scanlines);
  });

  test('im Browser ungepackt: Stored-Blöcke über mehrere Blöcke (#689)', () {
    for (final n in [0, 1, 65535, 65536, 200000]) {
      final raw = overlayLike(n, n);
      final packed = web.zlibDeflate(raw, level: 1);
      final blocks = n == 0 ? 1 : (n + 65534) ~/ 65535;
      // Kopf 2, je Block 5, Daten, Adler-32 4 — nichts gepackt.
      expect(packed.length, 2 + blocks * 5 + n + 4, reason: '$n');
      expect(const ZLibDecoder().decodeBytes(packed), raw, reason: '$n');
      expect(zlib.decode(packed), raw, reason: '$n');
    }
  });
}
