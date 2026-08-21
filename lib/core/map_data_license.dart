import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Der OFL-Wortlaut der Kartenschrift. Muss in `pubspec.yaml` als Asset
/// stehen — ein Verzeichnis-Eintrag wie `assets/map_glyphs/noto-sans-regular/`
/// nimmt die Datei NICHT mit, sie liegt eine Ebene höher.
/// `test/flows/license_flow_test.dart` wacht über beides.
const notoSansLicenseAsset = 'assets/map_glyphs/OFL.txt';

/// Mitgeliefertes ist keine pub-Abhängigkeit — Flutter sammelt für die
/// Lizenzseite nur die LICENSE-Dateien der Pakete ein. ODbL, die
/// Protomaps-Basemap, die GBIF-Funddaten, die DWD-Regendaten und die
/// Kartenschrift tauchen dort also nur auf, wenn wir sie selbst eintragen.
/// Bei den Karten steht dasselbe schon an der Karte
/// (`RichAttributionWidget`) und im Offline-Karten-Screen; hier landet es
/// zusätzlich an der Stelle, an der ein Nutzer Lizenzen erwartet.
///
/// **Jede neue mitgelieferte Quelle gehört hierher** — die Namensnennung
/// ist bei CC-BY-Daten keine Höflichkeit, sondern die Bedingung, unter der
/// wir sie überhaupt ausliefern dürfen. Dasselbe gilt für Software-Lizenzen
/// wie BSD-3-Clause und die OFL: Sie verlangen den Copyright-Vermerk bzw.
/// den vollen Lizenztext beim ausgelieferten Werk.
///
/// Bis 1.61.1 fehlten hier drei Dinge, und die Schrift war der ernste Fall:
/// Die Glyphen unter `assets/map_glyphs/` sind aus Noto Sans erzeugt, ihr
/// OFL-Text lag zwar im Repo, war aber nicht einmal als Asset deklariert —
/// er erreichte also niemanden. Genau dagegen steht jetzt der Wächter in
/// `test/flows/license_flow_test.dart`.
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
      'https://protomaps.com\n\n'
      'Der mitgelieferte Kartenstil ist mit @protomaps/basemaps erzeugt. '
      'Das ist Software, keine Daten — sie steht unter der BSD-3-Clause- '
      'Lizenz, und deren Bedingung ist die Weitergabe des '
      'Copyright-Vermerks:\n'
      'Copyright (c) 2021 Protomaps LLC\n'
      'Weitergabe in Quell- und Binärform, mit oder ohne Änderung, ist '
      'erlaubt, sofern der Copyright-Vermerk, diese Bedingungen und der '
      'Haftungsausschluss erhalten bleiben und weder Name noch Mitwirkende '
      'ohne vorherige schriftliche Erlaubnis zur Bewerbung abgeleiteter '
      'Produkte verwendet werden. Die Software wird ohne Mängelgewähr '
      'bereitgestellt.',
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
    yield const LicenseEntryWithLineBreaks(
      ['Regendaten (Deutscher Wetterdienst)'],
      'Die Regenradar- und Niederschlagssummen-Ebenen der Karte und die '
      'Regenmenge am Spot beruhen auf RADOLAN-Produkten des Deutschen '
      'Wetterdienstes.\n'
      'Datenbasis: Deutscher Wetterdienst, eigene Darstellung und '
      'Aufbereitung.\n'
      'https://www.dwd.de\n\n'
      'Die Daten stehen unter der Datenlizenz Deutschland – Namensnennung '
      '– Version 2.0; die Namensnennung ist die Bedingung, unter der wir '
      'sie zeigen dürfen.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Waldtypen (Copernicus Land Monitoring Service)'],
      'Die Waldtypen-Ebene der Karte und die „Wald hier"-Zeile im '
      'Spot-Blatt beruhen auf dem Produkt „High Resolution Layer '
      'Dominant Leaf Type" des Copernicus Land Monitoring Service, '
      'zusammengefasst auf ein Wabengitter (≈ 250 m, nachladbar ≈ 100 m) '
      'für Deutschland, Österreich '
      'und die Schweiz.\n'
      '© Europäische Union, Copernicus Land Monitoring Service, '
      'Europäische Umweltagentur (EEA).\n'
      'https://land.copernicus.eu\n\n'
      'Die Copernicus-Daten stehen unter der Politik des freien, '
      'vollständigen und offenen Zugangs der EU; die Quellennennung ist '
      'die Bedingung ihrer Nutzung.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Baumarten (DLR)'],
      'Die Baumarten-Zeile im Spot-Blatt beruht auf dem Produkt '
      '„Tree Species Germany" (Stand 2022) des Earth Observation Center '
      'im Deutschen Zentrum für Luft- und Raumfahrt, zusammengefasst auf '
      'dasselbe Wabengitter wie die Waldtypen (≈ 250 m). Die Abdeckung '
      'ist Deutschland; in Österreich und der Schweiz gibt es die Zeile '
      'deshalb nicht.\n'
      '© DLR, Tree Species Germany.\n'
      'https://geoservice.dlr.de/web/maps/eoc:tcde:2022\n\n'
      'Das Produkt steht unter CC BY 4.0 — die Namensnennung ist die '
      'Bedingung, unter der wir es zeigen dürfen.\n'
      'https://creativecommons.org/licenses/by/4.0/',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Geländehöhen (Copernicus DEM)'],
      'Die Höhenumrechnung der Pilzwetter-Temperatur und die '
      'Höhenlinien-Ebene der Karte beruhen auf dem Copernicus DEM '
      'GLO-90, zusammengefasst auf dasselbe Wabengitter wie die '
      'Waldtypen (≈ 250 m, mittlere Geländehöhe je Wabe).\n'
      '© DLR e.V. 2010–2014 und © Airbus Defence and Space GmbH '
      '2014–2018, bereitgestellt unter COPERNICUS durch die Europäische '
      'Union und die ESA.\n'
      'https://dataspace.copernicus.eu\n\n'
      'Die Nutzung ist frei; die Nennung der Rechteinhaber ist die '
      'Bedingung, unter der die Daten weitergegeben werden dürfen.',
    );
    // Keine Lizenzpflicht, sondern wissenschaftliche Redlichkeit: Die
    // Pilzwetter-Konstanten sind übernommen, nicht erfunden — und die
    // Lizenzseite ist der Ort, an dem die App ohnehin sagt, woher ihre
    // Inhalte stammen (Betreiber, 2026-08-15). Die Kurzform steht an
    // der Ampel-Zeile selbst (`ampel_section.dart`).
    yield const LicenseEntryWithLineBreaks(
      ['Pilzwetter-Formel (wissenschaftliche Quelle)'],
      'Die Formel hinter dem Pilzwetter — Fruchtungsgipfel bei etwa '
      '13 °C Mitteltemperatur über 20 Tage, linear steigender Nutzen '
      'des über 26 Tage kumulierten Niederschlags — folgt einer '
      'Langzeitstudie mit zehn Jahren nahezu täglicher '
      'Steinpilz-Erfassung in einem Buchenwald bei Bielefeld:\n\n'
      'Brejon Lamartiniere & Hoffman (2025), bioRxiv-Preprint.\n'
      'https://doi.org/10.64898/2025.12.12.693895\n\n'
      'Ehrlichkeitsvermerk: Ein Preprint (nicht begutachtet), ein '
      'Standort, eine Art. Wir haben die Formel deshalb selbst '
      'gegengeprüft — an je 2000 Paaren aus echten Fundmeldungen und '
      'Vergleichstagen am selben Ort: An Fundtagen steht sie '
      'verlässlich höher. Ob sie je Art unterschiedlich wirkt, ist '
      'offen; deshalb rechnet sie für alle geprüften Arten gleich.\n\n'
      'Die Wetterdaten dazu liefert der Deutsche Wetterdienst '
      '(eigener Eintrag oben).',
    );
    // Als einziger Eintrag nicht `const`: Die OFL verlangt die Weitergabe
    // ihres WORTLAUTS, nicht nur einen Verweis — also wird die
    // mitgelieferte Datei gelesen statt der Text hier nachgetippt. Sonst
    // driften Kopie und Original auseinander, sobald die Schrift wechselt.
    yield LicenseEntryWithLineBreaks(
      const ['Kartenschrift (Noto Sans)'],
      await rootBundle.loadString(notoSansLicenseAsset),
    );
  });
}
