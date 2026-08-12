// Lizenz-Compliance: MIT-Datei im Repo, Lizenzseite in der App und die
// Kartendaten-Lizenz, die Flutter von sich aus nicht kennt.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/map_data_license.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Mitgelieferte Fremdinhalte aus der Asset-Liste und der Name, der dafür
/// in `map_data_license.dart` stehen MUSS. Wer hier einträgt, hat
/// entschieden, dass die Lizenz dieser Quelle abgehandelt ist.
const _attributedAssets = <String, String>{
  'assets/map_style/protomaps_light_de.json': 'Protomaps',
  'assets/offline_maps/overview_dach.pmtiles': 'Protomaps',
  'assets/map_glyphs/noto-sans-regular/': 'Noto Sans',
  'assets/map_glyphs/noto-sans-medium/': 'Noto Sans',
  'assets/map_glyphs/OFL.txt': 'Noto Sans',
  'assets/forest/forest_grid.bin.gz': 'Copernicus Land Monitoring Service',
  'assets/forest/forest_manifest.json': 'Copernicus Land Monitoring Service',
  'assets/forest/forest_species.bin.gz': 'DLR',
  'assets/forest/forest_species_manifest.json': 'DLR',
};

/// Eigenerzeugnis — keine fremde Lizenz, nichts zu attribuieren.
const _ownWorkAssets = <String>{'CHANGELOG.md'};

/// Quellen, die in der App stecken und deren Lizenz eine Namensnennung
/// verlangt. Gegenrichtung zur Asset-Liste: Der DWD ist kein Asset (die
/// Regendaten kommen zur Laufzeit), seine Nennung ist trotzdem Pflicht.
const _bundledSources = <String>[
  'OpenStreetMap',
  'Protomaps',
  'GBIF',
  'Deutscher Wetterdienst',
  'Noto Sans',
  'Copernicus Land Monitoring Service',
  'DLR',
];

/// Die Asset-Einträge aus `pubspec.yaml`. Bewusst per Regex statt mit dem
/// `yaml`-Paket: Das ist keine Abhängigkeit dieses Projekts, und für eine
/// Liste, die wir selbst schreiben, lohnt sie nicht.
List<String> _declaredAssets() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final start = lines.indexWhere((l) => l.trimRight() == '  assets:');
  expect(start, isNot(-1), reason: 'assets:-Block fehlt in pubspec.yaml');

  final assets = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final match = RegExp(r'^\s+- (.+)$').firstMatch(line);
    // Erste Zeile, die kein Listeneintrag mehr ist, beendet den Block.
    if (match == null) break;
    assets.add(match.group(1)!.trim());
  }
  expect(assets, isNotEmpty, reason: 'Keine Assets gelesen — Regex kaputt?');
  return assets;
}

void main() {
  // Seit 1.61.1 lädt `registerMapDataLicense()` den OFL-Text über
  // `rootBundle`, und die Registry-Tests unten sind einfache `test()` ohne
  // Widget-Kontext. Das geht trotzdem: `flutter test` initialisiert die
  // Binding in seinem eigenen Bootstrap, bevor irgendein Test läuft — ein
  // `TestWidgetsFlutterBinding.ensureInitialized()` hier wäre wirkungslos.
  // Nachgemessen, nicht angenommen: mit und ohne die Zeile identisch grün.
  test('Das Repo hat eine LICENSE-Datei mit MIT-Text', () {
    // Ohne LICENSE gilt in einem öffentlichen Repo „alle Rechte
    // vorbehalten" — niemand dürfte den Code legal weiterverwenden.
    final license = File('LICENSE');
    expect(license.existsSync(), isTrue, reason: 'LICENSE fehlt');

    final text = license.readAsStringSync();
    expect(text, contains('MIT License'));
    expect(text, contains('Marcus Bucher'));
    // Die Haftungsfreistellung ist der Teil, der bei Copy-Paste gern fehlt.
    expect(text, contains('WITHOUT WARRANTY OF ANY KIND'));
  });

  // Die Registry ist global und ADDIERT bei jedem Aufruf. Ohne das
  // Zurücksetzen fände der zweite Test jeden Eintrag doppelt — und
  // scheiterte an einer Zahl, die mit der Sache nichts zu tun hat.
  setUp(LicenseRegistry.reset);

  test('Kartendaten-Lizenz landet in der LicenseRegistry', () async {
    // Flutter sammelt nur LICENSE-Dateien von pub-Paketen ein; ODbL und
    // Protomaps müssen wir selbst eintragen.
    registerMapDataLicense();

    final entries = await LicenseRegistry.licenses.toList();
    final mapEntry = entries.where(
        (e) => e.packages.any((p) => p.contains('Kartendaten')));
    expect(mapEntry, hasLength(1), reason: 'Kartendaten-Eintrag fehlt');

    final text =
        mapEntry.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('OpenStreetMap'));
    expect(text, contains('ODbL'));
    expect(text, contains('Protomaps'));
  });

  test('GBIF-Funddaten landen in der LicenseRegistry', () async {
    // Die Saisonkurven stehen auf CC-BY-Daten. Namensnennung ist dort
    // die Bedingung, unter der wir sie ausliefern dürfen — und die
    // Lizenzseite ist der Ort, an dem ein Nutzer sie sucht.
    registerMapDataLicense();

    final entries = await LicenseRegistry.licenses.toList();
    final gbif =
        entries.where((e) => e.packages.any((p) => p.contains('GBIF')));
    expect(gbif, hasLength(1), reason: 'GBIF-Eintrag fehlt');

    final text = gbif.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('Global Biodiversity Information Facility'));
    expect(text, contains('CC BY 4.0'));
    // Der Lizenzfilter ist eine bewusste Entscheidung (26 % weniger
    // Daten). Wer ihn im Skript entfernt, muss auch hier vorbeikommen.
    expect(text, contains('nicht-kommerziell'));
  });

  test('Regendaten-Lizenz landet in der LicenseRegistry', () async {
    // Die RADOLAN-Produkte stehen unter der Datenlizenz Deutschland mit
    // Namensnennung. In der Oberfläche steht sie längst (Regen-Blatt und
    // MapLibre-Attribution) — auf der Lizenzseite fehlte sie bis 1.61.1.
    registerMapDataLicense();

    final entries = await LicenseRegistry.licenses.toList();
    final dwd = entries
        .where((e) => e.packages.any((p) => p.contains('Regendaten')));
    expect(dwd, hasLength(1), reason: 'DWD-Eintrag fehlt');

    final text = dwd.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('Deutscher Wetterdienst'));
  });

  test('Der OFL-Wortlaut der Kartenschrift landet in der LicenseRegistry',
      () async {
    // Der Kern des Ganzen: Die Glyphen unter assets/map_glyphs/ sind aus
    // Noto Sans erzeugt, und die OFL verlangt die Weitergabe ihres
    // Lizenztextes beim ausgelieferten Werk. Bis 1.61.1 war die Datei
    // nicht einmal im Bundle — der Text erreichte niemanden.
    registerMapDataLicense();

    final entries = await LicenseRegistry.licenses.toList();
    final font = entries
        .where((e) => e.packages.any((p) => p.contains('Kartenschrift')));
    expect(font, hasLength(1), reason: 'Noto-Sans-Eintrag fehlt');

    final text = font.single.paragraphs.map((p) => p.text).join(' ');
    // Wortlaut, nicht Verweis — sonst ist die Bedingung nicht erfüllt.
    expect(text, contains('SIL OPEN FONT LICENSE'));
    expect(text, contains('Copyright'),
        reason: 'Die OFL nennt den Copyright-Vermerk ausdrücklich als '
            'Bedingung');
  });

  test('Der OFL-Text wird mit ausgeliefert', () {
    // Zwei Hälften, und beide sind nötig. Die Datei auf Platte zu haben
    // nützt nichts, wenn sie nicht im Bundle landet: Die zwei
    // Verzeichnis-Einträge für die Glyphen nehmen sie NICHT mit, weil
    // Flutter dort nur Dateien direkt im Verzeichnis erfasst und OFL.txt
    // eine Ebene höher liegt. Genau das war der Fehler bis 1.61.1.
    final file = File(notoSansLicenseAsset);
    expect(file.existsSync(), isTrue, reason: '$notoSansLicenseAsset fehlt');

    final text = file.readAsStringSync();
    expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(text, contains('Copyright'));

    expect(_declaredAssets(), contains(notoSansLicenseAsset),
        reason: '$notoSansLicenseAsset muss EINZELN in der Asset-Liste von '
            'pubspec.yaml stehen. Ohne den Eintrag liegt der Text nicht im '
            'Bundle, rootBundle.loadString wirft, und die Lizenzseite '
            'bleibt an dieser Stelle leer.');
  });

  test('Kein mitgeliefertes Asset ohne Lizenz-Entscheidung', () {
    // Dieselbe Bauart wie test/privacy_policy_test.dart: Nicht die
    // Lizenzseite auf Vollständigkeit prüfen (das kann kein Test), sondern
    // die Gegenrichtung — taucht in der Asset-Liste etwas auf, das niemand
    // eingeordnet hat, bricht CI.
    final unknown = _declaredAssets().where((a) =>
        !_attributedAssets.containsKey(a) && !_ownWorkAssets.contains(a));

    expect(unknown, isEmpty,
        reason: 'Neues Asset in pubspec.yaml: ${unknown.join(", ")}. '
            'Entscheide, ob es Eigenerzeugnis ist — dann in '
            '_ownWorkAssets eintragen — oder fremdes Material: dann '
            'gehört seine Lizenz nach lib/core/map_data_license.dart und '
            'der Quellenname hier in _attributedAssets. Mitliefern ohne '
            'diese Entscheidung ist der Fehler, den 1.61.1 behoben hat.');
  });

  test('Jede mitgelieferte Quelle steht in map_data_license.dart', () {
    // Gegenstück zur Asset-Prüfung, für die Quellen statt der Dateien —
    // wie das `for (final host in fetched)` am Ende von
    // privacy_policy_test.dart. Fängt den Fall, dass jemand einen Eintrag
    // aus der Registry entfernt, während das Asset liegen bleibt.
    final source = File('lib/core/map_data_license.dart').readAsStringSync();
    for (final name in _bundledSources) {
      expect(source, contains(name),
          reason: '„$name" wird ausgeliefert, aber in '
              'map_data_license.dart nicht mehr genannt. Die '
              'Namensnennung ist die Bedingung, unter der wir die Quelle '
              'verwenden dürfen.');
    }

    // Und die Namen aus der Asset-Zuordnung dürfen nicht danebenlaufen.
    for (final name in _attributedAssets.values.toSet()) {
      expect(_bundledSources, contains(name),
          reason: '„$name" steht in _attributedAssets, aber nicht in '
              '_bundledSources — dann prüft niemand, ob die Quelle in '
              'map_data_license.dart auch wirklich genannt wird.');
    }
  });

  testWidgets('Profil führt zur Lizenzseite', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.text('Profil'));
    await settle(tester);

    // Bis ans Listenende scrollen statt `scrollUntilVisible`: das schiebt
    // den Eintrag nur knapp ins Bild, wo er die untere Navigationsleiste
    // überlappt — der Tap landete dann auf „Freunde".
    for (var i = 0; i < 4; i++) {
      await tester.drag(
          find.byType(Scrollable).first, const Offset(0, -600));
      await settle(tester, frames: 4);
    }
    expect(find.text('Open-Source-Lizenzen'), findsOneWidget);

    await tester.tap(find.text('Open-Source-Lizenzen'));
    await settle(tester, frames: 20);

    // Flutters Lizenzseite zeigt Name und Legalese aus showLicensePage.
    expect(find.text('PilzBuddy'), findsWidgets);
    expect(find.textContaining('MIT-Lizenz'), findsWidgets);
  });
}
