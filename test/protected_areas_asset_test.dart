// Das ECHTE Schutzgebiets-Asset (#580) — lädt es, und stimmt es an
// Stellen, deren Antwort feststeht?
//
// Warum ein eigener Test: Der Lader macht aus jedem Fehler still „keine
// Schutzgebiete" (`protected_area_providers.dart`). Das ist für die
// Karte die richtige Reaktion, aber ein kaputtes Asset sähe dann aus wie
// „hier ist keins" — und genau das soll in CI auffallen, nicht im Wald.
//
// Die Stichproben sind dieselben, mit denen das Asset vor dem Commit
// geprüft wurde (`python3 tool/protected_areas.py lookup`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/protected_areas.dart';

void main() {
  late ProtectedAreas areas;

  setUpAll(() {
    areas = ProtectedAreas.decode(
        File('assets/protected/protected_grid.bin.gz').readAsBytesSync(),
        File('assets/protected/protected_manifest.json').readAsStringSync());
  });

  test('das Asset liegt auf dem Raster des Waldgitters', () {
    // Sonst schlügen Schraffur (je Waldwabe) und Hinweis verschiedene
    // Waben nach — dieselbe Falle, vor der das Werkzeug beim Bauen warnt.
    final forest = File('assets/forest/forest_manifest.json')
        .readAsStringSync();
    expect(forest, contains('"width": ${areas.width}'));
    expect(forest, contains('"height": ${areas.height}'));
    expect(areas.areas.length, greaterThan(9000),
        reason: 'der erste DACH-Lauf hatte 9 877 Gebiete');
  });

  test('bekannte Schutzgebiete warnen', () {
    void warns(double lat, double lon, ProtectedKind kind, String name) {
      final area = areas.areaAt(lat, lon);
      expect(area, isNotNull, reason: '$name fehlt');
      expect(area!.kind, kind, reason: name);
      expect(area.label, contains(name));
    }

    warns(47.8436, 8.3540, ProtectedKind.natureReserve, 'Wutachschlucht');
    warns(48.5630, 8.2320, ProtectedKind.coreZone, 'Nationalpark Schwarzwald');
    warns(48.9770, 13.3930, ProtectedKind.nationalPark, 'Bayerischer Wald');
    warns(48.1800, 16.5200, ProtectedKind.nationalPark, 'Donau-Auen');
    warns(46.6600, 10.2000, ProtectedKind.nationalPark,
        'Schweizerischer Nationalpark');
  });

  test('wo Sammeln erlaubt ist, schweigt es', () {
    // Naturpark Thal (Regionalpark, in OSM als nature_reserve erfasst),
    // Dobratsch (Naturpark mit Nationalpark-Titel in OSM), München.
    expect(areas.areaAt(47.3350, 7.6400), isNull, reason: 'Naturpark Thal');
    expect(areas.areaAt(46.6400, 13.7200), isNull, reason: 'Dobratsch');
    expect(areas.areaAt(48.1370, 11.5750), isNull, reason: 'München');
  });
}
