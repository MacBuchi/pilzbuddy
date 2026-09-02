// Der `geo:`-URI, mit dem ein Spot an eine Navi-App geht (#367).
//
// Zwei Dinge daran sind leicht zu übersehen und beide still: eine
// Klammer im Spot-Namen zerlegt den URI, und `geo:0,0?q=…` (die
// verbreitete Kurzform) schickt jede App, die `q` ignoriert, in den Golf
// von Guinea.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/spot_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('geoUriFor', () {
    test('trägt die Koordinate zweimal — im Pfad und in der Suche', () {
      final uri = geoUriFor(lat: 51.1634, lng: 10.4477);

      expect(uri.scheme, kGeoScheme);
      expect(uri.path, '51.163400,10.447700',
          reason: 'Apps, die `q` ignorieren, zentrieren auf den Pfad');
      expect(uri.queryParameters['q'], '51.163400,10.447700');
    });

    test('rundet auf sechs Stellen — mehr wäre erfundene Genauigkeit', () {
      final uri = geoUriFor(lat: 51.16341234567, lng: -10.4477987654);

      expect(uri.path, '51.163412,-10.447799');
    });

    test('hängt den Namen als Pin-Titel an', () {
      final uri = geoUriFor(lat: 51.0, lng: 10.0, label: 'Buchenhang');

      expect(uri.toString(), 'geo:51.000000,10.000000'
          '?q=51.000000,10.000000(Buchenhang)');
    });

    test('kodiert den Namen, statt ihn roh einzusetzen', () {
      final uri = geoUriFor(lat: 51.0, lng: 10.0, label: 'Am Bach & Weg');

      expect(uri.toString(), contains('(Am%20Bach%20%26%20Weg)'));
    });

    test('Klammern im Namen zerlegen den URI nicht', () {
      // Ohne das Aussieben stünde hier `…(Hang (oben))` — die Ziel-App
      // liest bis zur ersten schließenden Klammer und der Rest wandert
      // in den Titel oder verwirft ihn ganz.
      final uri = geoUriFor(lat: 51.0, lng: 10.0, label: 'Hang (oben)');

      expect(uri.queryParameters['q'], '51.000000,10.000000(Hang oben)');
    });

    test('ein leerer Name lässt die Klammern ganz weg', () {
      final uri = geoUriFor(lat: 51.0, lng: 10.0, label: '   ');

      expect(uri.toString(),
          'geo:51.000000,10.000000?q=51.000000,10.000000');
    });

    test('ein langer Name wird gekürzt, nicht durchgereicht', () {
      final uri = geoUriFor(lat: 51.0, lng: 10.0, label: 'A' * 200);

      final label = uri.queryParameters['q']!.split('(').last;
      expect(label.length, lessThanOrEqualTo(kMaxLabelLength + 2),
          reason: 'Gekürztes plus Auslassungszeichen plus Klammer');
      expect(label, endsWith('…)'));
    });
  });

  group('formatCoordinates', () {
    test('schreibt einen Punkt, unabhängig von der Sprache', () {
      expect(formatCoordinates(51.1634, 10.4477), '51.163400, 10.447700');
    });
  });

  group('openInNavigationApp', () {
    late List<String> clipboard;

    setUp(() {
      clipboard = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('öffnet den App-Wähler und meldet sonst nichts', () async {
      Uri? launched;
      final outcome = await openInNavigationApp(
        lat: 51.1634,
        lng: 10.4477,
        label: 'Buchenhang',
        launch: (uri) async {
          launched = uri;
          return true;
        },
      );

      expect(outcome, SpotNavigationOutcome.opened);
      expect(launched, geoUriFor(lat: 51.1634, lng: 10.4477,
          label: 'Buchenhang'));
      expect(clipboard, isEmpty,
          reason: 'die Zwischenablage ist der Rückfallweg, nicht der Weg');
    });

    test('ohne Navi-App landet die Koordinate in der Zwischenablage',
        () async {
      final outcome = await openInNavigationApp(
        lat: 51.1634,
        lng: 10.4477,
        launch: (_) async => false,
      );

      expect(outcome, SpotNavigationOutcome.copiedNoNaviApp);
      expect(clipboard, ['51.163400, 10.447700']);
    });

    test('eine Ausnahme aus url_launcher ist derselbe Fall', () async {
      // Je nach Android-Fassung meldet das Paket „niemand nimmt das an"
      // als `false` ODER als `PlatformException`. Fiele die zweite
      // Fassung durch, stünde am Knopf ein roter Bildschirm statt einer
      // Koordinate.
      final outcome = await openInNavigationApp(
        lat: 51.1634,
        lng: 10.4477,
        launch: (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
      );

      expect(outcome, SpotNavigationOutcome.copiedNoNaviApp);
      expect(clipboard, ['51.163400, 10.447700']);
    });
  });
}
