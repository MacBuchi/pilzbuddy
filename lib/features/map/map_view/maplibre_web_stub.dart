// Außerhalb des Browsers: Die Engine-Wahl fragt den Schalter nie
// (`!kIsWeb` entscheidet vorher), und MapLibre native braucht keinen
// Lader.
import '../app_tile_protocol.dart' show AppTile;

/// Siehe `maplibre_web_browser.dart`.
bool webMapLibreRequested() => false;

/// Siehe `maplibre_web_browser.dart`.
Future<bool> loadMapLibreJs() async => true;

/// Siehe `maplibre_web_browser.dart`.
void setMapLibrePointerEvents(bool enabled) {}

/// Siehe `maplibre_web_browser.dart`. Außerhalb des Browsers liefert der
/// Kachel-Server auf Loopback (#659).
bool registerAppTileProtocol(Future<AppTile?> Function(String url) load) =>
    false;
