# MapLibre GL JS und PMTiles — selbst gehostet (#689, Hebel C)

Die Web-Karte kann versuchsweise mit MapLibre GL JS zeichnen statt mit
flutter_map (`?maplibre=1`, siehe `lib/features/map/CLAUDE.md`). Das
Paket `maplibre` erwartet dafür die globalen Objekte `maplibregl` und
`pmtiles`; geladen werden sie erst, wenn die Engine gewählt ist
(`maplibre_web_browser.dart`), nie beim Start.

**Selbst gehostet, nie von einem CDN**: Ein CDN wäre ein neues Netzziel
(Datenschutzerklärung, `test/privacy_policy_test.dart`), und offline
gäbe es die Karte nicht.

Unverändert aus den npm-Paketen (`dist/`):

| Datei | Paket | SHA-256 |
|---|---|---|
| `maplibre-gl.js` | maplibre-gl 5.24.0 | `45a9b07a9189ce56054c620a947ccf41e291e58c95e9b61533b740aaa65ee5cb` |
| `maplibre-gl.css` | maplibre-gl 5.24.0 | `ab1e70d59ec40465bae7e7030da2f3ccf28133fd502e62bd598eefbadfd7a732` |
| `pmtiles.js` | pmtiles 4.5.0 | `caf981bc46f6327ee7e65d5dc964d89d38a69f60edca2bd4c5c890c21b554c6c` |

Beide BSD-3-Clause (`LICENSE-*.txt`). `maplibre` 0.3.5 ist gegen GL JS 5
gebaut — ein Sprung auf 6 nur mit dem Paket zusammen.
