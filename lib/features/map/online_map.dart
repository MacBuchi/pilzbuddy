// Die Online-Karte vom eigenen Kartenhost (#630, Stufe 1): EIN
// PMTiles-Archiv von DACH (Protomaps-Basiskarte, Zoom 0–13, ODbL) auf
// Cloudflare R2 hinter `tiles.mcbuchi.de`. Geschnitten, geprüft und
// hochgeladen wird es von TrailBuddys `map-data.yml` — PilzBuddy liest
// DASSELBE Archiv mit (Betreiber, 2026-09-30: gleiche Kacheln, und zwei
// Archive lägen über dem Freikontingent des Speichers).
//
// Solange das eine Vorschau ist, steht es hinter einem Schalter
// ([newMapEnabledProvider], ab Werk aus), und das OSM-Raster bleibt der
// Rückfall: Geht irgendetwas auf dem Weg schief — Manifest nicht da, nicht
// lesbar, Archiv nicht erreichbar —, zeichnet die Karte genau das, was sie
// ohne Schalter zeichnet. Die Regel steht an EINER Stelle
// ([onlineMapProvider]); beide Engines fragen nur „gibt es eine?".
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileProviders;

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../offline_maps/offline_map_providers.dart';
import '../offline_maps/pmtiles_tile_provider.dart';

/// Der Kartenhost. Das Präfix gehört TrailBuddy — dort wird geschnitten,
/// hier nur gelesen. Bewusst eine Konstante und keine Konfiguration: Die
/// Adresse ist öffentlich, steht in der Datenschutzerklärung, und
/// `test/privacy_policy_test.dart` liest sie aus `lib/`.
const kMapTilesBase = 'https://tiles.mcbuchi.de/trailbuddy';

/// Das Manifest nennt die AKTUELLE Archivdatei (`dach-<build>.pmtiles`).
/// Der Umweg ist Absicht: Eine Sitzung merkt sich die Verzeichnisse des
/// Archivs, und ein Archiv, das unter ihr überschrieben würde, ließe diese
/// Versätze in eine andere Datei zeigen. Dateien mit Datum im Namen sind
/// unveränderlich; nur der Zeiger wechselt.
const kMapManifestUrl = '$kMapTilesBase/dach.json';

/// Das Manifest des Kartenhosts (`dach.json`): welche Datei gerade gilt
/// und bis zu welchem Zoom sie reicht.
///
/// **Die Datei schreibt ein ANDERES Repo** (TrailBuddy). Was hier nicht
/// passt, wirft — und ein Wurf heißt Rückfall auf OSM, nie eine kaputte
/// Karte. `test/online_map_test.dart` hält die heutige Form fest; ändert
/// TrailBuddy sie, wird die Vorschau still zur alten Karte statt still
/// falsch.
class MapManifest {
  const MapManifest({
    required this.file,
    required this.maxZoom,
    required this.sourceBuild,
  });

  final String file;
  final int maxZoom;

  /// Das Datum des Protomaps-Baus (`JJJJMMTT`) — der Kartenstand.
  final String sourceBuild;

  Uri get archiveUri => Uri.parse('$kMapTilesBase/$file');

  /// Der Dateiname wird geprüft, weil er zu einem Pfad wird.
  factory MapManifest.fromJson(Map<String, dynamic> j) {
    final file = j['file'];
    if (file is! String || !RegExp(r'^dach-\d{8}\.pmtiles$').hasMatch(file)) {
      throw FormatException('Unerwarteter Archivname: $file');
    }
    final maxZoom = j['maxzoom'];
    if (maxZoom is! int || maxZoom < 8 || maxZoom > 16) {
      throw FormatException('Unerwarteter Zoom: $maxZoom');
    }
    return MapManifest(
      file: file,
      maxZoom: maxZoom,
      sourceBuild: j['source_build'] as String,
    );
  }
}

/// Holt das Manifest vom Host — die Naht, die Tests ersetzen (kein Netz).
Future<MapManifest> fetchMapManifest() async {
  final response = await http
      .get(Uri.parse(kMapManifestUrl))
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw http.ClientException('Kartenmanifest: HTTP ${response.statusCode}');
  }
  return MapManifest.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>);
}

final mapManifestLoaderProvider =
    Provider<Future<MapManifest> Function()>((ref) => fetchMapManifest);

/// Öffnet das Archiv über Range-Anfragen — die zweite Naht für Tests.
final onlineArchiveOpenerProvider =
    Provider<Future<PmTilesVectorTileProvider> Function(Uri)>(
        (ref) => PmTilesVectorTileProvider.openUri);

/// Der Schalter „Neue Karte" — ab Werk an seit 1.217.0 (#630, Stufe 3),
/// davor eine Vorschau. Muster
/// `AmpelBannerEnabledNotifier`: Zustand springt sofort, Speichern läuft
/// nach, ein Fehler beim Merken wird nur protokolliert.
class NewMapEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).newMapEnabled;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setNewMapEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Kartenwahl merken', e, stackTrace);
    }));
  }
}

final newMapEnabledProvider =
    NotifierProvider<NewMapEnabledNotifier, bool>(NewMapEnabledNotifier.new);

/// Darf die OSM-Karte als Rückfall zeichnen? NICHT, wenn die Neue Karte
/// gewählt ist und kein Empfang besteht (Feldbefund 1.216.0, PWA im
/// Flugmodus: „die alte Online-Karte hat sich teils geladen").
///
/// Ohne Empfang fällt die Neue Karte weg (`onlineMapProvider` ⇒ null),
/// und bis hierher hieß null überall „OSM wie bisher". Offline liefert
/// OSM aber nicht NICHTS, wie #118 annahm: Der Browser (und auf Android
/// der Platten-Cache) gibt einzelne alte Kacheln heraus — ein
/// Flickenteppich im fremden Stil über der Übersicht und neben den
/// gespeicherten Bereichen, genau die Mischung, die #137 verbietet. Wer
/// die Neue Karte gewählt hat, bekommt ohne Empfang deshalb nur, was im
/// eigenen Stil vorliegt: Übersicht und Bereiche. Mit Empfang bleibt OSM
/// der Rückfall für einen unerreichbaren Host. Beide Engines lesen diese
/// eine Regel.
final osmFallbackAllowedProvider = Provider<bool>((ref) =>
    !(ref.watch(newMapEnabledProvider) && ref.watch(noConnectivityProvider)));

/// Die Online-Karte vom Host: Manifest plus GEÖFFNETES Archiv.
class OnlineMap {
  const OnlineMap({required this.manifest, required this.tiles});

  final MapManifest manifest;

  /// Das Archiv für die flutter_map-Engine. MapLibre liest selbst per
  /// `pmtiles://https://…` und braucht nur [manifest] — geöffnet wird es
  /// trotzdem auch dort, siehe [onlineMapProvider].
  final PmTilesVectorTileProvider tiles;
}

/// Die Online-Karte — oder null, und null heißt überall: OSM wie bisher.
///
/// Null ist sie, wenn der Schalter aus ist (dann wird der Host NIE
/// gefragt), kein Empfang besteht (dann gibt es ohnehin keine
/// Online-Kachel), oder irgendein Schritt scheitert.
///
/// **Das Archiv wird auch für MapLibre geöffnet, obwohl MapLibre es selbst
/// liest.** Nur so ist „erreichbar" geprüft: Ein Manifest, das kommt,
/// während das Archiv mit 403 antwortet (Cloudflares Bot-Abwehr stellte
/// genau so eine Challenge, TrailBuddy #55), ließe MapLibre leere Kacheln
/// zeichnen — ohne Rückfall. Das Öffnen kostet Header und
/// Wurzelverzeichnis, eine Anfrage je Sitzung.
///
/// Ein Fehler wird nur gemeldet, wenn er nicht nach Funkloch aussieht —
/// sonst füllte jeder Wald den Wochendigest.
final onlineMapProvider = FutureProvider<OnlineMap?>((ref) async {
  if (!ref.watch(newMapEnabledProvider)) return null;
  if (ref.watch(noConnectivityProvider)) return null;
  try {
    final manifest = await ref.watch(mapManifestLoaderProvider)();
    // Mit Grenze: MapLibre wartet mit dem Style auf diese Antwort, und
    // ein Netz, das Verbindungen annimmt und nie antwortet, gibt es im
    // Wald wirklich (Feldbefund zum Service Worker, 1.204.2).
    final tiles = await ref
        .watch(onlineArchiveOpenerProvider)(manifest.archiveUri)
        .timeout(const Duration(seconds: 10));
    ref.onDispose(tiles.close);
    return OnlineMap(manifest: manifest, tiles: tiles);
  } catch (e, s) {
    if (!looksOffline(e)) logError('Online-Karte vom Kartenhost', e, s);
    return null;
  }
});

/// Die Online-Karte für die flutter_map-Engine: Archiv plus das Thema
/// OHNE `background`-Ebene, damit die Übersicht darunter durchscheint, wo
/// eine Kachel noch fehlt. Beide sind derselbe Kartenstil — die Regel
/// „Übersicht nie unter Online-Kacheln" (#137) galt zwei VERSCHIEDENEN
/// Stilen nebeneinander und trifft hier nicht zu.
final onlineMapStyleProvider = FutureProvider<OfflineMapStyle?>((ref) async {
  final online = await ref.watch(onlineMapProvider.future);
  if (online == null) return null;
  try {
    final theme =
        await ref.watch(offlineThemeWithoutBackgroundProvider.future);
    return OfflineMapStyle(
      theme: theme,
      tileProviders: TileProviders({'protomaps': online.tiles}),
    );
  } catch (e, s) {
    logError('Online-Karte: Thema laden', e, s);
    return null;
  }
});
