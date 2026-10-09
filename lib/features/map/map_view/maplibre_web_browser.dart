import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

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
