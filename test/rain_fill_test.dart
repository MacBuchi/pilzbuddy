// Die eingefärbte Fläche zwischen den Höhenlinien.
//
// Ein selbst gebautes PNG ist die Sorte Code, die entweder funktioniert
// oder ein leeres Rechteck ergibt — und auf der Karte ist zwischen
// „durchsichtig, weil trocken" und „durchsichtig, weil kaputt" nichts zu
// sehen. Deshalb wird hier zurückdekodiert statt nur die Länge geprüft.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/map/rain_fill.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';

import 'rain_grid_test.dart' show gridOf;

/// Liest das erzeugte PNG wieder aus — Kopfdaten und rohe Bildpunkte.
({int width, int height, Uint8List pixels}) decodePng(Uint8List bytes) {
  expect(bytes.sublist(0, 8),
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      reason: 'PNG-Signatur');
  var offset = 8;
  int width = 0, height = 0;
  final data = BytesBuilder();
  while (offset < bytes.length) {
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes + offset);
    final length = view.getUint32(0);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final body = bytes.sublist(offset + 8, offset + 8 + length);
    // Die Prüfsumme jedes Blocks: Ein Bild mit falscher CRC zeigen manche
    // Decoder trotzdem an und andere nicht — das ist genau der Fehler,
    // der erst auf einem fremden Gerät auffällt.
    final expected = ByteData.view(bytes.buffer,
            bytes.offsetInBytes + offset + 8 + length)
        .getUint32(0);
    expect(getCrc32(bytes.sublist(offset + 4, offset + 8 + length)), expected,
        reason: 'CRC von $type');
    if (type == 'IHDR') {
      width = ByteData.view(body.buffer, body.offsetInBytes).getUint32(0);
      height = ByteData.view(body.buffer, body.offsetInBytes).getUint32(4);
      expect(body[8], 8, reason: 'Bittiefe');
      expect(body[9], 6, reason: 'RGBA');
    } else if (type == 'IDAT') {
      data.add(body);
    } else if (type == 'IEND') {
      break;
    }
    offset += 12 + length;
  }
  final raw = const ZLibDecoder().decodeBytes(data.toBytes());
  final pixels = Uint8List(width * height * 4);
  var source = 0, target = 0;
  for (var y = 0; y < height; y++) {
    expect(raw[source++], 0, reason: 'Filter der Zeile $y');
    for (var i = 0; i < width * 4; i++) {
      pixels[target++] = raw[source++];
    }
  }
  return (width: width, height: height, pixels: pixels);
}

void main() {
  const levels = [10, 20, 30];

  test('malt jede Zelle in der Farbe ihres Bandes', () {
    final grid = gridOf([
      [5, 15],
      [25, 35],
    ]);
    final image = decodePng(rainFillPng(grid, levels: levels, smooth: false));
    expect(image.width, 2);
    expect(image.height, 2);

    ({int r, int g, int b, int a}) at(int x, int y) {
      final o = (y * image.width + x) * 4;
      return (
        r: image.pixels[o],
        g: image.pixels[o + 1],
        b: image.pixels[o + 2],
        a: image.pixels[o + 3],
      );
    }

    // 5 mm liegt unter der untersten Linie — keine Farbe.
    expect(at(0, 0).a, 0);
    // 15, 25 und 35 liegen im ersten, zweiten und dritten Band.
    for (final (position, band) in [((1, 0), 0), ((0, 1), 1), ((1, 1), 2)]) {
      final pixel = at(position.$1, position.$2);
      final expected = AppColors.rainLine(band);
      expect(pixel.r, (expected.r * 255).round(), reason: 'Band $band rot');
      expect(pixel.g, (expected.g * 255).round(), reason: 'Band $band grün');
      expect(pixel.b, (expected.b * 255).round(), reason: 'Band $band blau');
      expect(pixel.a, rainFillAlpha, reason: 'Band $band Deckkraft');
    }
  });

  test('lässt Zellen ohne Daten durchsichtig', () {
    final grid = gridOf([
      [rainNoData, 35],
    ]);
    final image =
        decodePng(rainFillPng(grid, levels: levels, smooth: false));
    expect(image.pixels[3], 0, reason: 'keine Daten ⇒ keine Farbe');
    expect(image.pixels[7], rainFillAlpha);
  });

  test('zeichnet dasselbe Feld wie die Höhenlinien — also geglättet', () {
    // Die Linien entstehen aus `grid.smoothed()`. Zeichnete die Fläche
    // das rohe Gitter, stünden zwei verschiedene Wahrheiten übereinander:
    // eine Linie „30 mm" mitten in einer Fläche, die dort schon zum
    // nächsten Band gehört — und Sprenkel genau dort, wo bewusst keine
    // Linie gezogen wird.
    final grid = gridOf([
      [0, 0, 0, 0, 0],
      [0, 40, 0, 90, 0],
      [0, 0, 0, 0, 0],
    ]);
    expect(rainFillPng(grid, levels: levels),
        rainFillPng(grid.smoothed(), levels: levels, smooth: false),
        reason: 'Glätten ist die Vorgabe, nicht die Ausnahme');
    expect(rainFillPng(grid, levels: levels),
        isNot(rainFillPng(grid, levels: levels, smooth: false)),
        reason: 'sonst prüft die Zeile darüber nichts');
  });

  test('bleibt in dem Fenster, das am Gerät lesbar war', () {
    // Beide Grenzen sind gemessen, keine Geschmacksfrage (2026-08-04,
    // Ausschnitt Kassel–Göttingen, drei gebaute Varianten):
    //
    // - Bei 82 (32 %) verschob die Fläche die Kartenfarben nur um
    //   (−33, −20, −31) von 255. Der Betreiber las das als „die Flächen
    //   sind gar nicht ausgefüllt" — zwei benachbarte Bänder waren nicht
    //   zu unterscheiden.
    // - Bei 190 (75 %) waren die Bänder sehr klar und die Ortsnamen
    //   verblasst. Das ist derselbe Befund, an dem die Vollfläche in
    //   1.45.0 gescheitert ist.
    //
    // Dazwischen liegt das Fenster. Wer hier hinausläuft, macht die
    // Karte unlesbar oder die Bänder unsichtbar — beides ist am Gerät
    // schon einmal passiert.
    expect(rainFillAlpha, greaterThan(102),
        reason: 'darunter sind die Bänder nicht zu unterscheiden');
    expect(rainFillAlpha, lessThan(190),
        reason: 'darüber verschwindet die Karte — der Befund aus 1.45.0');
  });

  test('hat für jede Höhenstufe eine eigene Farbe', () {
    // Zwei Bänder in derselben Farbe wären eine Karte, die zwei
    // verschiedene Regenmengen gleich aussehen lässt.
    final seen = <int>{};
    for (var band = 0; band < levels.length; band++) {
      expect(seen.add(AppColors.rainLine(band).toARGB32()), isTrue,
          reason: 'Band $band wiederholt eine Farbe');
    }
  });

  test('kommt mit dem echten Gitterformat zurecht', () {
    // Ein Gitter in der Größenordnung Deutschlands: Das PNG muss
    // vollständig sein, nicht nur die erste Zeile.
    final rows = [
      for (var y = 0; y < 60; y++) [for (var x = 0; x < 80; x++) (x + y) % 45]
    ];
    final image = decodePng(rainFillPng(gridOf(rows), levels: levels));
    expect(image.width, 80);
    expect(image.height, 60);
    expect(image.pixels.length, 80 * 60 * 4);
    expect(image.pixels.any((byte) => byte != 0), isTrue,
        reason: 'ein leeres Bild wäre auf der Karte nicht zu unterscheiden');
  });
}
