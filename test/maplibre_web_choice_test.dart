// Web-Vorgabe der Karten-Engine (#689, seit 1.225.0): MapLibre GL JS,
// außer der Browser hat mit `?maplibre=0` abgewählt. Die Browser-Datei
// läuft nur in dart2js; die Entscheidung selbst prüft die VM hier.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/map_view/maplibre_web_choice.dart';

bool chosen(String? param, String? stored) =>
    mapLibreChosen(storedMapLibreChoice(param, stored));

void main() {
  test('ohne Parameter und ohne Gemerktes: MapLibre', () {
    expect(chosen(null, null), isTrue);
  });

  test('?maplibre=0 wählt flutter_map und wird gemerkt', () {
    expect(storedMapLibreChoice('0', null), '0');
    expect(chosen('0', null), isFalse);
    // Nächster Start der PWA ohne Parameter: bleibt abgewählt.
    expect(chosen(null, '0'), isFalse);
  });

  test('?maplibre=1 nimmt den Ausstieg zurück', () {
    expect(storedMapLibreChoice('1', '0'), isNull);
    expect(chosen('1', '0'), isTrue);
  });

  test('eine 1 aus der Versuchszeit bleibt MapLibre', () {
    expect(chosen(null, '1'), isTrue);
  });

  test('unbekannter Wert ändert nichts am Gemerkten', () {
    expect(storedMapLibreChoice('ja', '0'), '0');
    expect(chosen('ja', null), isTrue);
  });
}
