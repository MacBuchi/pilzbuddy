// Neue Karte ab Werk an und Kartenbereiche auf neuem Stand (#630,
// Stufe 3): was veraltet ist, wann der Nachlauf startet und wann er
// anhält, und die Vorgaben der beiden Schalter.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/offline_areas/area_auto_update.dart';
import 'package:pilzbuddy/features/offline_areas/area_plan.dart';
import 'package:pilzbuddy/features/offline_areas/area_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

StoredArea _area(String id, String build) => StoredArea(
      id: id,
      name: id,
      bounds: const AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7),
      minZoom: 8,
      maxZoom: 13,
      build: build,
      tiles: 10,
      bytes: 1000,
      savedAt: DateTime.utc(2026, 9, 30),
    );

void main() {
  final old = _area('alt', '20260828');
  final fresh = _area('neu', '20260928');

  test('veraltet ist, was älter ist als der Stand des Hosts', () {
    expect(staleAreas([old, fresh], '20260928'), [old]);
    expect(staleAreas([old, fresh], null), isEmpty,
        reason: 'ohne Manifest (kein Empfang, Schalter aus) nichts');
    expect(staleAreas([old, fresh], '20260801'), isEmpty);
  });

  ({StoredArea? start, bool cancel}) plan({
    bool enabled = true,
    bool freeNetwork = true,
    bool inForeground = true,
    List<StoredArea>? stale,
    bool busy = false,
    String? autoRunning,
    Set<String> failed = const {},
  }) =>
      planAutoAreaUpdate(
        enabled: enabled,
        freeNetwork: freeNetwork,
        inForeground: inForeground,
        stale: stale ?? [old],
        busy: busy,
        autoRunning: autoRunning,
        failed: failed,
      );

  test('startet im freien Netz im Vordergrund mit dem ersten veralteten', () {
    expect(plan().start, old);
    expect(plan().cancel, isFalse);
  });

  test('startet nicht: Schalter aus, kostenpflichtig, Hintergrund, belegt, '
      'gescheitert', () {
    expect(plan(enabled: false).start, isNull);
    expect(plan(freeNetwork: false).start, isNull);
    expect(plan(inForeground: false).start, isNull);
    expect(plan(busy: true).start, isNull);
    expect(plan(failed: {'alt'}).start, isNull);
  });

  test('hält den EIGENEN Download an, wenn das freie Netz geht — sonst '
      'keinen', () {
    expect(plan(freeNetwork: false, autoRunning: 'alt').cancel, isTrue);
    expect(plan(enabled: false, autoRunning: 'alt').cancel, isTrue);
    expect(plan(freeNetwork: false, busy: true).cancel, isFalse,
        reason: 'ein angetippter Download gehört der Nutzerin');
    expect(plan(inForeground: false, autoRunning: 'alt').cancel, isFalse,
        reason: 'der Hintergrund allein hält nichts an');
  });

  test('Vorgaben: Neue Karte an, Bereiche automatisch aktualisieren an',
      () async {
    SharedPreferences.setMockInitialValues({});
    final settings = PrefsSettings(await SharedPreferences.getInstance());
    expect(settings.newMapEnabled, isTrue);
    expect(settings.areaAutoUpdateEnabled, isTrue);
    await settings.setNewMapEnabled(false);
    expect(settings.newMapEnabled, isFalse,
        reason: 'wer sie abschaltet, behält das');
  });
}
