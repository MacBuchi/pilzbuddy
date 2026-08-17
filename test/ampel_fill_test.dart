// Die Pilzwetter-RECHNUNG (Ampel-Vorschau): die Stufe je Zelle, gegen
// das MODELL selbst geprüft — das Gitter rechnet je Zelle dieselbe
// Reihe, die auch `ampelRainFactor`/`ampelLevelOf` bekämen; jede
// Abweichung (Gewichtung, Sättigung, Schwellen) reißt den Vergleich.
//
// Seit 1.76.0 malt hier nichts mehr: Die Ampel färbt nur noch Waldwaben
// (`forestAmpelFillPng`, siehe `forest_ampel_fill_test.dart`). Geprüft
// wird deshalb das Stufen-Gitter, nicht mehr das Bild.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/ampel/ampel_fill.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/ampel/ampel_providers.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';
import 'package:pilzbuddy/features/map/spot_weather.dart';

import 'rain_grid_test.dart' show encode;

/// Ein Stapel: 3 Spalten × 1 Zeile, je Zelle die eigene Regenreihe
/// (Index 0 = ältester Tag). Kürzere Reihen als [days] füllen vorn mit 0.
RainStackData stackOf(List<List<int>> mmPerCellOldestFirst,
    {int days = 26}) {
  return RainStackData(
    info: RainStackInfo(
      width: mmPerCellOldestFirst.length,
      height: 1,
      west: 10,
      east: 13,
      north: 52,
      south: 50,
      days: const [],
    ),
    days: [
      for (var i = 0; i < days; i++)
        (
          date: DateTime.utc(2026, 7, 1).add(Duration(days: i)),
          gzipped: encode([
            [
              for (final series in mmPerCellOldestFirst)
                i < days - series.length
                    ? 0
                    : series[i - (days - series.length)],
            ]
          ]),
        ),
    ],
  );
}

/// Ein Stapel über ein FLÄCHIGES Gitter: [width] × [height] Zellen mit
/// überall derselben Regenreihe ([mmPerDay] an jedem der 26 Tage).
///
/// Für die Wächter-Tests: Wenn der Regen konstant ist, kann jeder
/// Unterschied zwischen zwei Zellen nur aus der Stationswahl kommen.
RainStackData gridStackOf({
  required int width,
  required int height,
  int mmPerDay = 3,
  double west = 10,
  double east = 13,
  double north = 52,
  double south = 50,
}) {
  return RainStackData(
    info: RainStackInfo(
      width: width,
      height: height,
      west: west,
      east: east,
      north: north,
      south: south,
      days: const [],
    ),
    days: [
      for (var i = 0; i < 26; i++)
        (
          date: DateTime.utc(2026, 7, 1).add(Duration(days: i)),
          gzipped: encode([
            for (var y = 0; y < height; y++)
              List.filled(width, mmPerDay),
          ]),
        ),
    ],
  );
}

/// Eine Station für [tableOfStations]: Ort, konstantes Tagesmittel — und
/// an wie vielen der 20 Tage sie überhaupt gemessen hat.
typedef TestStation = ({double lat, double lon, double meanC, int measured});

/// Die Stationstabelle über den echten Parser.
WeatherTable tableOfStations(List<TestStation> stations) {
  String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  final start = DateTime.utc(2026, 7, 7);
  final json = {
    'days': [
      for (var i = 0; i < 20; i++) iso(start.add(Duration(days: i))),
    ],
    'stations': [
      for (final (index, station) in stations.indexed)
        {
          'id': index + 1,
          'lat': station.lat,
          'lon': station.lon,
          'h': 300,
          'name': 'Teststation ${index + 1}',
          // Die Lücken liegen vorn, also bei den ÄLTESTEN Tagen — die
          // Reihe kommt ältester-zuerst.
          'max': [
            for (var i = 0; i < 20; i++)
              i < 20 - station.measured ? null : station.meanC + 3,
          ],
          'min': [
            for (var i = 0; i < 20; i++)
              i < 20 - station.measured ? null : station.meanC - 3,
          ],
        },
    ],
    'soil': const [],
  };
  return weatherTableFrom(
      GZipEncoder().encode(utf8.encode(jsonEncode(json)))!)!;
}

/// Eine einzelne Luftstation mit konstantem Tagesmittel [meanC].
///
/// Sie steht in der MITTE von [stackOf] (lon 11,5), damit auch die
/// Randzellen der drei Spalten innerhalb der 100-km-Grenze liegen — seit
/// die Fläche je Zelle sucht (#279), zählt der Abstand zur Zelle und
/// nicht mehr der zur Kachelmitte.
WeatherTable tableOf(
        {double meanC = 13, double lat = 51, double lon = 11.5}) =>
    tableOfStations([(lat: lat, lon: lon, meanC: meanC, measured: 20)]);

void main() {
  /// Die Stufe der Zelle [x] in der einzigen Zeile — `null` heißt
  /// „keine Aussage" (zu wenige Regentage, keine Station in Reichweite).
  AmpelLevel? levelOf(AmpelLevelGrid grid, int x) => grid.levelFor(0, x);

  test('je Zelle exakt die Stufe, die das Modell für ihre Reihe nennt',
      () {
    // Drei Zellen: satt (5 mm/Tag → Faktor 1), verhalten (1 mm/Tag →
    // 26/87 ≈ 0,30), trocken (0). Temperatur 13 °C → Faktor 1.
    final series = [
      List.filled(26, 5),
      List.filled(26, 1),
      List.filled(26, 0),
    ];
    final grid = ampelLevelsFrom(stackOf(series), tableOf())!;
    expect(grid.width, 3);

    for (final (x, cell) in series.indexed) {
      // Der Maßstab ist das MODELL selbst: dieselbe Reihe, Vortag
      // zuerst, durch dieselben Funktionen.
      final expected = ampelLevelOf(ampelRainFactor(
          [for (final mm in cell.reversed) mm.toDouble()]));
      expect(levelOf(grid, x), expected, reason: 'Zelle $x');
    }
    expect(grid.newest, DateTime.utc(2026, 7, 26));
    expect(grid.west, 10);
    expect(grid.south, 50);
  });

  test('die Altersgewichtung zählt: gleicher Regen, anderes Alter, '
      'andere Stufe', () {
    // Beide Zellen bekommen 8×8 mm — Zelle 0 in den JÜNGSTEN acht
    // Tagen, Zelle 1 in den ältesten. Wer die Gewichtung umdreht oder
    // weglässt, malt beide gleich.
    final young = [...List.filled(18, 0), ...List.filled(8, 8)];
    final old = [...List.filled(8, 8), ...List.filled(18, 0)];
    final grid = ampelLevelsFrom(stackOf([young, old]), tableOf())!;
    final expectedYoung = ampelLevelOf(ampelRainFactor(
        [for (final mm in young.reversed) mm.toDouble()]));
    final expectedOld = ampelLevelOf(ampelRainFactor(
        [for (final mm in old.reversed) mm.toDouble()]));
    expect(expectedYoung, isNot(expectedOld),
        reason: 'sonst prüft dieser Test nichts');
    expect(expectedYoung, AmpelLevel.guenstig);
    expect(expectedOld, AmpelLevel.verhalten);
    expect(levelOf(grid, 0), AmpelLevel.guenstig);
    expect(levelOf(grid, 1), AmpelLevel.verhalten);
  });

  test('die Temperatur dämpft: 27 °C macht aus sattem Regen ungünstig',
      () {
    final grid = ampelLevelsFrom(
        stackOf([List.filled(26, 5)]), tableOf(meanC: 27))!;
    expect(levelOf(grid, 0), AmpelLevel.unguenstig,
        reason: 'Glocke bei 27 °C ≈ 0,0004 — Score unter jeder Schwelle');
  });

  test('ein fehlender Kalendertag nimmt die ganze Ebene', () {
    // 25 statt 26 Tage: Die Altersgewichte wären still verschoben —
    // dieselbe Strenge wie die graue Sektion, heilt sich am Folgetag.
    expect(
        ampelLevelsFrom(
            stackOf([List.filled(25, 5)], days: 25), tableOf()),
        isNull);
  });

  test('ohne Station in 100 km bleibt die Zelle transparent', () {
    final grid = ampelLevelsFrom(
        stackOf([List.filled(26, 5)]), tableOf(lat: 40, lon: 3))!;
    expect(levelOf(grid, 0), isNull,
        reason: 'keine Temperatur, keine Aussage — kein geratener Wert');
  });

  test('ganz ohne Stationstabelle gibt es keine Ebene', () {
    expect(ampelLevelsFrom(stackOf([List.filled(26, 5)]), null), isNull);
  });

  // --- Fläche und Blatt dürfen sich nicht widersprechen (#279) --------
  //
  // Gemeldet war eine rechteckige „verhalten"-Fläche bei Garmisch, wo
  // das Blatt „ungünstig" sagte: Die Fläche suchte ihre Station vom
  // Mittelpunkt einer 16-km-Kachel aus, das Blatt vom Punkt. Der
  // Maßstab dieser Gruppe ist deshalb nicht mehr das Modell allein,
  // sondern **das Blatt** — dieselbe Kette wie in `map_legend.dart` und
  // `ampel_section.dart`, nur ohne Riverpod.
  group('Fläche und Blatt sagen dasselbe (#279)', () {
    /// Nur für die Geometrie: die Zellmitten in Grad.
    RainGrid probeOf(RainStackData stack) => RainGrid(
          values: Uint8List(0),
          width: stack.info.width,
          height: stack.info.height,
          west: stack.info.west,
          east: stack.info.east,
          north: stack.info.north,
          south: stack.info.south,
          measured: DateTime.utc(2026, 7, 26),
        );

    /// Was das BLATT an diesem Punkt sagt: Regenverlauf am Punkt plus
    /// nächste Station am Punkt, durch `ampelReadingFrom`. Grau (kein
    /// Level) ist dasselbe wie „keine Aussage" auf der Karte.
    AmpelLevel? sheetLevelAt(
        RainStackData stack, WeatherTable table, double lat, double lon,
        {ElevationGrid? elevation}) {
      final course = rainCourseFrom(
        stack.days,
        width: stack.info.width,
        height: stack.info.height,
        west: stack.info.west,
        east: stack.info.east,
        north: stack.info.north,
        south: stack.info.south,
        lat: lat,
        lon: lon,
      );
      return ampelReadingFrom(course, table.at(lat, lon),
              spotHeightM: elevation?.heightMetersAt(lat, lon))
          .level;
    }

    /// Ein Gitter in Wirklichkeitsmaßstab: ~1 km je Zelle, also
    /// ~17-km-Kacheln wie am echten Regengitter. Ein großzügiger
    /// Ausschnitt würde die Kandidaten-Schranke nie schneiden lassen.
    const width = 32;
    const height = 24;
    RainStackData stackForArea() => gridStackOf(
          width: width,
          height: height,
          west: 10.0,
          east: 10.5,
          north: 51.3,
          south: 51.0,
        );

    /// Drei Stationen, deren Faktoren in DREI Bändern liegen:
    /// 13 °C → 1,000 · 17 °C → 0,527 · 20 °C → 0,141, jeweils mal
    /// Regenfaktor 0,897 (3 mm/Tag).
    final threeBands = <TestStation>[
      (lat: 51.32, lon: 10.05, meanC: 13, measured: 20),
      (lat: 51.28, lon: 10.45, meanC: 17, measured: 20),
      (lat: 50.95, lon: 10.25, meanC: 20, measured: 20),
    ];

    /// Läuft jede Zellmitte ab und vergleicht Karte gegen Blatt.
    /// Gibt zurück, welche Stufen dabei überhaupt vorkamen — ohne
    /// Kontrast prüft der Lauf nichts.
    Set<AmpelLevel?> walkAndCompare(
        RainStackData stack, WeatherTable table, AmpelLevelGrid grid) {
      final probe = probeOf(stack);
      final seen = <AmpelLevel?>{};
      for (var y = 0; y < stack.info.height; y++) {
        final lat = probe.latAtRow(y + 0.5);
        for (var x = 0; x < stack.info.width; x++) {
          final lon = probe.lonAtColumn(x + 0.5);
          final expected = sheetLevelAt(stack, table, lat, lon);
          expect(grid.levelFor(y, x), expected,
              reason: 'Zelle $x/$y (${lat.toStringAsFixed(4)}, '
                  '${lon.toStringAsFixed(4)})');
          seen.add(expected);
        }
      }
      return seen;
    }

    test('an jeder Zellmitte dieselbe Stufe wie im Spot-Blatt', () {
      final stack = stackForArea();
      final table = tableOfStations(threeBands);
      final grid = ampelLevelsFrom(stack, table)!;

      expect(walkAndCompare(stack, table, grid), hasLength(3),
          reason: 'die Lage muss alle drei Stufen hergeben, sonst '
              'vergleicht der Lauf lauter gleiche Werte');

      // Und der Beweis, dass die Auflösung wirklich feiner ist als die
      // Kachel: Die alte Rechnung konnte je Kachel nur EINE Stufe
      // malen, weil der Regen hier überall gleich ist.
      final blocksX = (width + ampelTempBlockCells - 1) ~/ ampelTempBlockCells;
      final perBlock = <int, Set<AmpelLevel?>>{};
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final block = (y ~/ ampelTempBlockCells) * blocksX +
              x ~/ ampelTempBlockCells;
          (perBlock[block] ??= <AmpelLevel?>{}).add(grid.levelFor(y, x));
        }
      }
      expect(perBlock.values.where((levels) => levels.length > 1), isNotEmpty,
          reason: 'mindestens eine Kachel muss mehrere Stufen enthalten — '
              'sonst käme die alte Blockrechnung genauso durch');
    });

    test('wo Kachelmitte und Zelle verschiedene Stationen sehen, '
        'gilt die Zelle', () {
      final stack = stackForArea();
      final table = tableOfStations(threeBands);
      final grid = ampelLevelsFrom(stack, table)!;
      final probe = probeOf(stack);

      // Genau der gemeldete Fall, als Bedingung formuliert: Zellmitte
      // und Kachelmitte greifen zu verschiedenen Stationen.
      var contested = 0;
      for (var y = 0; y < height; y++) {
        final lat = probe.latAtRow(y + 0.5);
        final rowStart = y ~/ ampelTempBlockCells * ampelTempBlockCells;
        final rowEnd = rowStart + ampelTempBlockCells > height
            ? height
            : rowStart + ampelTempBlockCells;
        final blockLat = probe.latAtRow((rowStart + rowEnd) / 2);
        for (var x = 0; x < width; x++) {
          final lon = probe.lonAtColumn(x + 0.5);
          final colStart = x ~/ ampelTempBlockCells * ampelTempBlockCells;
          final colEnd = colStart + ampelTempBlockCells > width
              ? width
              : colStart + ampelTempBlockCells;
          final blockLon = probe.lonAtColumn((colStart + colEnd) / 2);
          final atCell = table.nearestAir(lat, lon)?.station.name;
          final atBlock = table.nearestAir(blockLat, blockLon)?.station.name;
          if (atCell == atBlock) continue;
          contested++;
          expect(grid.levelFor(y, x),
              sheetLevelAt(stack, table, lat, lon),
              reason: 'Zelle $x/$y sieht $atCell, ihre Kachel $atBlock');
        }
      }
      expect(contested, greaterThan(0),
          reason: 'ohne strittige Zellen prüft dieser Test nichts');
    });

    test('auch mit Höhengitter: an jeder Zellmitte dieselbe Stufe '
        'wie im korrigierten Blatt', () {
      final stack = stackForArea();
      // EINE Station auf 300 m (die Höhe aus `tableOfStations`), Mittel
      // 13 °C — unkorrigiert wäre ÜBERALL „günstig". Das Höhengitter
      // legt die Osthälfte auf 1500 m: Dort kühlt die Korrektur um
      // 7,8 K ab, und die Stufe kippt. Der Kontrast ist der Beweis,
      // dass die Korrektur wirklich rechnet — ein Gitter ohne Wirkung
      // bestünde diesen Test nicht.
      final table = tableOfStations(
          [(lat: 51.15, lon: 10.25, meanC: 13, measured: 20)]);
      final elevation = ElevationGrid(
        values: Uint8List.fromList([
          for (var y = 0; y < 8; y++)
            for (var x = 0; x < 10; x++)
              x < 5 ? 300 ~/ elevationQuantM : 1500 ~/ elevationQuantM,
        ]),
        width: 10,
        height: 8,
        west: 10.0,
        east: 10.5,
        north: 51.3,
        south: 51.0,
        hexLonStep: 0.05,
        hexLatStep: 0.0375,
      );
      // EIN Gitter — die Höhe geht seit dem Berchtesgaden-Befund nicht
      // mehr in den Bau ein, sondern in die Auswertung: `levelAt` mit
      // Höhengitter ist exakt der Weg des Wabenzeichners.
      final grid = ampelLevelsFrom(stack, table)!;

      final probe = probeOf(stack);
      final seen = <AmpelLevel?>{};
      var changed = 0;
      for (var y = 0; y < height; y++) {
        final lat = probe.latAtRow(y + 0.5);
        for (var x = 0; x < width; x++) {
          final lon = probe.lonAtColumn(x + 0.5);
          final expected =
              sheetLevelAt(stack, table, lat, lon, elevation: elevation);
          expect(grid.levelAt(lat, lon, elevation: elevation), expected,
              reason: 'Zelle $x/$y (${lat.toStringAsFixed(4)}, '
                  '${lon.toStringAsFixed(4)})');
          seen.add(expected);
          if (grid.levelAt(lat, lon, elevation: elevation) !=
              grid.levelFor(y, x)) {
            changed++;
          }
        }
      }
      expect(seen.length, greaterThan(1),
          reason: 'die 1500-m-Hälfte muss die Stufe kippen — sonst '
              'vergleicht der Lauf lauter gleiche Werte');
      expect(changed, greaterThan(0),
          reason: 'kein Unterschied zur unkorrigierten Fläche — die '
              'Korrektur hat nicht gerechnet');
    });

    test('die Ablesung verschiebt das Mittel exakt um 0,65 K je 100 m',
        () {
      final stack = stackForArea();
      final table = tableOfStations(
          [(lat: 51.15, lon: 10.25, meanC: 13, measured: 20)]);
      RainCourse courseAt(double lat, double lon) => rainCourseFrom(
            stack.days,
            width: stack.info.width,
            height: stack.info.height,
            west: stack.info.west,
            east: stack.info.east,
            north: stack.info.north,
            south: stack.info.south,
            lat: lat,
            lon: lon,
          );
      final at = table.at(51.15, 10.25);

      // Station 300 m, Spot 1500 m: (300 − 1500) · 0,65/100 = −7,8 K.
      final corrected = ampelReadingFrom(courseAt(51.15, 10.25), at,
          spotHeightM: 1500);
      expect(corrected.tempMeanC, closeTo(13 - 7.8, 1e-9));
      expect(corrected.heightCorrectionK, closeTo(-7.8, 1e-9));
      expect(corrected.spotHeightM, 1500);

      // Gleiche Höhe: Korrektur 0, aber GESETZT — die Anzeige
      // unterscheidet „nichts zu tun" von „konnte nicht rechnen".
      final level = ampelReadingFrom(courseAt(51.15, 10.25), at,
          spotHeightM: 300);
      expect(level.tempMeanC, closeTo(13, 1e-9));
      expect(level.heightCorrectionK, closeTo(0, 1e-9));

      // Ohne Höhe: unkorrigiert, beide Felder leer.
      final without = ampelReadingFrom(courseAt(51.15, 10.25), at);
      expect(without.tempMeanC, closeTo(13, 1e-9));
      expect(without.heightCorrectionK, isNull);
      expect(without.spotHeightM, isNull);
    });

    test('die Kandidaten-Schranke reicht bis in die Kachelecke', () {
      // Die Schranke muss `dMin + 2 * reach` sein, nicht `dMin + reach`:
      // Eine Zelle in der Kachelecke liegt `reach` von der Mitte weg,
      // ihre Siegerin darf also nochmal `reach` weiter draußen stehen.
      //
      // Genau diese Lage wird hier gebaut: Station A sitzt fast auf der
      // Kachelmitte, Station B liegt in Richtung der Nordwest-Ecke, aber
      // anderthalbmal so weit — von der Mitte aus fern, von der Eckzelle
      // aus die nächste. Wer die Schranke halbiert, verliert B und malt
      // die Ecke mit A.
      final stack = stackForArea();
      final probe = probeOf(stack);
      final centreLat = probe.latAtRow(ampelTempBlockCells / 2);
      final centreLon = probe.lonAtColumn(ampelTempBlockCells / 2);
      final cornerLat = probe.latAtRow(0.5);
      final cornerLon = probe.lonAtColumn(0.5);
      final table = tableOfStations([
        (lat: centreLat, lon: centreLon, meanC: 13, measured: 20),
        (
          lat: centreLat + (cornerLat - centreLat) * 1.5,
          lon: centreLon + (cornerLon - centreLon) * 1.5,
          meanC: 20,
          measured: 20,
        ),
      ]);
      // Ohne diesen Vorspann prüfte der Test eine Lage, die es gar nicht
      // gibt: B muss die Eckzelle gewinnen und die Mitte verlieren.
      expect(table.nearestAir(cornerLat, cornerLon)?.station.name,
          'Teststation 2');
      expect(table.nearestAir(centreLat, centreLon)?.station.name,
          'Teststation 1');

      final grid = ampelLevelsFrom(stack, table)!;
      expect(walkAndCompare(stack, table, grid).length, greaterThan(1),
          reason: 'ohne Stufenwechsel wäre der Vergleich zahnlos');
    });

    test('auch im dichten Stationsnetz stimmt jede Zelle mit dem Blatt', () {
      // Ein gestörtes Stationsgitter MIT LOCH: Ein gleichmäßiges Netz
      // stresst die Schranke nicht — dort liegt die Siegerin einer
      // Randzelle immer knapp innerhalb. Erst wo die Dichte springt,
      // gewinnt für eine Eckzelle eine Station, die von der Kachelmitte
      // aus weit weg steht. Genau dann muss die Schranke weit genug
      // sein. Verliert sie die Siegerin, weicht die Zelle vom Blatt ab —
      // das Blatt sucht roh über alle.
      final dense = <TestStation>[
        for (var i = 0; i < 6; i++)
          for (var j = 0; j < 7; j++)
            if (!(i >= 2 && i <= 3 && j >= 2 && j <= 4))
              (
                lat: 50.94 + i * 0.09 + (j.isEven ? 0.018 : -0.013),
                lon: 9.96 + j * 0.10 + (i.isOdd ? 0.021 : -0.016),
                meanC: 11.0 + ((i * 7 + j) % 13),
                measured: 20,
              ),
      ];
      final stack = stackForArea();
      final table = tableOfStations(dense);
      expect(table.air, hasLength(36), reason: '42 minus das 2×3-Loch');
      final grid = ampelLevelsFrom(stack, table)!;

      expect(walkAndCompare(stack, table, grid).length, greaterThan(1),
          reason: 'ohne Stufenwechsel wäre der Vergleich zahnlos');
    });

    test('eine zu lückige Station macht die Zelle transparent, statt '
        'zur übernächsten zu greifen', () {
      // Die nächste Station hat 12 von 20 Tagen: Sie tritt an (>= 10),
      // kann aber nicht antworten (< 14). Das Blatt wird grau — und die
      // Karte darf sich nicht die übernächste holen und färben.
      final stack = stackOf([List.filled(26, 5)]);
      // Die lückige steht NÄHER (70 km) als die vollständige (77 km) —
      // die Karte darf sich die weitere nicht holen.
      final gappy = <TestStation>[
        (lat: 51.0, lon: 10.5, meanC: 13, measured: 12),
        (lat: 51.0, lon: 10.4, meanC: 13, measured: 20),
      ];
      final table = tableOfStations(gappy);
      final grid = ampelLevelsFrom(stack, table)!;
      final probe = probeOf(stack);
      final lat = probe.latAtRow(0.5);
      final lon = probe.lonAtColumn(0.5);

      expect(table.nearestAir(lat, lon)?.station.name, 'Teststation 1',
          reason: 'die lückige muss hier wirklich die nächste sein');
      expect(sheetLevelAt(stack, table, lat, lon), isNull,
          reason: 'das Blatt wird grau — der Maßstab dieses Tests');
      expect(grid.levelFor(0, 0), isNull);

      // Und die Gegenprobe: Ohne die lückige davor stünde hier sehr
      // wohl eine Stufe — sonst prüfte der Test nur, dass irgendetwas
      // transparent ist.
      final good = ampelLevelsFrom(stack, tableOfStations([gappy.last]))!;
      expect(good.levelFor(0, 0), isNotNull,
          reason: 'die Lage an sich gibt eine Stufe her');
    });
  });
}
