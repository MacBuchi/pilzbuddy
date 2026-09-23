// Die Fundorte-Fläche (#467): zurückdekodiert und Pixel für Pixel
// geprüft — dieselbe Begründung wie beim Wald: „durchsichtig, weil
// nichts gemeldet" und „durchsichtig, weil kaputt" sehen gleich aus.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/gbif_fill.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart'
    show latFromMercatorY, mercatorY;

import 'gbif_finds_test.dart' show GbifRow, findsOf;
import 'rain_fill_test.dart' show decodePng;

void main() {
  // Ein Fenster von 200 × 200 px über 0,2° × ~0,13°: knapp 14 km breit,
  // also ~70 m je Pixel — ein 250-m-Punkt ist dort 3,6 px Radius, ein
  // Quadrat 50 px.
  const window = FillWindow(
      west: 10.0, east: 10.2, north: 51.1, south: 50.97, width: 200, height: 200);

  /// Pixelmitte in Fensterkoordinaten für einen Punkt.
  (int x, int y) pixelOf(double lat, double lon) => (
        ((lon - window.west) / (window.east - window.west) * window.width)
            .floor(),
        ((mercatorY(lat) - mercatorY(window.north)) /
                (mercatorY(window.south) - mercatorY(window.north)) *
                window.height)
            .floor(),
      );

  ({int r, int g, int b, int a}) pixel(
      ({int width, int height, Uint8List pixels}) png, int x, int y) {
    final o = (y * png.width + x) * 4;
    return (
      r: png.pixels[o],
      g: png.pixels[o + 1],
      b: png.pixels[o + 2],
      a: png.pixels[o + 3],
    );
  }

  int red(int argb) => (argb >> 16) & 0xFF;

  test('eine scharfe Scheibe trägt die Klassenfarbe, drumherum nichts', () {
    final finds = findsOf([
      (species: 0, lat: 51.03, lon: 10.1, uncertaintyM: 250, count: 1, year: 2024),
    ], species: [
      'Steinpilz'
    ]);
    final paint = gbifPaintFor(finds);
    final png = decodePng(gbifFillPng(finds, window: window, paint: paint));
    final (x, y) = pixelOf(51.03, 10.1);
    final centre = pixel(png, x, y);
    expect(centre.a, gbifSharpAlpha);
    expect(centre.r, red(AppColors.gbifClassColours['herbst']!.toARGB32()));
    // 250 m sind hier ~3,6 px: Zehn Pixel weiter ist nichts mehr.
    expect(pixel(png, x + 10, y).a, 0);
    expect(pixel(png, x, y + 10).a, 0);
  });

  test('die Kante ist weich: der äußerste Ring hat die halbe Deckkraft', () {
    // 700 m sind hier 10 px Radius — groß genug, dass der Ring nicht am
    // halben Pixel hängt.
    final finds = findsOf([
      (species: 0, lat: 51.03, lon: 10.1, uncertaintyM: 700, count: 1, year: 2024),
    ], species: [
      'Steinpilz'
    ]);
    final png = decodePng(
        gbifFillPng(finds, window: window, paint: gbifPaintFor(finds)));
    final (x, y) = pixelOf(51.03, 10.1);
    expect(pixel(png, x + 8, y).a, gbifSharpAlpha);
    expect(pixel(png, x + 9, y).a, gbifSharpAlpha ~/ 2);
    expect(pixel(png, x + 11, y).a, 0);
  });

  test('grob heißt große Scheibe mit kleiner Deckkraft; unbekannt zählt grob',
      () {
    final finds = findsOf([
      (species: 0, lat: 51.03, lon: 10.1, uncertaintyM: 3535, count: 5, year: 2020),
      (species: 0, lat: 51.0, lon: 10.02, uncertaintyM: null, count: 1, year: null),
    ], species: [
      'Hallimasch'
    ]);
    final png = decodePng(
        gbifFillPng(finds, window: window, paint: gbifPaintFor(finds)));
    final (x, y) = pixelOf(51.03, 10.1);
    // 3535 m ≈ 50 px Radius: 40 px daneben liegt noch Scheibe.
    expect(pixel(png, x, y).a, gbifCoarseAlpha);
    expect(pixel(png, x - 40, y).a, gbifCoarseAlpha);
    // Ohne Ampel-Klasse: grau.
    expect(pixel(png, x, y).r, red(AppColors.gbifNoClass.toARGB32()));
    final (x2, y2) = pixelOf(51.0, 10.02);
    expect(pixel(png, x2, y2).a, greaterThan(0),
        reason: 'unbekannte Unschärfe wird als Quadrat gezeichnet');
    expect(pixel(png, x2 + 30, y2).a, greaterThan(0));
  });

  test('Überlagerung verdichtet, aber der Deckel hält', () {
    final rows = <GbifRow>[
      for (var i = 0; i < 12; i++)
        (species: 0, lat: 51.03, lon: 10.1, uncertaintyM: 200 + i, count: 1, year: 2020),
    ];
    final finds = findsOf(rows, species: ['Steinpilz']);
    final png = decodePng(
        gbifFillPng(finds, window: window, paint: gbifPaintFor(finds)));
    final (x, y) = pixelOf(51.03, 10.1);
    expect(pixel(png, x, y).a, gbifMaxAlpha);
    expect(gbifMaxAlpha, lessThan(255));
  });

  test('der Artenfilter zeichnet nur die gewählte Art, der Klassenfilter '
      'lässt Arten ohne Klasse fallen', () {
    final finds = findsOf([
      (species: 0, lat: 51.03, lon: 10.05, uncertaintyM: 250, count: 1, year: 2024),
      (species: 1, lat: 51.03, lon: 10.15, uncertaintyM: 250, count: 1, year: 2024),
      (species: 2, lat: 51.0, lon: 10.1, uncertaintyM: 250, count: 1, year: 2024),
    ], species: [
      'Steinpilz',
      'Pfifferling',
      'Hallimasch'
    ]);
    final (steinpilz) = pixelOf(51.03, 10.05);
    final (pfifferling) = pixelOf(51.03, 10.15);
    final (hallimasch) = pixelOf(51.0, 10.1);

    var png = decodePng(gbifFillPng(finds,
        window: window, paint: gbifPaintFor(finds, species: {'Pfifferling'})));
    expect(pixel(png, steinpilz.$1, steinpilz.$2).a, 0);
    expect(pixel(png, pfifferling.$1, pfifferling.$2).a, gbifSharpAlpha);
    expect(pixel(png, pfifferling.$1, pfifferling.$2).r,
        red(AppColors.gbifClassColours['sommer']!.toARGB32()));
    expect(pixel(png, hallimasch.$1, hallimasch.$2).a, 0);

    png = decodePng(gbifFillPng(finds,
        window: window, paint: gbifPaintFor(finds, classes: {'herbst'})));
    expect(pixel(png, steinpilz.$1, steinpilz.$2).a, gbifSharpAlpha);
    expect(pixel(png, pfifferling.$1, pfifferling.$2).a, 0);
    expect(pixel(png, hallimasch.$1, hallimasch.$2).a, 0,
        reason: 'ohne Klasse fällt die Art bei gesetzter Klassenwahl heraus');

    // Leer = alle, wie im Filter.
    png = decodePng(
        gbifFillPng(finds, window: window, paint: gbifPaintFor(finds)));
    expect(pixel(png, hallimasch.$1, hallimasch.$2).a, gbifSharpAlpha);
  });

  test('die Zeilen liegen MERCATOR-verteilt (#247)', () {
    // Ein hohes Fenster: Grad-linear läge die Mitte ~26 km daneben,
    // hier reicht schon der Unterschied von ein paar Zeilen.
    const tall = FillWindow(
        west: 10.0, east: 10.2, north: 55.0, south: 46.0, width: 20, height: 900);
    const lat = 50.5;
    final finds = findsOf([
      (species: 0, lat: lat, lon: 10.1, uncertaintyM: 250, count: 1, year: 2024),
    ], species: [
      'Steinpilz'
    ]);
    final png = decodePng(
        gbifFillPng(finds, window: tall, paint: gbifPaintFor(finds)));
    // Die Zeile, in der die Scheibe liegt, muss zur Mercator-Breite
    // passen — nicht zur grad-linearen.
    var found = -1;
    for (var y = 0; y < 900; y++) {
      if (pixel(png, 10, y).a > 0) {
        found = y;
        break;
      }
    }
    expect(found, isNot(-1));
    final mercLat = latFromMercatorY(mercatorY(55.0) +
        (found + 3) / 900 * (mercatorY(46.0) - mercatorY(55.0)));
    expect(mercLat, closeTo(lat, 0.05));
    final linearRow = ((55.0 - lat) / 9.0 * 900).floor();
    expect((found - linearRow).abs(), greaterThan(10),
        reason: 'grad-linear läge die Scheibe erkennbar woanders');
  });

  test('über dem Budget werden grobe Scheiben verkleinert gemalt — und '
      'sehen am Ende gleich aus', () {
    final finds = findsOf([
      (species: 0, lat: 51.03, lon: 10.1, uncertaintyM: 3535, count: 5, year: 2020),
      (species: 0, lat: 51.03, lon: 10.1, uncertaintyM: 250, count: 5, year: 2020),
    ], species: [
      'Steinpilz'
    ]);
    final paint = gbifPaintFor(finds);
    final full = decodePng(gbifFillPng(finds, window: window, paint: paint));
    final small = decodePng(
        gbifFillPng(finds, window: window, paint: paint, budget: 500));
    final (x, y) = pixelOf(51.03, 10.1);
    // In der Mitte liegt der scharfe Punkt über dem Quadrat — in
    // beiden Fassungen mit derselben Farbe und praktisch derselben
    // Deckkraft.
    expect(pixel(small, x, y).r, pixel(full, x, y).r);
    expect((pixel(small, x, y).a - pixel(full, x, y).a).abs(), lessThan(4));
    // Am Rand des Quadrats: Der verkleinerte Puffer glättet, aber die
    // Scheibe ist da.
    expect(pixel(small, x - 30, y).a, greaterThan(gbifCoarseAlpha ~/ 2));
    expect(pixel(small, x - 80, y).a, 0);
  });

  test('die Legendenzählung folgt derselben Auswahl wie die Fläche (#279)',
      () {
    // Stünden hier andere Arten als auf der Karte, zählte die Legende
    // Scheiben, die niemand sieht.
    const rows = [
      (species: 'Steinpilz', observations: 5, places: 2, newestYear: 2024),
      (species: 'Maronenröhrling', observations: 2, places: 1, newestYear: 2023),
      (species: 'Pfifferling', observations: 3, places: 1, newestYear: 2022),
      (species: 'Hallimasch', observations: 7, places: 3, newestYear: 2021),
    ];
    final steinpilz = gbifClassKeyFor('Steinpilz')!;
    final pfifferling = gbifClassKeyFor('Pfifferling')!;
    expect(gbifClassKeyFor('Hallimasch'), isNull,
        reason: 'ohne Ampel-Gruppe — sonst prüft die letzte Zeile nichts');
    expect(gbifClassKeyFor('Maronenröhrling'), steinpilz);

    expect(gbifClassCountsFrom(rows),
        {steinpilz: 7, pfifferling: 3, null: 7},
        reason: 'Arten derselben Gruppe addieren sich, ohne Gruppe = null');
    expect(gbifClassCountsFrom(rows, species: {'Steinpilz'}), {steinpilz: 5},
        reason: 'der Artenfilter wie auf der Karte');
    expect(gbifClassCountsFrom(rows, classes: {pfifferling}),
        {pfifferling: 3},
        reason: 'die Gruppenwahl nimmt auch die grauen Arten heraus');
  });
}
