import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../../core/gunzip_stream_web.dart';
import '../app_tile_protocol.dart';

/// Gerätelokal wie die Kartenschalter — aber nicht in den
/// SharedPreferences, weil es einen Versuch steuert und keine Einstellung
/// ist, die das Profil kennt.
const _flagKey = 'pilzbuddy.web_maplibre';

/// Hat dieser Browser MapLibre GL JS gewählt?
///
/// `?maplibre=1` schaltet ein, `?maplibre=0` aus; beides wird gemerkt,
/// damit der Schalter einen Neustart der PWA übersteht (die startet ohne
/// Parameter). Ohne Speicher (privater Modus) gilt nur der Parameter.
bool webMapLibreRequested() {
  final param = Uri.base.queryParameters['maplibre'];
  try {
    final storage = web.window.localStorage;
    if (param == '1') storage.setItem(_flagKey, '1');
    if (param == '0') storage.removeItem(_flagKey);
    return storage.getItem(_flagKey) == '1';
  } catch (_) {
    // Kein `localStorage` (privater Modus, gesperrte Website-Daten):
    // Dann zählt der Parameter allein. Die Vorgabe bleibt flutter_map.
    return param == '1';
  }
}

Future<bool>? _loading;

/// Lädt MapLibre GL JS und PMTiles aus `web/maplibre/` — einmal je
/// Sitzung, und erst, wenn die Engine gebraucht wird. `false`, wenn das
/// scheitert; dann zeichnet die Ansicht flutter_map.
///
/// Relativ zur `<base href>`, also für Freigabe und Vorschau gleich.
/// Nacheinander, nicht parallel: `pmtiles.js` hängt sich nicht an
/// `maplibregl`, aber das Paket ruft beide beim Anlegen der Karte, und
/// eine feste Reihenfolge macht einen Fehlschlag eindeutig.
Future<bool> loadMapLibreJs() => _loading ??= _load();

Future<bool> _load() async {
  try {
    if (!globalContext.has('maplibregl')) {
      final css = web.HTMLLinkElement()
        ..rel = 'stylesheet'
        ..href = 'maplibre/maplibre-gl.css';
      web.document.head!.appendChild(css);
      await _script('maplibre/maplibre-gl.js');
    }
    if (!globalContext.has('pmtiles')) await _script('maplibre/pmtiles.js');
    return globalContext.has('maplibregl') && globalContext.has('pmtiles');
  } catch (_) {
    // Datei fehlt oder Netz weg: Die Ansicht fällt auf flutter_map
    // zurück — ein Versuch nimmt niemandem die Karte.
    return false;
  }
}

Future<void> _script(String src) {
  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = src
    ..async = false;
  script.onload = ((web.Event _) => done.complete()).toJS;
  script.onerror = ((web.Event _) =>
      done.completeError(StateError('$src nicht geladen'))).toJS;
  web.document.head!.appendChild(script);
  return done.future;
}

/// Lässt die MapLibre-Fläche Zeiger-Ereignisse annehmen oder nicht.
///
/// Im Browser liegt die Karte als HTML-Element UNTER Flutters
/// Zeichenfläche, nimmt aber jeden Klick zuerst — ein Dialog oder ein
/// Blatt über der Karte wäre sonst nicht zu bedienen. Für die festen
/// Bedienelemente gibt es `MapOverlayGuard`; für alles, was als Route
/// darüber aufgeht, schaltet die Ansicht hier die ganze Fläche ab.
void setMapLibrePointerEvents(bool enabled) {
  try {
    final maps = web.document.querySelectorAll('.maplibregl-map');
    for (var i = 0; i < maps.length; i++) {
      (maps.item(i) as web.HTMLElement?)?.style.pointerEvents =
          enabled ? '' : 'none';
    }
  } catch (_) {
    // Ohne DOM-Zugriff bleibt es beim Standard: Die Karte nimmt Klicks.
  }
}

/// Meldet das Kachel-Protokoll der App bei MapLibre GL JS an (#689,
/// `app_tile_protocol.dart`). `false`, wenn die Bibliothek fehlt oder die
/// Anmeldung scheitert — dann bleibt der Style bei `pmtiles://`.
///
/// Gepackte Kacheln packt der Browser aus (`DecompressionStream`), nicht
/// Dart: Das Ergebnis geht als `ArrayBuffer` unverändert an MapLibre, und
/// der Hauptthread wartet nur. Eine fehlende Kachel ist ein leerer Puffer
/// — wie beim `pmtiles`-Protokoll, MapLibre zeichnet dort nichts.
bool registerAppTileProtocol(Future<AppTile?> Function(String url) load) {
  try {
    final maplibregl = globalContext['maplibregl'] as JSObject?;
    if (maplibregl == null) return false;
    JSPromise<JSObject> handler(JSObject params, JSAny? abort) {
      Future<JSObject> serve() async {
        final url = (params['url'] as JSString).toDart;
        final tile = await load(url);
        final JSArrayBuffer data;
        if (tile == null) {
          data = JSArrayBuffer(0);
        } else if (tile.gzip) {
          data = await _inflate(tile.bytes);
        } else {
          // Kopie: Ein Ausschnitt eines größeren Puffers gäbe MapLibre
          // sonst den ganzen Puffer.
          data = Uint8List.fromList(tile.bytes).buffer.toJS;
        }
        return JSObject()..['data'] = data;
      }

      return serve().toJS;
    }

    maplibregl.callMethod('addProtocol'.toJS, kAppTileScheme.toJS, handler.toJS);
    return true;
  } catch (_) {
    // Ältere Bibliothek ohne `addProtocol` oder kein DOM: Der Style nimmt
    // dann die bisherigen Wege, die Karte bleibt dieselbe.
    return false;
  }
}

Future<JSArrayBuffer> _inflate(Uint8List gzipped) async {
  try {
    return await inflateNatively(gzipped);
  } catch (_) {
    // Kein `DecompressionStream` (Safari < 16.4): langsamer in Dart, aber
    // dieselben Bytes. Kaputte Daten werfen hier noch einmal — MapLibre
    // lässt die Kachel dann leer.
    return Uint8List.fromList(gunzip(gzipped)).buffer.toJS;
  }
}
