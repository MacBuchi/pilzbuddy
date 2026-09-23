// Schutzgebiete (#580): lesen, nachschlagen, benennen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/protected_areas.dart';

/// Schreibt Läufe wie `tool/protected_areas.py` (`encode_runs`) — für
/// den Rundlauf gegen den echten Leser.
List<int> encodeRuns(List<List<(int, int, int)>> rows) {
  final out = BytesBuilder();
  void u16(int v) => out.add([v & 0xFF, v >> 8]);
  for (final row in rows) {
    u16(row.length);
    for (final (x0, n, idx) in row) {
      u16(x0);
      u16(n);
      u16(idx);
    }
  }
  return GZipEncoder().encode(out.toBytes())!;
}

String manifestOf(
        {required int width,
        required int height,
        List<Map<String, String>> areas = const [],
        String encoding = 'gzip-runs-u16le'}) =>
    jsonEncode({
      'lattice': 'hex-odd-r',
      'encoding': encoding,
      'width': width,
      'height': height,
      'west': 10.0,
      'north': 50.0,
      'hex_lon_step': 0.01,
      'hex_lat_step': 0.01,
      'extracts': {'germany': '2026-09-22T20:22:59Z'},
      'areas': areas,
    });

/// Ein kleines Gitter direkt gebaut — für die Tests anderer Dateien.
ProtectedAreas protectedOf(List<List<(int, int, int)>> rows,
        {List<ProtectedArea> areas = const [
          ProtectedArea(
              kind: ProtectedKind.natureReserve, name: 'Wutachschlucht'),
        ],
        double west = 10.0,
        double north = 50.0,
        double lonStep = 0.01,
        double latStep = 0.01,
        int width = 10}) =>
    ProtectedAreas(
      width: width,
      height: rows.length,
      west: west,
      north: north,
      lonStep: lonStep,
      latStep: latStep,
      rows: [
        for (final row in rows)
          Uint16List.fromList([
            for (final (x0, n, idx) in row) ...[x0, n, idx],
          ]),
      ],
      areas: areas,
    );

void main() {
  test('Rundlauf: was das Werkzeug schreibt, liest die App zurück', () {
    final areas = ProtectedAreas.decode(
        encodeRuns([
          [],
          [(0, 2, 1), (2, 1, 2), (5, 1, 3)],
          [(5, 1, 3)],
        ]),
        manifestOf(width: 6, height: 3, areas: [
          {'kind': 'Naturschutzgebiet', 'name': 'Wutachschlucht'},
          {'kind': 'Nationalpark', 'name': 'Nationalpark Schwarzwald'},
          {'kind': 'Kernzone', 'name': ''},
        ]));
    expect(areas.indexAtCell(1, 1), 1);
    expect(areas.indexAtCell(2, 1), 2, reason: 'Nachbarlauf, anderes Gebiet');
    expect(areas.indexAtCell(3, 1), 0, reason: 'zwischen zwei Läufen');
    expect(areas.indexAtCell(5, 2), 3);
    expect(areas.indexAtCell(0, 0), 0, reason: 'leere Zeile');
    expect(areas.areas[1].kind, ProtectedKind.nationalPark);
    expect(areas.extract, '2026-09-22');
  });

  test('ein fremdes Format ist KEIN leeres Gitter, sondern ein Fehler', () {
    // Sonst läse eine neuere App ein älteres Asset (ein Wert je Zelle)
    // als Läufe — und fände überall Unsinn oder nichts.
    expect(
        () => ProtectedAreas.decode(encodeRuns([[]]),
            manifestOf(width: 1, height: 1, encoding: 'gzip-u16le')),
        throwsFormatException);
    expect(
        () => ProtectedAreas.decode(
            encodeRuns([[], []]), manifestOf(width: 1, height: 1)),
        throwsFormatException,
        reason: 'Bytes hinter der letzten Zeile heißen: falsche Höhe');
  });

  test('nachschlagen geht über dieselbe Wabe wie das Waldgitter', () {
    final areas = protectedOf([
      [],
      [(3, 2, 1)],
    ]);
    // Wabe (3, 1): Mittelpunkt bei u = 3 + 0,5 + 0,5 (ungerade Zeile),
    // v = 1 + 2/3.
    const lon = 10.0 + 4.0 * 0.01;
    const lat = 50.0 - (1 + 2 / 3) * 0.01;
    expect(areas.areaAt(lat, lon)?.name, 'Wutachschlucht');
    expect(areas.areaAt(lat, lon + 0.02), isNull, reason: 'Wabe (5, 1)');
    expect(areas.areaAt(10, 10), isNull, reason: 'außerhalb des Rasters');
  });

  test('der Anzeigename verdoppelt die Art nicht', () {
    String label(ProtectedKind kind, String name) =>
        ProtectedArea(kind: kind, name: name).label;
    expect(label(ProtectedKind.natureReserve, 'Wutachschlucht'),
        'Naturschutzgebiet „Wutachschlucht“');
    expect(label(ProtectedKind.natureReserve, 'Naturschutzgebiet Ruggeller Riet'),
        'Naturschutzgebiet Ruggeller Riet',
        reason: 'so stand es im ersten Entwurf doppelt da');
    expect(label(ProtectedKind.coreZone, 'Kernzone Nationalpark Schwarzwald'),
        'Kernzone Nationalpark Schwarzwald');
    expect(label(ProtectedKind.coreZone, 'Schutzzone 1 Nationalpark Hainich'),
        'Schutzzone 1 Nationalpark Hainich');
    expect(label(ProtectedKind.nationalPark, 'Národní park Šumava'),
        'Národní park Šumava');
    expect(label(ProtectedKind.nationalPark, ''), 'Nationalpark',
        reason: 'ohne Namen die Art allein, keine leeren Anführungszeichen');
  });
}
