// Packen mit dem schnellsten Weg der Plattform (#662) — das Gegenstück
// zu `gunzip.dart`.
//
// Die Bild-Overlays der Karte (Wald, Ampel, Regen, Fundorte) werden als
// PNG geschrieben, und dessen Bilddaten sind zlib. Bis 1.222.7 packte
// `package:archive` sie — reines Dart. Auf dem Pixel XL kostete das je
// Waldbild 0,75–0,9 s (am Mac 70 ms), mehr als Wald und Auflösen
// zusammen.
//
// Auf Android ist es deshalb `dart:io`s zlib (nativ). Im Browser gibt es
// `dart:io` nicht; dort wird seit #689 gar nicht gepackt, sondern in
// Stored-Blöcken geschrieben (Begründung in `zlib_deflate_web.dart`).
// Die Bytes beider Wege sind NICHT gleich, das Ausgepackte schon — und
// nur das liest ein PNG-Decoder.
export 'zlib_deflate_web.dart' if (dart.library.io) 'zlib_deflate_io.dart';
