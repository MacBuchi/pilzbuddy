// Die Regenebene baut ihre DWD-Anfrage selbst zusammen — und ein Fehler
// darin ist auf dem Gerät unsichtbar: Der Dienst antwortet dann mit einem
// XML-Fehler, den weder MapLibre noch flutter_map anzeigen. Es bleibt
// einfach leer. Deshalb prüft diese Datei die URL Stück für Stück.
//
// Die Werte darin sind am 2026-08-04 gegen den echten Dienst geprüft
// (GetCapabilities + GetMap), nicht geraten.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';

/// Zerlegt die gebaute URL in ihre Parameter (kleingeschrieben).
Map<String, String> params(String url) => Uri.parse(url).queryParameters;

void main() {
  final now = DateTime.utc(2026, 8, 4, 10, 32);

  test('ohne Ebene gibt es keine Anfrage', () {
    expect(rainLayerUrl(RainLayer.off, now: now), isNull);
    expect(rainLegendUrl(RainLayer.off), isNull);
  });

  test('jede Ebene nennt ihr DWD-Produkt', () {
    expect(params(rainLayerUrl(RainLayer.now, now: now)!)['layers'],
        'dwd:Niederschlagsradar');
    expect(params(rainLayerUrl(RainLayer.inOneHour, now: now)!)['layers'],
        'dwd:Niederschlagsradar');
    expect(params(rainLayerUrl(RainLayer.last24h, now: now)!)['layers'],
        'dwd:SF-Produkt');
    expect(params(rainLayerUrl(RainLayer.last30d, now: now)!)['layers'],
        'dwd:RADOLAN-W4');
  });

  test('GetMap in EPSG:3857 mit Transparenz', () {
    final p = params(rainLayerUrl(RainLayer.now, now: now)!);
    expect(p['service'], 'WMS');
    expect(p['version'], '1.3.0');
    expect(p['request'], 'GetMap');
    expect(p['crs'], 'EPSG:3857',
        reason: 'In EPSG:4326 dreht WMS 1.3.0 die Achsen — das Bild läge '
            'dann quer über der Karte.');
    expect(p['transparent'], 'true',
        reason: 'Ohne Transparenz deckt die Ebene die Karte darunter zu.');
    expect(p['format'], 'image/png');
  });

  group('Ausschnitt', () {
    test('BBOX ist der Ausschnitt der Ebene in Mercator-Metern', () {
      final p = params(rainLayerUrl(RainLayer.now, now: now)!);
      final bbox = p['bbox']!.split(',').map(int.parse).toList();
      // 5,5° O und 17,5° O in EPSG:3857 (nachgerechnet gegen die
      // GetCapabilities-Angabe des Dienstes).
      expect(bbox[0], closeTo(612257, 2));
      expect(bbox[2], closeTo(1948091, 2));
      expect(bbox[1], closeTo(5700583, 2));
      expect(bbox[3], closeTo(7459517, 2));
    });

    test('Bildhöhe folgt dem Mercator-Verhältnis, nicht dem Gradmaß', () {
      // Der Radar-Ausschnitt ist 12° breit und 10° hoch. Wer die Höhe aus
      // den GRADEN ableitet, bekommt 1280 statt rund 2020 Pixel — das Bild
      // stünde gestaucht auf der Karte und der Regen läge zig Kilometer
      // neben dem Ort, an dem er fällt.
      final p = params(rainLayerUrl(RainLayer.now, now: now)!);
      final width = int.parse(p['width']!);
      final height = int.parse(p['height']!);
      final bbox = p['bbox']!.split(',').map(int.parse).toList();
      expect(height / width,
          closeTo((bbox[3] - bbox[1]) / (bbox[2] - bbox[0]), 0.001));
      expect(height, greaterThan(width));
    });

    test('Auflösung bleibt unter der Datenauflösung von 1 km', () {
      // Der ganze Grund für das feste Bild: Es muss feiner sein als das
      // 1-km-Raster des DWD, sonst verliert es Daten und die Entscheidung
      // gegen den mitwandernden Ausschnitt trüge nicht mehr.
      for (final layer in RainLayer.values) {
        final url = rainLayerUrl(layer, now: now);
        if (url == null) continue;
        final p = params(url);
        final bbox = p['bbox']!.split(',').map(int.parse).toList();
        final b = layer.bounds;
        // Mercator-Meter sind am Äquator gedehnt — auf die Ausschnittsmitte
        // zurückrechnen, sonst sieht die Auflösung besser aus, als sie ist.
        final shrink = math.cos((b.south + b.north) / 2 * math.pi / 180);
        final metersPerPixel =
            (bbox[2] - bbox[0]) / int.parse(p['width']!) * shrink;
        expect(metersPerPixel, lessThan(1000),
            reason: '${layer.name} löst mit ${metersPerPixel.round()} m je '
                'Pixel gröber auf als die Daten selbst.');
      }
    });

    test('die Summenprodukte decken Deutschland ab, das Radar den '
        'DACH-Ausschnitt der Übersichtskarte', () {
      expect(RainLayer.last30d.bounds, RainLayer.last24h.bounds);
      expect(RainLayer.now.bounds, RainLayer.inOneHour.bounds);
      // Sylt (55,0 N) und Oberstdorf (47,4 N) müssen drin liegen, sonst
      // fehlt Nutzern am Rand die Ebene.
      final de = RainLayer.last30d.bounds;
      expect(de.north, greaterThan(55.0));
      expect(de.south, lessThan(47.4));
      expect(de.west, lessThan(6.0));
      expect(de.east, greaterThan(15.0));
    });
  });

  group('Zeit', () {
    test('nur die Vorhersage schickt TIME mit', () {
      expect(params(rainLayerUrl(RainLayer.now, now: now)!), isNot(contains('time')),
          reason: 'Ohne TIME liefert der Dienst seinen eigenen aktuellen '
              'Stand — der ist immer vorhanden, auch bei falsch gehender '
              'Geräteuhr.');
      expect(params(rainLayerUrl(RainLayer.last24h, now: now)!),
          isNot(contains('time')));
      expect(params(rainLayerUrl(RainLayer.last30d, now: now)!),
          isNot(contains('time')));
      expect(params(rainLayerUrl(RainLayer.inOneHour, now: now)!),
          contains('time'));
    });

    test('Vorhersagezeit ist auf 5 Minuten abgerundet, in UTC, +1 Stunde',
        () {
      final p = params(rainLayerUrl(RainLayer.inOneHour, now: now)!);
      // 10:32 → abgerundet 10:30 → +1 h = 11:30.
      expect(p['time'], '2026-08-04T11:30:00Z');
    });

    test('lokale Zeit wird nach UTC gerechnet', () {
      final local = DateTime.utc(2026, 8, 4, 10, 32).toLocal();
      expect(params(rainLayerUrl(RainLayer.inOneHour, now: local)!)['time'],
          '2026-08-04T11:30:00Z',
          reason: 'Der Dienst kennt nur UTC. Eine lokale Zeit wäre im '
              'Sommer zwei Stunden daneben — und läge damit hinter dem '
              'Ende des Vorhersagelaufs.');
    });

    test('Tageswechsel', () {
      final p = params(
          rainLayerUrl(RainLayer.inOneHour, now: DateTime.utc(2026, 8, 4, 23, 44))!);
      expect(p['time'], '2026-08-05T00:40:00Z');
    });
  });

  test('Legende kommt vom selben Dienst wie die Ebene', () {
    final p = params(rainLegendUrl(RainLayer.last30d)!);
    expect(p['request'], 'GetLegendGraphic');
    expect(p['layer'], 'dwd:RADOLAN-W4',
        reason: 'Eine Legende zu einem anderen Produkt wäre schlimmer als '
            'gar keine.');
  });

  test('jede Ebene sagt, wo sie Daten hat', () {
    for (final layer in RainLayer.values) {
      if (layer == RainLayer.off) continue;
      expect(layer.coverage, isNotEmpty,
          reason: 'Ohne diesen Satz sieht eine leere Fläche in Wien nach '
              'einem Fehler der App aus.');
      expect(layer.label, isNotEmpty);
      expect(layer.description, isNotEmpty);
      expect(layer.opacity, inExclusiveRange(0, 1),
          reason: 'Deckend löscht die Karte darunter aus.');
    }
  });
}
