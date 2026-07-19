// Unit-Tests für das Parsing des Karten-Katalogs (Asset-Namensschema
// der Quelle: <key>_<JJJJMMTT>.pmtiles).
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/region_catalog.dart';

void main() {
  group('parseMapAssetName', () {
    test('zerlegt Bundesland-Assets in Key und Datum', () {
      final parsed = parseMapAssetName('de_bayern_20260320.pmtiles');
      expect(parsed?.key, 'de_bayern');
      expect(parsed?.dateStamp, '20260320');
    });

    test('funktioniert auch für Nicht-DE-Regionen', () {
      final parsed = parseMapAssetName('austria_20260320.pmtiles');
      expect(parsed?.key, 'austria');
      expect(parsed?.dateStamp, '20260320');
    });

    test('ignoriert Dateien außerhalb des Schemas', () {
      expect(parseMapAssetName('readme.md'), isNull);
      expect(parseMapAssetName('de_bayern.pmtiles'), isNull);
      expect(parseMapAssetName('de_bayern_2026032.pmtiles'), isNull);
    });
  });

  group('regionLabel', () {
    test('kennt deutsche Namen mit Umlauten', () {
      expect(regionLabel('de_thueringen'), 'Thüringen');
      expect(regionLabel('de_baden_wuerttemberg'), 'Baden-Württemberg');
      expect(regionLabel('austria'), 'Österreich');
    });

    test('fällt bei unbekannten Keys auf generierten Namen zurück', () {
      expect(regionLabel('croatia'), 'Croatia');
      expect(regionLabel('france_nw'), 'France Nw');
    });
  });

  test('compareRegionKeys sortiert deutsche Regionen zuerst', () {
    final keys = ['austria', 'de_berlin', 'switzerland', 'de_bayern'];
    keys.sort(compareRegionKeys);
    expect(keys, ['de_bayern', 'de_berlin', 'austria', 'switzerland']);
  });

  test('formatDateStamp formatiert lesbar', () {
    expect(formatDateStamp('20260320'), '20.3.2026');
    expect(formatDateStamp('kaputt'), 'kaputt');
  });
}
