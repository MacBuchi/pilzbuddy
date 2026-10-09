// Im Browser packt der Browser aus (#689): `preInflate` gibt die Bytes
// an `DecompressionStream` und legt das Ergebnis für `gunzip` bereit.
//
// Läuft NUR in Chrome (CI-Schritt „Web-Test auf dart2js"). Ein grüner
// Lauf allein bewiese nichts — fiele `preInflate` still aus, packte
// `gunzip` in Dart aus und lieferte dieselben Bytes. Deshalb prüft der
// Test ausdrücklich, dass etwas BEREITLAG.
@TestOn('browser')
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipEncoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/gunzip.dart';
import 'package:pilzbuddy/core/gunzip_web.dart' show debugInflatedReady;

Uint8List gz(Uint8List raw) => Uint8List.fromList(GZipEncoder().encode(raw)!);

void main() {
  test('nativ ausgepackt, bereitgelegt und genau einmal genommen', () async {
    final r = Random(7);
    final raw = Uint8List(300000);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = r.nextInt(6) == 0 ? r.nextInt(256) : 0;
    }
    final packed = gz(raw);
    await preInflate(packed);
    expect(debugInflatedReady(packed), isTrue);
    expect(gunzip(packed), raw);
    expect(debugInflatedReady(packed), isFalse);
    // Danach packt `gunzip` wieder selbst aus — dieselben Bytes.
    expect(gunzip(packed), raw);
  });

  test('abgeschnitten: nichts bereit, gunzip wirft wie bisher', () async {
    final raw = Uint8List(50000)..fillRange(0, 50000, 3);
    final packed = gz(raw);
    final cut = Uint8List.fromList(packed.sublist(0, packed.length ~/ 2));
    await preInflate(cut);
    expect(debugInflatedReady(cut), isFalse);
    expect(() => gunzip(cut), throwsFormatException);
  });
}
