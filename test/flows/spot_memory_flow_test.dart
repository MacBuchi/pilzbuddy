// Die Spot-Erinnerung auf der Karte: Banner, Antippen, Stummschalten.
// Die Auswahlregeln selbst prüft test/spot_memory_test.dart.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/map/widgets/map_banners.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  /// Ein Fund am selben Kalendertag wie heute, aber im Vorjahr — so ist
  /// der Test unabhängig davon, wann er läuft (die Erinnerung rechnet
  /// gegen `DateTime.now()`).
  DateTime lastYearToday() {
    final now = DateTime.now();
    // 28. Februar statt 29. — ein Schaltjahrestag im Vorjahr existiert
    // nicht zwingend.
    final day = now.month == 2 && now.day == 29 ? 28 : now.day;
    return DateTime(now.year - 1, now.month, day);
  }

  testWidgets('Erinnerung erscheint, öffnet den Spot und bleibt danach '
      'stumm', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
        ownerId: me.id,
        name: 'Buchenhang',
        species: 'Steinpilz',
        foundOn: lastYearToday());
    final settings = FakeSettings();

    await pumpApp(tester, backend, settings: settings);

    expect(find.textContaining('Erinnerung: Buchenhang'), findsOneWidget);
    expect(find.textContaining('Steinpilz'), findsOneWidget);

    // Antippen öffnet den Spot UND schaltet stumm — wer hingesehen hat,
    // braucht den Hinweis morgen nicht noch einmal.
    await tester.tap(find.textContaining('Erinnerung: Buchenhang'));
    await settle(tester);
    expect(find.text('Buchenhang'), findsWidgets, reason: 'Spot-Blatt offen');
    expect(settings.spotMemoryDismissedUntil, isNotNull);

    // Blatt zu: Das Banner ist weg und kommt in dieser Sitzung nicht
    // wieder.
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(find.textContaining('Erinnerung: Buchenhang'), findsNothing);
  });

  testWidgets('eine abgelaufene Stummschaltung erinnert wieder',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
        ownerId: me.id,
        name: 'Buchenhang',
        species: 'Steinpilz',
        foundOn: lastYearToday());

    // Stummschaltung von gestern — das nächste Zeitfenster soll den
    // Hinweis wieder zeigen, sonst verstummt die Erinnerung für immer.
    final settings = FakeSettings()
      ..spotMemoryDismissedUntil =
          DateTime.now().toUtc().subtract(const Duration(days: 1));
    await pumpApp(tester, backend, settings: settings);

    expect(find.textContaining('Erinnerung: Buchenhang'), findsOneWidget);
  });

  testWidgets('ohne passenden Fund gibt es kein Banner', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    // Fund aus dem laufenden Jahr: bekannt, keine Erinnerung.
    backend.addSpot(
        ownerId: me.id,
        name: 'Frisch',
        species: 'Steinpilz',
        foundOn: DateTime.now().subtract(const Duration(days: 3)));

    await pumpApp(tester, backend);

    expect(find.textContaining('Erinnerung:'), findsNothing);
  });

  test('der Dismiss-Provider liest den gespeicherten Wert', () {
    // Die Naht zwischen Settings und Banner — ohne sie käme die
    // Stummschaltung nach einem Neustart nicht an.
    final settings = FakeSettings()
      ..spotMemoryDismissedUntil = DateTime.utc(2026, 9, 30);
    final container = ProviderContainer(
        overrides: [settingsProvider.overrideWithValue(settings)]);
    addTearDown(container.dispose);
    expect(container.read(spotMemoryDismissedProvider),
        DateTime.utc(2026, 9, 30));
  });
}
