// Nativ und im Browser dieselben Bytes (#641): `gunzip` nimmt auf
// Android das zlib der Plattform statt `package:archive`. Beide Wege
// müssen Byte für Byte dasselbe liefern — sonst sähe die PWA andere
// Gitter als das Telefon.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/gunzip_io.dart' as native;
import 'package:pilzbuddy/core/gunzip_web.dart' as web;

void main() {
  test('Zufallsdaten: beide Wege, dieselben Bytes', () {
    final r = Random(7);
    final raw = Uint8List(300000);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = r.nextInt(6) == 0 ? r.nextInt(256) : 0;
    }
    final gz = gzip.encode(raw);
    expect(native.gunzip(gz), raw);
    expect(web.gunzip(gz), raw);
  });

  test('die ausgelieferten Gitter: beide Wege, dieselben Bytes', () {
    final assets = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.gz'))
        .toList();
    expect(assets, isNotEmpty);
    for (final f in assets) {
      final gz = f.readAsBytesSync();
      expect(native.gunzip(gz), web.gunzip(gz), reason: f.path);
    }
  });

  test('abgeschnittene Daten werfen auf beiden Wegen', () {
    // Beide Entpacker lieferten hier still den Teil bis zum Abbruch
    // (nachgemessen). Die Stationstabelle wird nur „zur Probe"
    // ausgepackt, bevor sie in den Zwischenspeicher geht — ein stiller
    // Teil hätte einen abgebrochenen Download dort festgeschrieben.
    final raw = Uint8List(50000)..fillRange(0, 50000, 3);
    final gz = gzip.encode(raw);
    final cut = gz.sublist(0, gz.length ~/ 2);
    for (final unpack in [native.gunzip, web.gunzip]) {
      expect(() => unpack(cut), throwsFormatException);
    }
  });

  test('Bereitgelegtes nimmt gunzip genau einmal (#689)', () {
    final raw = Uint8List(1000)..fillRange(0, 1000, 5);
    final gz = Uint8List.fromList(gzip.encode(raw));
    final prepared = Uint8List.fromList(raw);
    web.rememberInflated(gz, prepared);
    expect(web.debugInflatedReady(gz), isTrue);
    expect(identical(web.gunzip(gz), prepared), isTrue);
    expect(web.debugInflatedReady(gz), isFalse);
    expect(identical(web.gunzip(gz), prepared), isFalse);
  });

  test('Bereitgelegtes mit falscher Länge bleibt nicht liegen (#689)', () {
    // Der native Weg prüft wie `gunzip` gegen den Abspann — sonst
    // schlüpfte ein abgeschnittener Strom an der Prüfung vorbei.
    final raw = Uint8List(1000)..fillRange(0, 1000, 5);
    final gz = Uint8List.fromList(gzip.encode(raw));
    web.rememberInflated(gz, Uint8List(999));
    expect(web.debugInflatedReady(gz), isFalse);
    expect(web.gunzip(gz), raw);
  });
}
