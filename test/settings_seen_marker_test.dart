// Der „gesehen bis"-Marker fürs Buddy-Fund-Banner (#202): die erste
// Nicht-Bool-Einstellung. Der Roundtrip über den ISO-String und der
// Erstlauf-Schutz sind genau die Stellen, die still falsch sein könnten.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_settings.dart';

void main() {
  test('ensureFindSeenMarker setzt nur bei null', () async {
    final fresh = FakeSettings();
    await ensureFindSeenMarker(fresh, now: DateTime.utc(2026, 8, 5));
    expect(fresh.lastFindSeenAt, DateTime.utc(2026, 8, 5));

    final existing =
        FakeSettings(lastFindSeenAt: DateTime.utc(2026, 8, 1));
    await ensureFindSeenMarker(existing, now: DateTime.utc(2026, 8, 5));
    expect(existing.lastFindSeenAt, DateTime.utc(2026, 8, 1),
        reason: 'ein gesetzter Marker darf nie zurückspringen');
  });

  test('PrefsSettings: Roundtrip über den ISO-String', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = PrefsSettings(await SharedPreferences.getInstance());
    expect(settings.lastFindSeenAt, isNull);

    await settings.setLastFindSeenAt(DateTime.utc(2026, 8, 5, 12, 30));
    expect(settings.lastFindSeenAt, DateTime.utc(2026, 8, 5, 12, 30));
  });

  test('PrefsSettings: kaputter Wert liest sich als null, nicht als Wurf',
      () async {
    SharedPreferences.setMockInitialValues(
        {'last_find_seen_at': 'kein-datum'});
    final settings = PrefsSettings(await SharedPreferences.getInstance());
    expect(settings.lastFindSeenAt, isNull);
  });
}
