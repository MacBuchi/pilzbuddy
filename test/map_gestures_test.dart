// Der Gesten-Schalter der Karte (#210): Langes Draufhalten richtete das
// Fadenkreuz aus UND zoomte auf 16 — ein Fehlgriff aus der Übersicht warf
// einen woanders hin. Entschärfen ging nicht (keine der beiden
// Karten-Bibliotheken lässt Haltedauer oder Toleranz einstellen), also ist
// die Geste ab Werk aus und im Profil zurückholbar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/map/map_gestures.dart';

import 'fakes/fake_backend.dart';
import 'fakes/fake_map_view.dart';
import 'fakes/fake_settings.dart';
import 'fakes/test_app.dart';

void main() {
  FakeBackend signedIn() {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    return backend;
  }

  test('Ab Werk aus, und der Schalter überdauert den Neustart', () {
    final settings = FakeSettings();
    final container = ProviderContainer(
        overrides: [settingsProvider.overrideWithValue(settings)]);
    addTearDown(container.dispose);

    expect(container.read(mapLongPressEnabledProvider), isFalse);

    container.read(mapLongPressEnabledProvider.notifier).toggle();
    expect(container.read(mapLongPressEnabledProvider), isTrue);
    expect(settings.mapLongPressEnabled, isTrue,
        reason: 'Ohne Speichern wäre die Geste nach jedem Start wieder weg '
            '— dieselbe Lehre wie beim Offline-Schalter (#145).');
  });

  test('Gespeichertes „an" gilt beim nächsten Start', () {
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWithValue(FakeSettings(mapLongPressEnabled: true)),
    ]);
    addTearDown(container.dispose);
    expect(container.read(mapLongPressEnabledProvider), isTrue);
  });

  testWidgets('Der Profil-Schalter schaltet die Geste auf der Karte frei',
      (tester) async {
    // Der ganze Weg: Schalter im Profil → Einstellung → Karte. Sonst
    // bewiese der Provider-Test nur sich selbst.
    final settings = FakeSettings();
    await pumpApp(tester, signedIn(), settings: settings);

    expect(tester.widget<FakeMapView>(find.byType(FakeMapView)).config.onLongPress,
        isNull);
    // Ohne die Geste steht auch ihre Erklärung nicht dauerhaft im Bild.
    expect(find.text('Gedrückt halten richtet das Fadenkreuz aus'),
        findsNothing);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Karte gedrückt halten'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Karte gedrückt halten'));
    await settle(tester);
    expect(settings.mapLongPressEnabled, isTrue);

    await tester.tap(find.text('Karte'));
    await settle(tester);
    expect(tester.widget<FakeMapView>(find.byType(FakeMapView)).config.onLongPress,
        isNotNull);
    expect(find.text('Gedrückt halten richtet das Fadenkreuz aus'),
        findsOneWidget);
  });
}
