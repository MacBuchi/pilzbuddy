// Unter welcher Adresse ein Asset im Browser liegt (#689, B3) — für den
// Web Worker, der die großen Gitter selbst lädt. Relativ zur Seite; der
// Worker liegt daneben (`map_worker.js`) und löst sie genauso auf.
export 'asset_url_stub.dart' if (dart.library.js_interop) 'asset_url_web.dart';
