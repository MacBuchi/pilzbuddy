import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Bittet den Browser, diesen Speicher nicht von sich aus zu räumen.
///
/// Antwortet je nach Browser unterschiedlich: Chrome entscheidet still
/// anhand seiner eigenen Kriterien (installierte PWA, Lesezeichen,
/// Nutzungshäufigkeit), Firefox fragt die Nutzerin. Deshalb wird das
/// erst gerufen, wenn wirklich etwas Ungesendetes entstanden ist — eine
/// Nachfrage beim App-Start hätte keinen erkennbaren Anlass.
Future<bool> requestDurableStorage() => _ask((s) => s.persist());

/// Fragt NUR nach dem Stand — ohne Nachfrage, in jedem Browser.
/// Das ist die Grundlage für den Hinweis auf der Karte.
Future<bool> isStorageDurable() => _ask((s) => s.persisted());

Future<bool> _ask(JSPromise<JSBoolean> Function(web.StorageManager) call) async {
  try {
    return (await call(web.window.navigator.storage).toDart).toDart;
  } catch (_) {
    // `navigator.storage` gibt es nur in sicheren Kontexten — über
    // `file://` und in alten Browsern fehlt es ganz. Im Zweifel gilt
    // „nicht zugesichert": Die harmlose Fehlerrichtung ist ein Hinweis
    // zu viel, nicht ein verlorener Fund.
    return false;
  }
}
