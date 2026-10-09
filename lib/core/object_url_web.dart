import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Die zuletzt ausgegebene URL je Platz — die vorige wird freigegeben,
/// sonst hielte jeder Kartenschwenk ein Bild für immer im Speicher.
final _current = <String, String>{};

/// Legt [bytes] als `blob:`-URL ab und gibt die vorige desselben
/// [slot] frei. `null`, wenn der Browser das verweigert.
///
/// Ein Platz entspricht dem Dateipräfix der Platte (`fill_<ebene>_`):
/// Dort räumt `_pruneOthers` die alten Stände weg, hier `revokeObjectURL`.
/// Das alte Bild liegt zu diesem Zeitpunkt längst in der Engine.
String? objectUrlFor(String slot, Uint8List bytes, {required String type}) {
  try {
    final url = web.URL.createObjectURL(web.Blob(
        <web.BlobPart>[bytes.toJS].toJS, web.BlobPropertyBag(type: type)));
    final previous = _current[slot];
    _current[slot] = url;
    if (previous != null) web.URL.revokeObjectURL(previous);
    return url;
  } catch (_) {
    // Ohne URL fehlt die Fläche, die Karte bleibt — dieselbe
    // Fehlerrichtung wie beim Schreiben der Datei (`writeFill`).
    return null;
  }
}
