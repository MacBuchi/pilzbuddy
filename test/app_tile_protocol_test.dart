// Das Kachel-Protokoll der App für MapLibre GL JS im Browser (#689): Der
// Router zerlegt `pilzbuddy://<quelle>/{z}/{x}/{y}` und fragt die richtige
// Quelle. Diese Tests beweisen die Zusagen, auf denen die Zahl der
// R2-Anfragen und die Korrektheit hängen — das Anmelden beim Browser
// selbst prüft nur der Prüfstand (`docs/map-performance.md`).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/app_tile_protocol.dart';

void main() {
  test('die Vorlage zerlegt sich zurück in Quelle und Kachel — auch mit / '
      'im Schlüssel', () async {
    final asked = <String>[];
    final router = AppTileRouter()
      ..replaceSources({
        'area-a/1': AppTileSource((z, x, y) async {
          asked.add('$z/$x/$y');
          return Uint8List.fromList([z, x, y]);
        }, gzip: true),
      });
    final url = AppTileRouter.urlTemplate('area-a/1')
        .replaceAll('{z}', '9')
        .replaceAll('{x}', '271')
        .replaceAll('{y}', '178');
    expect(url, startsWith('pilzbuddy://'));
    final tile = await router.load(url);
    expect(asked, ['9/271/178']);
    expect(tile!.bytes, [9, 271 & 0xff, 178]);
    expect(tile.gzip, isTrue);
  });

  test('unbekannte Quelle oder fremde Adresse ⇒ keine Kachel, kein Wurf',
      () async {
    final router = AppTileRouter()
      ..replaceSources({
        'overview': AppTileSource((z, x, y) async => Uint8List(1), gzip: false),
      });
    expect(await router.load('pilzbuddy://online-alt/1/0/0'), isNull);
    expect(await router.load('pmtiles://overview/1/0/0'), isNull);
    expect(await router.load('pilzbuddy://overview/1/0'), isNull);
  });

  test('replaceSources: eine Quelle, die der neue Style nicht mehr nennt, '
      'liefert nichts mehr', () async {
    final router = AppTileRouter()
      ..replaceSources({
        'area-a': AppTileSource((z, x, y) async => Uint8List(1), gzip: false),
      });
    expect(await router.load('pilzbuddy://area-a/8/0/0'), isNotNull);
    router.replaceSources({});
    expect(await router.load('pilzbuddy://area-a/8/0/0'), isNull);
  });

  test('Netzquelle: gleiche Kachel gleichzeitig ⇒ EIN Abruf; danach aus dem '
      'Speicher; eine Lücke wird einmal gefragt', () async {
    final asked = <String>[];
    final gate = Completer<void>();
    final router = AppTileRouter()
      ..replaceSources({
        'online-dach-20260928': AppTileSource((z, x, y) async {
          asked.add('$z/$x/$y');
          await gate.future;
          return y == 0 ? null : Uint8List(10);
        }, gzip: true, remote: true),
      });
    const url = 'pilzbuddy://online-dach-20260928/9/1/1';
    final a = router.load(url);
    final b = router.load(url);
    gate.complete();
    await Future.wait([a, b]);
    expect(asked, ['9/1/1'], reason: 'zwei Anfragen vor der Antwort');
    await router.load(url);
    expect(asked, ['9/1/1'], reason: 'abgelegt — R2 wird nicht neu gefragt');

    expect(await router.load('pilzbuddy://online-dach-20260928/9/1/0'), isNull);
    expect(await router.load('pilzbuddy://online-dach-20260928/9/1/0'), isNull);
    expect(asked, ['9/1/1', '9/1/0'], reason: 'Lücke nur einmal gefragt');
  });

  test('der Speicher hält seine Grenze und verdrängt das am längsten '
      'Unbenutzte', () async {
    var calls = 0;
    final router = AppTileRouter(maxCacheBytes: 25)
      ..replaceSources({
        'online-x': AppTileSource((z, x, y) async {
          calls++;
          return Uint8List(10);
        }, gzip: true, remote: true),
      });
    String u(int x) => 'pilzbuddy://online-x/9/$x/1';
    await router.load(u(1));
    await router.load(u(2));
    await router.load(u(1)); // 1 jetzt zuletzt benutzt
    await router.load(u(3)); // 30 > 25 ⇒ 2 fällt heraus
    expect(calls, 3);
    await router.load(u(1));
    expect(calls, 3, reason: '1 blieb liegen');
    await router.load(u(2));
    expect(calls, 4, reason: '2 war verdrängt');
  });

  test('lokale Quelle (Übersicht, Bereich) wird nicht doppelt abgelegt',
      () async {
    var calls = 0;
    final router = AppTileRouter()
      ..replaceSources({
        'overview': AppTileSource((z, x, y) async {
          calls++;
          return Uint8List(10);
        }, gzip: true),
      });
    await router.load('pilzbuddy://overview/5/1/1');
    await router.load('pilzbuddy://overview/5/1/1');
    expect(calls, 2,
        reason: 'Die Übersicht liegt schon ganz im Speicher; eine Kopie '
            'wäre nur Platz');
  });
}
