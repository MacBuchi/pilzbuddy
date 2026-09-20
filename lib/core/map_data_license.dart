import 'dart:convert';

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
      'Zwei Dinge in dieser App kommen aus Beobachtungsdaten der Global '
      'Biodiversity Information Facility: die Saisonkurven („Wann diese '
      'Art gemeldet wird", aggregiert zu zwölf Monatswerten je Art) und '
      'die Kartenebene „Gemeldete Fundorte" — dort liegen die einzelnen '
      'Meldungen unserer Arten als Scheiben in der Genauigkeit, die der '
      'Melder angegeben hat, für Deutschland, Österreich und die '
      'Schweiz. Namen der Melder werden nicht mitgeliefert.\n'
      'https://www.gbif.org\n\n'
      'Berücksichtigt werden ausschließlich Datensätze unter CC0 1.0 und '
      'CC BY 4.0; die nicht-kommerziell lizenzierten bleiben bewusst '
      'draußen.\n'
      'https://creativecommons.org/publicdomain/zero/1.0/\n'
      'https://creativecommons.org/licenses/by/4.0/\n\n'
      'Die Fundorte stammen aus dem GBIF-Download '
      'https://doi.org/10.15468/dl.dwbsuf (Stand 16. September 2026). '
      'Die Quell-Datensätze mit ihrem Anteil stehen im nächsten '
      'Eintrag.',
    );
    // Die Namensnennung je Quell-Datensatz — CC-BY-Pflicht. Aus dem
    // Manifest des Assets, damit sie beim nächsten Download von selbst
    // mitzieht statt hier zu veralten; ohne Asset bleibt der Eintrag
    // schlicht weg.
    final datasets = await _gbifDatasetLines();
    if (datasets != null) {
      yield LicenseEntryWithLineBreaks(
        const ['Funddaten (GBIF) — Quell-Datensätze'],
        'Die Kartenebene „Gemeldete Fundorte" enthält Meldungen aus '
        'diesen Datensätzen (CC0 1.0 oder CC BY 4.0), mit der Zahl der '
        'übernommenen Meldungen:\n\n$datasets',
      );
    }
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
      'verlässlich höher. Seit 1.137.0 rechnet sie je Pilzgruppe: Das '
      'eigene Temperaturfenster des Pfifferlings ist an '
      'österreichischen und schweizerischen Meldungen gegengeprüft, die '
      'an seiner Bestimmung nicht beteiligt waren; seit September 2026 '
      'steht es etwas kühler (14,5 °C), eine bewusste Anpassung, die '
      'diesen Nachweis noch nicht hat.\n\n'
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

/// Eine Zeile je Quell-Datensatz aus `assets/gbif/gbif_finds_manifest.json`,
/// die größten zuerst — oder `null`, wenn das Asset fehlt oder nicht
/// lesbar ist.
Future<String?> _gbifDatasetLines() async {
  try {
    final raw =
        await rootBundle.loadString('assets/gbif/gbif_finds_manifest.json');
    final manifest = jsonDecode(raw) as Map<String, dynamic>;
    final datasets = (manifest['datasets'] as List).cast<Map<String, dynamic>>();
    if (datasets.isEmpty) return null;
    return [
      for (final d in datasets)
        '${d['title']} — ${d['observations']} Meldungen',
    ].join('\n');
  } catch (_) {
    // Kein Asset, kein Eintrag — die Lizenzseite ist kein Ort für eine
    // Fehlermeldung über ein fehlendes Asset.
    return null;
  }
}
