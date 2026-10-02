// Entpacken mit dem schnellsten Weg der Plattform (#641).
//
// Alle Gitter der App (Wald, Höhe, Regen, Schutzgebiete, Fundorte,
// Baumarten, Stationen) liegen gzip-gepackt. Bis 1.222.4 entpackte sie
// `package:archive` — reines Dart, am Mac gut viermal langsamer als das
// zlib der Plattform (nachgemessen). Auf dem Pixel XL kostete so ein
// einziger Regenverlauf am Fadenkreuz 4–10 s, weil er rund 120
// Tagesgitter auspackt.
//
// Auf Android ist es deshalb `dart:io`s zlib (nativ, dieselben Bytes);
// im Browser gibt es `dart:io` nicht, dort bleibt `package:archive`.
export 'gunzip_web.dart' if (dart.library.io) 'gunzip_io.dart';
