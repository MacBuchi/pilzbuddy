import 'package:flutter/foundation.dart';

/// Mitgelieferte Daten sind keine pub-Abhängigkeit — Flutter sammelt für
/// die Lizenzseite nur die LICENSE-Dateien der Pakete ein. ODbL, die
/// Protomaps-Basemap und die GBIF-Funddaten tauchen dort also nur auf,
/// wenn wir sie selbst eintragen. Bei den Karten steht dasselbe schon an
/// der Karte (`RichAttributionWidget`) und im Offline-Karten-Screen; hier
/// landet es zusätzlich an der Stelle, an der ein Nutzer Lizenzen
/// erwartet.
///
/// **Jede neue mitgelieferte Datenquelle gehört hierher** — die
/// Namensnennung ist bei CC-BY-Daten keine Höflichkeit, sondern die
/// Bedingung, unter der wir sie überhaupt ausliefern dürfen.
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
    yield const LicenseEntryWithLineBreaks(
      ['Funddaten (GBIF)'],
      'Die Saisonkurven („Wann diese Art gemeldet wird") sind aus '
      'Beobachtungsdaten der Global Biodiversity Information Facility '
      'gerechnet — aggregiert zu zwölf Monatswerten je Art, für '
      'Deutschland, Österreich und die Schweiz.\n'
      'https://www.gbif.org\n\n'
      'Berücksichtigt werden ausschließlich Datensätze unter CC0 1.0 und '
      'CC BY 4.0; die nicht-kommerziell lizenzierten bleiben bewusst '
      'draußen.\n'
      'https://creativecommons.org/publicdomain/zero/1.0/\n'
      'https://creativecommons.org/licenses/by/4.0/\n\n'
      'Die Daten stammen von vielen einzelnen Sammlungen und '
      'Meldeportalen, darunter SwissFungi und die Österreichische '
      'Mykologische Gesellschaft.',
    );
  });
}
