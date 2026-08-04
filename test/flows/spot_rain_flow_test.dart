// Der Regen am Spot, vom Blatt aus: fragen → laden → Zahlen und Balken.
//
// Der Weg wird ganz gegangen, weil die Teile ihn nicht beweisen: Eine
// korrekt gerechnete Summe nützt nichts, wenn der Abschnitt nie erscheint
// oder ungefragt lädt — und „lädt nicht ungefragt" ist hier eine Zusage
// an die Nutzerin, keine Feinheit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';
import '../rain_grid_test.dart' show encode;

void main() {
  const spotLat = 51.0;
  const spotLng = 11.0;

  /// Ein Stapel über Deutschland: eine Zelle, alle Tage am selben Punkt.
  RainStackData stackOf(List<int> mmPerDay) => RainStackData(
        info: RainStackInfo(
          width: 1,
          height: 1,
          west: 10,
          east: 12,
          north: 52,
          south: 50,
          days: const [],
        ),
        days: [
          for (final (index, mm) in mmPerDay.indexed)
            (
              date: DateTime.utc(2026, 7, 21).add(Duration(days: index)),
              gzipped: encode([
                [mm]
              ]),
            ),
        ],
      );

  FakeBackend loggedInWithSpot() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
      ownerId: me.id,
      lat: spotLat,
      lng: spotLng,
      name: 'Buchenhang',
      species: 'Steinpilz',
    );
    return backend;
  }

  /// Wartet, bis der Verlauf gerechnet ist. Er läuft im Isolate, dafür
  /// braucht der Test echte Zeit — `settle` pumpt nur Bilder.
  Future<void> settleCourse(WidgetTester tester,
      {double lat = spotLat, double lon = spotLng}) async {
    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    await tester.runAsync(
        () => container.read(rainCourseProvider((lat: lat, lon: lon)).future));
    await settle(tester);
  }

  Future<void> openSpot(WidgetTester tester, [String name = 'Buchenhang']) async {
    // Der Marker trägt den Namen als Tooltip, nicht als Text — auf der
    // Karte steht er nirgends geschrieben.
    await tester.tap(find.byTooltip(name));
    await settle(tester);
  }

  testWidgets('lädt nichts, bevor jemand zustimmt', (tester) async {
    // Rund 0,9 MB gibt man im Wald nicht ungefragt aus — dieselbe Zusage
    // wie bei der Regenebene seit 1.45.0.
    var calls = 0;
    final backend = loggedInWithSpot();
    await pumpApp(tester, backend, extraOverrides: [
      rainStackLoaderProvider.overrideWithValue(() async {
        calls++;
        return stackOf([5]);
      }),
    ]);
    await openSpot(tester);

    expect(find.text('Regendaten laden'), findsOneWidget);
    expect(calls, 0, reason: 'ungefragt geladen');
    expect(find.textContaining('mm'), findsNothing);
  });

  testWidgets('nach dem Tipp stehen Summen und Verlauf da', (tester) async {
    final backend = loggedInWithSpot();
    await pumpApp(tester, backend, extraOverrides: [
      rainStackLoaderProvider.overrideWithValue(
          () async => stackOf([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])),
    ]);
    await openSpot(tester);
    await tester.tap(find.text('Regendaten laden'));
    await settleCourse(tester);

    // 7 Tage = 8+9+…+14 = 77, 14 Tage = 1+2+…+14 = 105.
    //
    // Geprüft wird das PAAR aus Beschriftung und Zahl, nicht nur, dass
    // beide Zahlen irgendwo stehen: Vertauschte Fenster zeigen dieselben
    // zwei Zahlen an den falschen Zeilen, und niemand sieht es.
    Finder sumRow(String label, String value) => find.ancestor(
          of: find.text(value),
          matching: find.widgetWithText(Row, label),
        );
    expect(sumRow('7 Tage', '77 mm'), findsOneWidget);
    expect(sumRow('14 Tage', '105 mm'), findsOneWidget);
    expect(find.textContaining('höchster Tageswert'), findsOneWidget,
        reason: 'der Satz, den eine Summe nicht sagen kann');
    expect(find.textContaining('nur Deutschland'), findsOneWidget,
        reason: 'ohne diesen Satz sieht ein leerer Abschnitt in Österreich '
            'nach einem Fehler der App aus');
  });

  testWidgets('die Zustimmung wird gemerkt, nicht bei jedem Spot neu gefragt',
      (tester) async {
    final settings = FakeSettings();
    final backend = loggedInWithSpot();
    await pumpApp(tester, backend, settings: settings,
        extraOverrides: [
          rainStackLoaderProvider.overrideWithValue(() async => stackOf([5])),
        ]);
    await openSpot(tester);
    await tester.tap(find.text('Regendaten laden'));
    await settle(tester);

    expect(settings.rainCourseEnabled, isTrue,
        reason: 'sonst kommt die Frage nach dem Neustart wieder');
  });

  testWidgets('ein Spot ohne Messung bekommt keinen leeren Abschnitt',
      (tester) async {
    // Der Stapel deckt 10..12 Grad Ost ab; dieser Spot liegt daneben —
    // auf der Karte aber sichtbar, sonst gäbe es keinen Marker zum
    // Antippen. Eine Zeile „keine Daten" bei jedem Spot außerhalb der
    // Messung wäre Lärm.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
        ownerId: me.id,
        lat: 51.0,
        lng: 13.5,
        name: 'Sächsischer Hang',
        species: 'Steinpilz');
    await pumpApp(tester, backend, extraOverrides: [
      rainStackLoaderProvider.overrideWithValue(() async => stackOf([5])),
    ]);
    await openSpot(tester, 'Sächsischer Hang');
    await tester.tap(find.text('Regendaten laden'));
    await settleCourse(tester, lat: 51.0, lon: 13.5);

    expect(find.text('Regen an diesem Spot'), findsNothing);
    expect(find.textContaining('mm'), findsNothing);
  });
}
