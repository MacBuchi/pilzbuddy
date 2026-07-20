import 'package:flutter/foundation.dart';

/// Kartendaten sind keine pub-Abhängigkeit — Flutter sammelt für die
/// Lizenzseite nur die LICENSE-Dateien der Pakete ein. ODbL und die
/// Protomaps-Basemap tauchen dort also nur auf, wenn wir sie selbst
/// eintragen. Inhaltlich steht dasselbe schon an der Karte
/// (`RichAttributionWidget`) und im Offline-Karten-Screen; hier landet es
/// zusätzlich an der Stelle, an der ein Nutzer Lizenzen erwartet.
void registerMapDataLicense() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Kartendaten (OpenStreetMap, Protomaps)'],
      'Die Karten dieser App basieren auf Daten von OpenStreetMap.\n'
      '© OpenStreetMap-Mitwirkende, lizenziert unter der Open Data '
      'Commons Open Database License (ODbL) 1.0.\n'
      'https://www.openstreetmap.org/copyright\n'
      'https://opendatacommons.org/licenses/odbl/1-0/\n\n'
      'Die Offline-Karten sind vorgerenderte PMTiles der Protomaps '
      'Basemap v4, ebenfalls aus OpenStreetMap-Daten und unter ODbL.\n'
      'https://protomaps.com',
    );
  });
}
