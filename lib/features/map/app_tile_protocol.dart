// Die Kacheln für MapLibre GL JS kommen im Browser von der App (#689).
//
// Im Browser holte MapLibre GL JS sich alles selbst: die Übersicht und die
// Neue Karte per `pmtiles://` (Range-Anfragen), und an die gespeicherten
// Kartenbereiche in IndexedDB kam es gar nicht heran. Daraus wurden drei
// Lücken gegenüber flutter_map, die vor dem Umlegen der Vorgabe zu
// schließen waren:
//
// - **Gespeicherte Bereiche** fehlten ganz.
// - **Die Neue Karte** ging an der App vorbei direkt an R2 — ungezählt und
//   ohne das Zusammenlegen gleicher Anfragen.
// - **Die Übersicht ohne Netz** fehlte: Der Service Worker legt
//   Teilanfragen nicht ab, das Asset kam nur mit Empfang.
//
// Alle drei schließt ein eigenes Protokoll: Der Style nennt
// `pilzbuddy://<quelle>/{z}/{x}/{y}`, `maplibregl.addProtocol` reicht jede
// Anfrage an [AppTileRouter.load], und der liest aus denselben
// Archiv-Lesern, die flutter_map im Browser benutzt (Übersicht ganz aus
// dem Asset, Bereiche aus IndexedDB, Neue Karte aus dem Archiv, das
// `onlineMapProvider` ohnehin öffnet). Es ist dasselbe Prinzip wie der
// Kachel-Server auf Android (#659), nur ohne Loopback.
//
// Dieser Teil ist reines Dart und läuft im Test in der VM; das Anmelden
// beim Browser und das Entpacken stehen in `maplibre_web_browser.dart`.
import 'dart:async';
import 'dart:typed_data';

import 'online_tile_server.dart' show RawTileFetch;

/// Das Schema im Style. Eigener Name, damit es nie mit dem
/// `pmtiles`-Protokoll des Pakets zusammenfällt.
const kAppTileScheme = 'pilzbuddy';

/// Höchstbelegung des Speichers für Kacheln aus dem NETZ. Übersicht und
/// Bereiche liegen ohnehin ganz im Speicher und brauchen keinen.
/// MapLibre hält selbst nur, was gerade zu sehen ist; ein Schwenk zurück
/// fragte sonst R2 erneut.
const kAppTileCacheMaxBytes = 16 * 1024 * 1024;

/// Eine Kachel, wie sie im Archiv liegt.
typedef AppTile = ({Uint8List bytes, bool gzip});

/// Eine Quelle hinter dem Protokoll.
class AppTileSource {
  const AppTileSource(this.fetch, {required this.gzip, this.remote = false});

  final RawTileFetch fetch;

  /// Liegen die Kacheln gzip-gepackt im Archiv (Header)?
  final bool gzip;

  /// Kommt jede Kachel über das Netz? Nur dann lohnt der Speicher.
  final bool remote;
}

class AppTileRouter {
  AppTileRouter({this.maxCacheBytes = kAppTileCacheMaxBytes});

  final int maxCacheBytes;

  var _sources = <String, AppTileSource>{};
  final _inFlight = <String, Future<Uint8List?>>{};
  final _missing = <String>{};
  final _cache = <String, Uint8List>{}; // Einfügereihenfolge = LRU
  var _cacheBytes = 0;

  /// Die Kachel-Vorlage für eine Quelle. Der Schlüssel wird kodiert, damit
  /// ein `/` darin nie die Zerlegung in [load] verschiebt.
  static String urlTemplate(String key) =>
      '$kAppTileScheme://${Uri.encodeComponent(key)}/{z}/{x}/{y}';

  /// Ersetzt die Quellen durch die des neuen Styles. Was dort nicht mehr
  /// vorkommt, gibt ab sofort keine Kacheln mehr — und hält sein Archiv
  /// nicht länger fest. Abgelegte Kacheln bleiben: Ihr Schlüssel trägt den
  /// Stand, ein neuer Stand fragt nie nach einem alten.
  void replaceSources(Map<String, AppTileSource> sources) {
    _sources = Map.of(sources);
  }

  /// Die Kachel zu [url] — `null`, wenn es dort keine gibt (Lücke im
  /// Archiv, unbekannte Quelle, keine Kachel-Adresse). Fehler beim Lesen
  /// werfen; MapLibre lässt die Kachel dann leer und fragt später neu.
  Future<AppTile?> load(String url) async {
    final parsed = _parse(url);
    if (parsed == null) return null;
    final (key, z, x, y) = parsed;
    final source = _sources[key];
    if (source == null) return null;
    final id = '$key/$z/$x/$y';
    if (_missing.contains(id)) return null;
    final cached = _cache.remove(id);
    if (cached != null) {
      _cache[id] = cached; // ans Ende: zuletzt benutzt
      return (bytes: cached, gzip: source.gzip);
    }
    // Fragt MapLibre dieselbe Kachel zweimal, bevor die erste Antwort da
    // ist, geht EIN Abruf hinaus. Der Block-Rumpf ist Absicht: `=>`
    // gäbe die entfernte Future zurück, `whenComplete` wartete auf sich
    // selbst, und jede Kachel hinge für immer.
    final bytes = await (_inFlight[id] ??=
        source.fetch(z, x, y).whenComplete(() {
      _inFlight.remove(id);
    }));
    if (bytes == null) {
      _missing.add(id);
      return null;
    }
    if (source.remote) _remember(id, bytes);
    return (bytes: bytes, gzip: source.gzip);
  }

  void _remember(String id, Uint8List bytes) {
    if (bytes.length > maxCacheBytes || _cache.containsKey(id)) return;
    _cache[id] = bytes;
    _cacheBytes += bytes.length;
    while (_cacheBytes > maxCacheBytes) {
      final oldest = _cache.keys.first;
      _cacheBytes -= _cache.remove(oldest)!.length;
    }
  }

  static (String, int, int, int)? _parse(String url) {
    const prefix = '$kAppTileScheme://';
    if (!url.startsWith(prefix)) return null;
    final parts = url.substring(prefix.length).split('/');
    if (parts.length != 4) return null;
    final z = int.tryParse(parts[1]);
    final x = int.tryParse(parts[2]);
    final y = int.tryParse(parts[3]);
    if (z == null || x == null || y == null) return null;
    return (Uri.decodeComponent(parts[0]), z, x, y);
  }
}
