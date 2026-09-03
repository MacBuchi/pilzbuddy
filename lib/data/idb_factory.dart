// Woher der IndexedDB-Zugang kommt — im Browser der echte, sonst keiner.
//
// Dieselbe Bauweise wie `download_keep_alive.dart` und `map_view.dart`:
// Der Web-Weg ist die Vorgabe, `dart.library.io` wählt den Stub. Nur so
// sieht der Android-Build `package:idb_shim/idb_browser.dart` nie — das
// Paket bringt dort seine Web-Interop-Schicht mit.
export 'idb_factory_web.dart' if (dart.library.io) 'idb_factory_stub.dart';
