// Die Kacheln der Neuen Karte kommen über die App, nicht direkt aus
// MapLibre (#659).
//
// maplibre-native liest ein entferntes PMTiles-Archiv (`pmtiles://https://…`)
// ohne jeden Zwischenspeicher. Gemessen am 2026-10-02 über einen Zähl-Proxy
// (#630, #658): vor JEDER Kachel ein Abruf des 127-Byte-Headers, dasselbe
// Wurzelverzeichnis fünfmal, jede Kachel zwei- bis dreimal, und nach dem
// Neustart alles noch einmal — 50 Anfragen je Kaltstart, davon 14
// verschieden, ~6 je neuer Kachel. Jede davon ist eine bezahlte
// R2-Operation (`cf-cache-status: DYNAMIC`, das Archiv ist zu groß für den
// Edge-Cache), und ein Start sind 50 Anfragen in vier Sekunden von einer
// IP — genau das, was eine Ratenbremse am Host (TrailBuddy #55) sieht.
//
// Deshalb ein kleiner Server NUR auf Loopback, der MapLibre eine gewöhnliche
// Kachel-Vorlage gibt und aus dem Archiv liefert, das `onlineMapProvider`
// ohnehin öffnet. `PmTilesArchive` hält Header und Verzeichnisse im
// Speicher; hier kommen dazu:
//
// - **Jede Kachel einmal unterwegs** (`_inFlight`): Fragt MapLibre dieselbe
//   Kachel zweimal, bevor die erste Antwort da ist, geht EIN Abruf hinaus.
// - **Jede Kachel einmal überhaupt** (`BoundedFileCache`, 64 MB im
//   Cache-Verzeichnis des Systems): Archivdateien tragen das Datum im
//   Namen und sind unveränderlich, eine abgelegte Kachel braucht also nie
//   eine Nachfrage. Ein neuer Stand bekommt neue Schlüssel; die alten
//   altern über die Größengrenze hinaus. Das System sichert dieses
//   Verzeichnis nie und darf es bei Platzmangel räumen — für etwas
//   jederzeit Nachladbares genau richtig.
// - **Eine fehlende Kachel einmal** (`_missing`): Das Archiv hat Lücken
//   (Meer, außerhalb von DACH); MapLibre fragte sonst bei jedem Schwenk neu.
//
// Ausgeliefert werden die Bytes, wie sie im Archiv liegen (gzip), mit
// `Content-Encoding` — kein Entpacken im Main-Isolate. Der Server läuft
// bewusst dort: Er wartet nur auf Ein- und Ausgabe, und ein eigenes Isolate
// wäre ein weiterer Mutator in der Gruppe, an der der ANR aus #641 hing.
//
// Nur Android: Im Browser zeichnet flutter_map, und das liest das Archiv
// ohnehin in Dart (`PmTilesVectorTileProvider`).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import '../../data/file_cache.dart';
import 'online_map.dart';

/// Holt eine Kachel UNentpackt aus dem Archiv; `null` heißt: keine da.
typedef RawTileFetch = Future<Uint8List?> Function(int z, int x, int y);

/// Höchstbelegung des Kachelspeichers. Eine Kachel der DACH-Karte wiegt
/// 10–280 KB (gemessen #630), das sind einige hundert bis tausend Kacheln —
/// mehr als die Gegend, in der man sich gewöhnlich bewegt.
const kTileCacheMaxBytes = 64 * 1024 * 1024;

class OnlineTileServer {
  OnlineTileServer({required BoundedFileCache cache}) : _cache = cache;

  final BoundedFileCache _cache;
  HttpServer? _server;

  String? _build;
  RawTileFetch? _fetch;
  bool _gzip = true;

  final _inFlight = <String, Future<Uint8List?>>{};
  final _missing = <String>{};

  /// Bindet an einen freien Port auf Loopback. Nie auf allen
  /// Schnittstellen: Die Kacheln sind öffentlich, aber ein offener Port
  /// im WLAN wäre trotzdem einer zu viel.
  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    _server = server;
    server.listen((request) => unawaited(_handle(request)),
        onError: (Object e, StackTrace s) => logError('Kachel-Server', e, s));
  }

  /// Hängt das Archiv eines Stands ein. Ein anderer Stand beginnt ohne
  /// Lücken-Merker; laufende Abrufe des alten laufen aus.
  void attach({
    required String build,
    required RawTileFetch fetch,
    required bool gzip,
  }) {
    if (build != _build) _missing.clear();
    _build = build;
    _fetch = fetch;
    _gzip = gzip;
  }

  /// Die Kachel-Vorlage für den Style. Der Stand steht im Pfad — so fragt
  /// ein Style, der noch auf den alten zeigt, nie Kacheln des neuen ab.
  String urlTemplate(String build) {
    final port = _server?.port;
    if (port == null) throw StateError('Kachel-Server läuft nicht');
    return 'http://127.0.0.1:$port/$build/{z}/{x}/{y}.pbf';
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final tile = _parse(request.uri.pathSegments);
      if (request.method != 'GET' || tile == null || tile.build != _build) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final bytes = await _tile(tile.build, tile.z, tile.x, tile.y);
      if (bytes == null) {
        response.statusCode = HttpStatus.noContent;
        return;
      }
      response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('application', 'x-protobuf')
        // MapLibre soll nicht ein zweites Mal ablegen, was hier schon liegt.
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..contentLength = bytes.length;
      if (_gzip) response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      response.add(bytes);
    } catch (e, s) {
      // Funkloch oder ein Archiv, das gerade ersetzt wird (StateError aus
      // dem geschlossenen Lesepool, vgl. PmTilesVectorTileProvider):
      // „Kachel fehlt gerade", nichts ablegen, nichts melden. Alles andere
      // ist ein Befund.
      if (e is! StateError && !looksOffline(e)) {
        logError('Kachel ausliefern', e, s);
      }
      response.statusCode = HttpStatus.serviceUnavailable;
    } finally {
      await response.close().catchError((_) {
        // MapLibre hat die Anfrage schon verworfen (Kachel aus dem Bild
        // gewandert) — niemand mehr da, dem man antworten könnte.
      });
    }
  }

  Future<Uint8List?> _tile(String build, int z, int x, int y) async {
    final key = '$build/$z/$x/$y';
    if (_missing.contains(key)) return null;
    // Erst die laufenden Abrufe, dann die Platte: Während ein Abruf seine
    // Kachel noch ablegt, steht sie schon als Datei da.
    final running = _inFlight[key];
    if (running != null) return running;
    final cached = await _cache.read(key);
    if (cached != null) return cached;
    return _inFlight[key] ??= _load(key, z, x, y);
  }

  Future<Uint8List?> _load(String key, int z, int x, int y) async {
    final fetch = _fetch;
    if (fetch == null) throw StateError('Kein Archiv eingehängt');
    try {
      final bytes = await fetch(z, x, y);
      if (bytes == null) {
        _missing.add(key);
      } else {
        await _cache.write(key, bytes);
      }
      return bytes;
    } finally {
      unawaited(_inFlight.remove(key));
    }
  }

  static ({String build, int z, int x, int y})? _parse(List<String> path) {
    if (path.length != 4 || !path[3].endsWith('.pbf')) return null;
    final z = int.tryParse(path[1]);
    final x = int.tryParse(path[2]);
    final y = int.tryParse(path[3].substring(0, path[3].length - 4));
    if (z == null || x == null || y == null) return null;
    return (build: path[0], z: z, x: x, y: y);
  }
}

/// Der eine Server der Sitzung — `null` im Browser oder wenn er nicht
/// startet; dann liest MapLibre das Archiv wie bisher selbst.
final onlineTileServerProvider =
    FutureProvider<OnlineTileServer?>((ref) async {
  if (kIsWeb) return null;
  try {
    final server = OnlineTileServer(
      cache: BoundedFileCache(
        dirName: 'map_tile_cache',
        maxBytes: kTileCacheMaxBytes,
        baseDirectory: await getTemporaryDirectory(),
      ),
    );
    await server.start();
    ref.onDispose(server.close);
    return server;
  } catch (e, s) {
    logError('Kachel-Server starten', e, s);
    return null;
  }
});

/// Die Kachel-Vorlage der Neuen Karte für MapLibre — oder `null`, dann
/// bleibt es bei `pmtiles://`. Ob es überhaupt eine Neue Karte gibt,
/// entscheidet weiter allein `onlineMapProvider`.
final onlineTilesUrlProvider = FutureProvider<String?>((ref) async {
  final online = await ref.watch(onlineMapProvider.future);
  if (online == null) return null;
  final server = await ref.watch(onlineTileServerProvider.future);
  if (server == null) return null;
  final build = online.manifest.file.replaceAll('.pmtiles', '');
  server.attach(
    build: build,
    fetch: online.tiles.rawTile,
    gzip: online.tiles.tilesGzipped,
  );
  return server.urlTemplate(build);
});
