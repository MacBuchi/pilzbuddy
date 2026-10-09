// MapLibre GL JS im Browser — Schalter und Lader (#689, Hebel C).
//
// Ein VERSUCH: Ab Werk zeichnet die Web-Karte weiter flutter_map. Mit
// `?maplibre=1` in der Adresse wählt ein Browser MapLibre GL JS und merkt
// sich das (`?maplibre=0` nimmt es zurück). So lassen sich beide Engines
// im selben Build messen und im Feld vergleichen, und ein Merge ändert
// für niemanden etwas. Warum und was gemessen wird: #689,
// `docs/map-performance.md`.
//
// Der Web-Weg ist die Vorgabe, `dart.library.io` wählt den Stub — wie bei
// `browser_storage.dart`.
export 'maplibre_web_browser.dart'
    if (dart.library.io) 'maplibre_web_stub.dart';
