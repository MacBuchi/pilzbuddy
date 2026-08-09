// PNG-Schreiber für die Bild-Overlays der Karte — aus `rain_fill.dart`
// herausgezogen, als mit dem Waldgitter (#213) der zweite Nutzer kam.
//
// Reines Dart samt PNG-Kodierung (zlib und CRC aus `package:archive`, das
// für den KMZ-Import ohnehin im Projekt liegt) — damit läuft es im
// Isolate, im Web und im Test, ohne `dart:ui` und ohne Canvas.
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Baut ein RGBA-PNG aus fertigen Scanlines.
///
/// [scanlines] ist `height * (width * 4 + 1)` Bytes: je Zeile ein
/// Filter-Byte (0 = „None" — die Flächen sind gleichförmig, ein Filter
/// brächte nichts) gefolgt von `width` RGBA-Quadrupeln.
///
/// **zlib-Stufe 1, nicht die voreingestellte 6** (gemessen 2026-08-09 an
/// einem 1193×1536-Bild: 222 ms statt 645 ms, dafür 2,2 statt 2,0 MB).
/// Diese Bilder werden in eine Datei geschrieben und sofort wieder
/// gelesen — sie wandern nie durchs Netz, 10 % mehr Bytes kosten also
/// nichts, während die Kompression bis dahin der TEUERSTE Schritt des
/// Einfärbens war (mehr als Rasterarbeit und Auflösen zusammen). Gilt
/// für Wald, Regen und Ampel gleichermaßen.
Uint8List overlayPng(int width, int height, Uint8List scanlines) {
  final header = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = Uint8List(13);
  final view = ByteData.view(ihdr.buffer);
  view.setUint32(0, width);
  view.setUint32(4, height);
  ihdr[8] = 8; // Bittiefe
  ihdr[9] = 6; // RGBA
  header.add(pngChunk('IHDR', ihdr));
  header.add(pngChunk('IDAT',
      Uint8List.fromList(const ZLibEncoder().encode(scanlines, level: 1))));
  header.add(pngChunk('IEND', Uint8List(0)));
  return header.toBytes();
}

/// Ein einzelner PNG-Chunk: Länge, Typ, Daten, CRC über Typ+Daten.
Uint8List pngChunk(String type, Uint8List data) {
  final out = Uint8List(data.length + 12);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, data.length);
  for (var i = 0; i < 4; i++) {
    out[4 + i] = type.codeUnitAt(i);
  }
  out.setRange(8, 8 + data.length, data);
  view.setUint32(8 + data.length, getCrc32(out.sublist(4, 8 + data.length)));
  return out;
}
