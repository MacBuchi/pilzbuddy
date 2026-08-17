// Der Höhengitter-Leser (`elevation_grid.dart`): beide Kodierungen,
// die Ablehnungen, die Punkt-Zuordnung und die Lapse-Rechnung.
//
// Die Kodier-Seite (Python) testet sich selbst; hier steht die
// Dart-Hälfte desselben Vertrags — mit denselben Zahlenbeispielen, wo
// es sie gibt (Zugspitze = Byte 148).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';

/// gzip wie das Werkzeug — plain oder mit Zeilen-Delta.
List<int> packed(List<List<int>> rows, {required bool delta}) {
  final flat = <int>[];
  for (final row in rows) {
    var previous = 0;
    for (final byte in row) {
      flat.add(delta ? (byte - previous) & 0xFF : byte);
      previous = byte;
    }
  }
  return GZipEncoder().encode(Uint8List.fromList(flat))!;
}

ElevationGrid decodeWith(String encoding, List<int> payload) =>
    ElevationGrid.decode(
      payload,
      encoding: encoding,
      width: 4,
      height: 2,
      west: 10.0,
      east: 10.4,
      north: 51.2,
      south: 51.0,
      hexLonStep: 0.1,
      hexLatStep: 0.1,
    );

void main() {
  // Die Zeilen decken den Wertebereich ab: Meer, Mittelgebirge,
  // Zugspitze (148 · 20 = 2960 m), Randzelle ohne Aussage.
  final rows = [
    [0, 15, 148, 0xFF],
    [3, 3, 3, 3],
  ];

  test('beide Kodierungen entpacken zu denselben Werten', () {
    for (final delta in [true, false]) {
      final grid = decodeWith(
          delta ? 'gzip+row-delta' : 'gzip', packed(rows, delta: delta));
      expect(grid.values, [0, 15, 148, 0xFF, 3, 3, 3, 3],
          reason: 'delta=$delta');
    }
  });

  test('fremde Kodierung und falsche Größe werden abgelehnt', () {
    expect(() => decodeWith('brotli', packed(rows, delta: false)),
        throwsFormatException,
        reason: 'ein Asset, das neuer ist als die App, wird abgelehnt '
            'statt still falsch gelesen');
    expect(
        () => ElevationGrid.decode(
              packed(rows, delta: false),
              encoding: 'gzip',
              width: 3,
              height: 2,
              west: 10.0,
              east: 10.3,
              north: 51.2,
              south: 51.0,
              hexLonStep: 0.1,
              hexLatStep: 0.1,
            ),
        throwsFormatException);
  });

  test('Höhe am Punkt: Byte mal 20 m, 0xFF und außerhalb sind null', () {
    final grid = decodeWith('gzip', packed(rows, delta: false));
    // Zellmitten der obersten Hexzeile (v klein): u wächst nach Osten.
    expect(grid.heightMetersAt(51.19, 10.02), 0);
    expect(grid.heightMetersAt(51.19, 10.12), 300);
    expect(grid.heightMetersAt(51.19, 10.22), 2960,
        reason: 'die Zugspitzen-Zelle: Byte 148');
    expect(grid.heightMetersAt(51.19, 10.38), isNull,
        reason: '0xFF heißt keine Aussage, nicht 5100 m');
    expect(grid.heightMetersAt(52.0, 10.1), isNull, reason: 'nördlich');
    expect(grid.heightMetersAt(51.1, 9.0), isNull, reason: 'westlich');
  });

  test('das ausgelieferte Asset: Landmarken über den DART-Leser', () {
    // Dieselben drei Punkte, die `tool/elevation_grid.py --verify` in
    // CI prüft — mit den Werten aus dem Bau-Lauf vom 2026-08-17. Der
    // Witz ist nicht die Höhe, sondern die ZELLE: Werkzeug (Python,
    // `cell_at`) und App (`hexNearestCell`) müssen denselben Punkt in
    // dieselbe Wabe legen. Weichen die Gitterwege je voneinander ab,
    // treffen sie verschiedene Zellen und dieser Test bricht.
    final manifest = jsonDecode(File('assets/elevation/elevation_manifest.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final grid = ElevationGrid.decode(
      File('assets/elevation/elevation.bin.gz').readAsBytesSync(),
      encoding: manifest['encoding'] as String,
      width: manifest['width'] as int,
      height: manifest['height'] as int,
      west: (manifest['west'] as num).toDouble(),
      east: (manifest['east'] as num).toDouble(),
      north: (manifest['north'] as num).toDouble(),
      south: (manifest['south'] as num).toDouble(),
      hexLonStep: (manifest['hex_lon_step'] as num).toDouble(),
      hexLatStep: (manifest['hex_lat_step'] as num).toDouble(),
    );
    expect(grid.heightMetersAt(47.4212, 10.9853), 2860,
        reason: 'Zugspitze (Wabenmittel)');
    expect(grid.heightMetersAt(47.8737, 8.0043), 1480, reason: 'Feldberg');
    expect(grid.heightMetersAt(53.5510, 9.9940), 20, reason: 'Hamburg');
  });

  test('Lapse-Rechnung: Vorzeichen und Größe', () {
    // Station auf der Zugspitze (2956 m), Tal auf 700 m: Das Tal ist
    // WÄRMER — die Korrektur muss positiv sein und 14,664 K betragen.
    expect(
        lapseCorrectionK(stationHeightM: 2956, targetHeightM: 700),
        closeTo(14.664, 1e-9));
    // Station im Tal, Spot am Berg: kälter.
    expect(lapseCorrectionK(stationHeightM: 300, targetHeightM: 1500),
        closeTo(-7.8, 1e-9));
    expect(lapseCorrectionK(stationHeightM: 500, targetHeightM: 500), 0);
  });
}
