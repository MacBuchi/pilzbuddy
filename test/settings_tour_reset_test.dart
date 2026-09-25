// Das Zurücksetzen der Touren für alle (1.208.0, 1.210.1) geht über neue
// Schlüssel. Zwei Dinge dürfen dabei nicht verloren gehen: dass die Tour
// wirklich wieder kommt, und dass ein Bestandsnutzer trotzdem als
// Bestandsnutzer erkannt wird.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PrefsSettings> _with(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return PrefsSettings(await SharedPreferences.getInstance());
}

void main() {
  test('wer die Touren unter dem Merker von 1.208.0 sah, sieht sie wieder',
      () async {
    final settings = await _with({
      'map_tour_seen_2': true,
      'seen_coach_tours_2': ['buddys', 'pilze', 'spots'],
    });
    expect(settings.mapTourSeen, isFalse);
    expect(settings.seenCoachTours, isEmpty);
    expect(settings.legacyMapTourSeen, isTrue,
        reason: 'kein Neuling — sonst hieße es „Willkommen"');
  });

  test('auch der Merker von vor 1.208.0 zählt als Bestandsnutzer', () async {
    final settings = await _with({'map_tour_seen': true});
    expect(settings.mapTourSeen, isFalse);
    expect(settings.legacyMapTourSeen, isTrue);
  });

  test('eine frische Installation ist kein Bestandsnutzer', () async {
    final settings = await _with({});
    expect(settings.legacyMapTourSeen, isFalse);
  });

  test('nach dem Zurücksetzen wird der neue Merker gemerkt', () async {
    final settings = await _with({'map_tour_seen_2': true});
    await settings.setMapTourSeen(true);
    await settings.setSeenCoachTours({'spots'});
    final again = PrefsSettings(await SharedPreferences.getInstance());
    expect(again.mapTourSeen, isTrue);
    expect(again.seenCoachTours, {'spots'});
  });
}
