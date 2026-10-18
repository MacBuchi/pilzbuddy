// Die Engine-Wahl im Browser als reine Rechnung (#689) — ohne
// `localStorage` und `Uri.base`, damit die Dart-VM sie prüfen kann. Die
// Browser-Datei liest und schreibt nur noch.

/// Was nach dem Parameter `?maplibre=` gemerkt wird: `'0'` heißt
/// flutter_map, nichts heißt Vorgabe. `?maplibre=1` löscht also den
/// Ausstieg, statt eine `'1'` zu schreiben.
String? storedMapLibreChoice(String? param, String? stored) => switch (param) {
      '0' => '0',
      '1' => null,
      _ => stored,
    };

/// MapLibre GL JS, außer der Browser hat ausdrücklich abgewählt. Ein
/// `'1'` aus der Versuchszeit (1.224.6–1.224.9) heißt dasselbe wie die
/// Vorgabe.
bool mapLibreChosen(String? stored) => stored != '0';
