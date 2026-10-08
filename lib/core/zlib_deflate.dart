// Packen mit dem schnellsten Weg der Plattform (#662) — das Gegenstück
// zu `gunzip.dart`.
//
// Die Bild-Overlays der Karte (Wald, Ampel, Regen, Fundorte) werden als
// PNG geschrieben, und dessen Bilddaten sind zlib. Bis 1.222.7 packte
// `package:archive` sie — reines Dart. Auf dem Pixel XL kostete das je
// Waldbild 0,75–0,9 s (am Mac 70 ms), mehr als Wald und Auflösen
// zusammen.
//
// Auf Android ist es deshalb `dart:io`s zlib (nativ); im Browser gibt es
// `dart:io` nicht, dort bleibt `package:archive`. Die Bytes beider Wege
// sind NICHT gleich (zwei Deflate-Umsetzungen), das Ausgepackte schon —
// und nur das liest ein PNG-Decoder.
export 'zlib_deflate_web.dart' if (dart.library.io) 'zlib_deflate_io.dart';
