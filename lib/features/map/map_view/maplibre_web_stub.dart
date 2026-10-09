// Außerhalb des Browsers: Die Engine-Wahl fragt den Schalter nie
// (`!kIsWeb` entscheidet vorher), und MapLibre native braucht keinen
// Lader.

/// Siehe `maplibre_web_browser.dart`.
bool webMapLibreRequested() => false;

/// Siehe `maplibre_web_browser.dart`.
Future<bool> loadMapLibreJs() async => true;

/// Siehe `maplibre_web_browser.dart`.
void setMapLibrePointerEvents(bool enabled) {}
