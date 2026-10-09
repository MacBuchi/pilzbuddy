// Bytes als URL, wo es keine Datei gibt (#689, Hebel C).
//
// MapLibre nimmt ein Bild nur als URL. Auf Android schreibt
// `RainGridRepository.writeFill` dafür eine Datei; im Browser gibt es
// keine Platte, dort wird es eine `blob:`-URL. Der Web-Weg ist die
// Vorgabe, `dart.library.io` wählt den Stub — wie bei `browser_storage`.
export 'object_url_web.dart' if (dart.library.io) 'object_url_stub.dart';
