// MapLibre GL JS im Browser — Schalter und Lader (#689, Hebel C).
//
// Seit 1.225.0 die VORGABE im Browser (Betreiber 2026-10-17, nach
// Messung am Prüfstand und auf dem Pixel XL). `?maplibre=0` in der Adresse
// wählt flutter_map und wird gemerkt (`?maplibre=1` nimmt es zurück) — der
// Notausgang, und weiter der Weg, beide Engines im selben Build zu messen.
// Warum und was gemessen wurde: #689, `docs/map-performance.md`.
//
// Der Web-Weg ist die Vorgabe, `dart.library.io` wählt den Stub — wie bei
// `browser_storage.dart`.
export 'maplibre_web_browser.dart'
    if (dart.library.io) 'maplibre_web_stub.dart';
