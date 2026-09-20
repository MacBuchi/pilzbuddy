// Das Fundorte-Asset (#467): Roundtrip durch das Spaltenformat, die
// Deutung der Sonderwerte, die Umkreis-Abfrage — und das echte Asset.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/features/map/gbif_finds.dart';

/// Eine Zeile, wie das Werkzeug sie schreibt.
typedef GbifRow = ({
  int species,
  double lat,
  double lon,
  int? uncertaintyM,
  int count,
  int? year,
});

const testBox = (west: 5.8, east: 17.3, north: 55.1, south: 45.7);

/// Der Encoder des Werkzeugs in Dart — Spalte für Spalte dasselbe
/// Format (`tool/gbif_finds.py`, „FORMAT"), damit Tests kleine Assets
/// bauen können, ohne Python zu rufen.
(Uint8List bytes, String manifest) encodeGbifFinds(
  List<GbifRow> rows, {
  required List<String> species,
  List<({String key, String title, int observations})> datasets = const [],
  Map<String, int> countries = const {},
  String? doi = '10.0/test',
}) {
  final n = rows.length;
  final raw = Uint8List(n * 9);
  final view = ByteData.view(raw.buffer);
  int q(double value, double low, double high) =>
      ((value - low) / (high - low) * 65535).round();
  for (var i = 0; i < n; i++) {
    final row = rows[i];
    raw[i] = row.species;
    view.setUint16(n + 2 * i, q(row.lat, testBox.north, testBox.south),
        Endian.little);
    view.setUint16(3 * n + 2 * i, q(row.lon, testBox.west, testBox.east),
        Endian.little);
    view.setUint16(5 * n + 2 * i, row.uncertaintyM ?? 0, Endian.little);
    raw[7 * n + i] = row.count;
    raw[8 * n + i] = row.year == null ? 0 : row.year! - 1900;
  }
  final gz = Uint8List.fromList(GZipEncoder().encode(raw)!);
  final manifest = jsonEncode({
    'encoding': 'gzip-columns',
    'columns': ['species', 'lat', 'lon', 'unc', 'count', 'year'],
    'records': n,
    'observations': rows.fold<int>(0, (sum, r) => sum + r.count),
    'west': testBox.west,
    'east': testBox.east,
    'north': testBox.north,
    'south': testBox.south,
    'unknown_uncertainty_drawn_as_m': 3535,
    'doi': doi,
    'fetched_on': '2026-09-16',
    'countries': countries,
    'species': [
      for (final name in species)
        {
          'name': name,
          'sci': 'Sci $name',
          'observations':
              rows.where((r) => species[r.species] == name).length,
        },
    ],
    'datasets': [
      for (final d in datasets)
        {'key': d.key, 'title': d.title, 'observations': d.observations},
    ],
  });
  return (gz, manifest);
}

GbifFinds findsOf(List<GbifRow> rows, {required List<String> species}) {
  final (bytes, manifest) = encodeGbifFinds(rows, species: species);
  return GbifFinds.decode(bytes, manifest);
}

void main() {
  test('Roundtrip: jede Spalte kommt so zurück, wie sie hineinging', () {
    final finds = findsOf([
      (species: 0, lat: 51.0, lon: 10.0, uncertaintyM: 25, count: 1, year: 2024),
      (species: 0, lat: 51.0, lon: 10.0, uncertaintyM: 3535, count: 3, year: 2023),
      (species: 1, lat: 48.0, lon: 12.0, uncertaintyM: null, count: 11, year: null),
    ], species: [
      'Steinpilz',
      'Rotkappe'
    ]);
    expect(finds.length, 3);
    expect(finds.observations, 15);
    expect(finds.species.map((s) => s.name), ['Steinpilz', 'Rotkappe']);
    expect(finds.latAt(0), closeTo(51.0, 0.0002));
    expect(finds.lonAt(0), closeTo(10.0, 0.0002));
    expect(finds.uncertaintyM[0], 25);
    expect(finds.count[1], 3);
    expect(finds.yearAt(0), 2024);
    expect(finds.yearAt(1), 2023);
    // Die Sonderwerte: unbekannte Unschärfe zeichnet als Quadrat, ein
    // fehlendes Jahr bleibt null statt 1900.
    expect(finds.uncertaintyKnownAt(2), isFalse);
    expect(finds.uncertaintyAt(2), 3535);
    expect(finds.yearAt(2), isNull);
    expect(finds.doi, '10.0/test');
  });

  test('ungerade Zeilenzahl — die u16-Spalten liegen dann unausgerichtet',
      () {
    // Drei Zeilen: Die Breiten-Spalte beginnt bei Byte 3. Ein Leser,
    // der `asUint16List` mit Versatz nimmt, würfe hier oder läse
    // Müll; der Roundtrip oben hat drei Zeilen, dieser hier eine.
    final finds = findsOf([
      (species: 0, lat: 50.5, lon: 8.25, uncertaintyM: 250, count: 2, year: 2020),
    ], species: [
      'Steinpilz'
    ]);
    expect(finds.latAt(0), closeTo(50.5, 0.0002));
    expect(finds.lonAt(0), closeTo(8.25, 0.0002));
    expect(finds.uncertaintyM[0], 250);
  });

  test('fremde Kodierung, falsche Länge und Artindex ohne Eintrag werden '
      'abgelehnt', () {
    final (bytes, manifest) = encodeGbifFinds([
      (species: 0, lat: 51.0, lon: 10.0, uncertaintyM: 25, count: 1, year: 2024),
    ], species: [
      'Steinpilz'
    ]);
    final map = jsonDecode(manifest) as Map<String, dynamic>;
    expect(
        () => GbifFinds.decode(
            bytes, jsonEncode({...map, 'encoding': 'gzip'})),
        throwsFormatException);
    expect(() => GbifFinds.decode(bytes, jsonEncode({...map, 'records': 2})),
        throwsFormatException);
    expect(
        () => GbifFinds.decode(
            bytes, jsonEncode({...map, 'species': <Object>[]})),
        throwsFormatException);
  });

  test('around: Fläche zählt, Zähler summieren, häufigste Art zuerst', () {
    // Mittelpunkt 51,0/10,0. Ein scharfer Punkt 2 km östlich, ein
    // Quadrat mit Mittelpunkt 7 km nördlich (reicht mit 3535 m in den
    // 5-km-Umkreis), eines 9 km nördlich (reicht nicht), eine zweite
    // Art dreimal an einem Ort direkt daneben.
    final finds = findsOf([
      (species: 0, lat: 51.0, lon: 10.0285, uncertaintyM: 25, count: 1, year: 2019),
      (species: 0, lat: 51.063, lon: 10.0, uncertaintyM: 3535, count: 2, year: 2022),
      (species: 0, lat: 51.081, lon: 10.0, uncertaintyM: 3535, count: 9, year: 2025),
      (species: 1, lat: 51.001, lon: 10.0, uncertaintyM: null, count: 3, year: null),
    ], species: [
      'Steinpilz',
      'Pfifferling'
    ]);
    final rows = finds.around(51.0, 10.0, radiusM: 5000);
    expect(rows.map((r) => r.species), ['Pfifferling', 'Steinpilz']);
    expect(rows[0].observations, 3);
    expect(rows[0].places, 1);
    expect(rows[0].newestYear, isNull);
    expect(rows[1].observations, 3, reason: '1 + 2, das ferne Quadrat nicht');
    expect(rows[1].places, 2);
    expect(rows[1].newestYear, 2022, reason: 'das Jahr des fernen Quadrats zählt nicht mit');
    expect(finds.around(40.0, 10.0, radiusM: 5000), isEmpty);
  });

  test('das echte Asset lässt sich lesen und passt zur Artenliste', () {
    // Bewusst mit dem ausgelieferten Asset: Ein Baufehler im Werkzeug
    // soll hier auffallen, nicht auf dem Gerät.
    final bytes = File('assets/gbif/gbif_finds.bin.gz').readAsBytesSync();
    final manifest =
        File('assets/gbif/gbif_finds_manifest.json').readAsStringSync();
    final finds = GbifFinds.decode(bytes, manifest);
    expect(finds.length, greaterThan(100000));
    expect(finds.doi, isNotNull);
    // Jede Art im Asset ist eine bekannte Hauptbezeichnung — sonst
    // fände weder der Filter noch die Ampel-Klasse sie.
    final known = {
      for (final s in kBekannteArten)
        if (!s.isSynonym) s.name
    };
    for (final s in finds.species) {
      expect(known, contains(s.name));
    }
    // Und die Namensnennung ist dabei.
    expect(finds.datasets, isNotEmpty);
    expect(finds.datasets.first.title, isNot(finds.datasets.first.key));
    // Alle Koordinaten liegen in der Box — quantisiert kann keine
    // herausfallen, aber ein vertauschtes Nord/Süd sähe man hier.
    for (final i in [0, finds.length ~/ 2, finds.length - 1]) {
      expect(finds.latAt(i), inInclusiveRange(45.7, 55.1));
      expect(finds.lonAt(i), inInclusiveRange(5.8, 17.3));
    }
  });
}
