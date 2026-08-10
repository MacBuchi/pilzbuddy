// Das Wetter am Spot, vom Blatt aus: fragen → laden → Zahlen, Balken und
// Temperaturlinien.
//
// Der Weg wird ganz gegangen, weil die Teile ihn nicht beweisen: Eine
// korrekt gerechnete Summe nützt nichts, wenn der Abschnitt nie erscheint
// oder ungefragt lädt — und „lädt nicht ungefragt" ist hier eine Zusage
// an die Nutzerin, keine Feinheit.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/spots/widgets/weather_chart.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';
import '../rain_grid_test.dart' show encode, gridOf;

/// Prüft, dass [value] in der Zelle mit der Beschriftung [label] steht —
/// über die NÄCHSTE Column um den Wert, nicht über einen Vorfahren-Finder:
/// Die Kachel legt alle Zellen in eine Row, ein `widgetWithText`-Vorfahre
/// fände deshalb zu jedem Wert jede Beschriftung.
void expectSumCell(WidgetTester tester, String label, String value) {
  final cell = tester.widget<Column>(
    find.ancestor(of: find.text(value), matching: find.byType(Column)).first,
  );
  final texts = [
    for (final child in cell.children)
      if (child is Text) child.data,
  ];
  expect(texts, contains(label),
      reason: 'der Wert $value muss in der Zelle „$label" stehen');
}

void main() {
  const spotLat = 51.0;
  const spotLng = 11.0;

  /// Ein Stapel über Deutschland: eine Zelle, alle Tage am selben Punkt.
  RainStackData stackOf(List<int> mmPerDay, {DateTime? firstDay}) =>
      RainStackData(
        info: const RainStackInfo(
          width: 1,
          height: 1,
          west: 10,
          east: 12,
          north: 52,
          south: 50,
          days: [],
        ),
        days: [
          for (final (index, mm) in mmPerDay.indexed)
            (
              date: (firstDay ?? DateTime.utc(2026, 7, 21))
                  .add(Duration(days: index)),
              gzipped: encode([
                [mm]
              ]),
            ),
        ],
      );

  /// Die Stationstabelle, wie sie das Werkzeug packt — eine Luft- und
  /// eine Bodenstation nahe am Spot.
  List<int> weatherBytes(List<DateTime> days) {
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final json = {
      'days': [for (final day in days) iso(day)],
      'stations': [
        {
          'id': 1270,
          'lat': 51.1,
          'lon': 11.0,
          'h': 316,
          'name': 'Erfurt-Weimar',
          'max': [for (var i = 0; i < days.length; i++) 20.0 + i],
          'min': [for (var i = 0; i < days.length; i++) 10.0 + i],
        },
      ],
      'soil': [
        {
          'id': 3821,
          'lat': 51.2,
          'lon': 11.1,
          'h': 250,
          'name': 'Weimarer Land',
          'soil': [for (var i = 0; i < days.length; i++) 15.0 + i],
        },
      ],
    };
    return GZipEncoder().encode(utf8.encode(jsonEncode(json)))!;
  }

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

  /// Wartet, bis Verlauf und Temperatur gerechnet sind. Beide laufen im
  /// Isolate, dafür braucht der Test echte Zeit — `settle` pumpt nur
  /// Bilder.
  Future<void> settleWeather(WidgetTester tester,
      {double lat = spotLat, double lon = spotLng}) async {
    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    await tester.runAsync(() async {
      await container.read(rainCourseProvider((lat: lat, lon: lon)).future);
      await container
          .read(spotTemperatureProvider((lat: lat, lon: lon)).future);
    });
    await settle(tester);
  }

  Future<void> openSpot(WidgetTester tester, [String name = 'Buchenhang']) async {
    // Der Marker trägt den Namen als Tooltip, nicht als Text — auf der
    // Karte steht er nirgends geschrieben.
    await tester.tap(find.byTooltip(name));
    await settle(tester);
  }

  /// Tippt auf „Wetterdaten laden" — nachdem der Knopf ins Bild geholt
  /// wurde.
  ///
  /// Der Regenabschnitt steht ganz unten im Blatt, und das Blatt scrollt
  /// (Obergrenze 90 % der Bildschirmhöhe). Alles, was darüber wächst,
  /// schiebt den Knopf hinaus: Seit dem Saison-Abschnitt (1.56.0) lag er
  /// außerhalb, `tap` warnte nur über den fehlgeschlagenen Hit-Test und
  /// tat nichts — sieben Tests scheiterten danach an Werten, die nie
  /// geladen wurden.
  Future<void> acceptWeather(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Wetterdaten laden'));
    await settle(tester);
    await tester.tap(find.text('Wetterdaten laden'));
  }

  testWidgets('lädt nichts, bevor jemand zustimmt', (tester) async {
    // Rund 1 MB gibt man im Wald nicht ungefragt aus — dieselbe Zusage
    // wie bei der Regenebene seit 1.45.0, und sie gilt für BEIDE Teile:
    // Stapel und Stationstabelle.
    var stackCalls = 0, weatherCalls = 0;
    final backend = loggedInWithSpot();
    await pumpApp(tester, backend, extraOverrides: [
      rainStackLoaderProvider.overrideWithValue(() async {
        stackCalls++;
        return stackOf([5]);
      }),
      weatherTableLoaderProvider.overrideWithValue(() async {
        weatherCalls++;
        return weatherBytes([DateTime.utc(2026, 7, 21)]);
      }),
    ]);
    await openSpot(tester);

    expect(find.text('Wetterdaten laden'), findsOneWidget);
    expect(stackCalls, 0, reason: 'Stapel ungefragt geladen');
    expect(weatherCalls, 0, reason: 'Stationstabelle ungefragt geladen');
    expect(find.textContaining('mm'), findsNothing);
  });

  testWidgets('nach dem Tipp stehen Summen und Verlauf da', (tester) async {
    final backend = loggedInWithSpot();
    await pumpApp(tester, backend, extraOverrides: [
      rainStackLoaderProvider.overrideWithValue(
          () async => stackOf([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])),
    ]);
    await openSpot(tester);
    await acceptWeather(tester);
    await settleWeather(tester);

    // 7 Tage = 8+9+…+14 = 77, 14 Tage = 1+2+…+14 = 105.
    //
    // Geprüft wird das PAAR aus Beschriftung und Zahl, nicht nur, dass
    // beide Zahlen irgendwo stehen: Vertauschte Fenster zeigen dieselben
    // zwei Zahlen an den falschen Zellen, und niemand sieht es. Über die
    // NÄCHSTE Column statt einen Finder: Seit die Summen in einer Kachel
    // stehen, enthält die eine äußere Row alle Beschriftungen UND alle
    // Zahlen — ein Row-/widgetWithText-Finder fände jede Kombination und
    // winkte Vertauschungen still durch.
    expectSumCell(tester, '7 Tage', '77 mm');
    expectSumCell(tester, '14 Tage', '105 mm');
    expect(find.textContaining('höchster Tageswert'), findsOneWidget,
        reason: 'der Satz, den eine Summe nicht sagen kann');
    expect(find.textContaining('nur Deutschland'), findsOneWidget,
        reason: 'ohne diesen Satz sieht ein leerer Abschnitt in Österreich '
            'nach einem Fehler der App aus');
  });

  testWidgets('die Summen stehen in einer Kachel im PilzBuddy-Stil',
      (tester) async {
    // Der Style-Vorschlag des Betreibers (2026-08-05): Cream-Kachel mit
    // runden Ecken, Wert fett in Grün — wie der Code-Block der Auth-Mails.
    // Mit W4-Gitter, damit auch die 30-Tage-Zelle da ist: Sie kommt aus
    // einer anderen Quelle als die beiden Stapel-Fenster.
    final backend = loggedInWithSpot();
    await pumpApp(tester, backend, extraOverrides: [
      rainStackLoaderProvider.overrideWithValue(
          () async => stackOf([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])),
      rainGridLoaderProvider.overrideWithValue((_) async => gridOf([
            [80, 80],
            [80, 80],
          ])),
    ]);
    await openSpot(tester);
    await acceptWeather(tester);
    await settleWeather(tester);
    await tester.runAsync(() => ProviderScope.containerOf(
            tester.element(find.byType(Scaffold).first))
        .read(rainMonthAtProvider((lat: spotLat, lon: spotLng)).future));
    await settle(tester);

    expectSumCell(tester, '30 Tage', '80 mm');

    final tile = tester.widget<Container>(
      find
          .ancestor(of: find.text('77 mm'), matching: find.byType(Container))
          .first,
    );
    final decoration = tile.decoration as BoxDecoration;
    expect(decoration.color, AppColors.cream);
    expect(decoration.borderRadius, BorderRadius.circular(8));

    final value = tester.widget<Text>(find.text('77 mm'));
    expect(value.style?.fontWeight, FontWeight.w700,
        reason: 'der Wert ist die Aussage, die Beschriftung die Zugabe');
    final theme = Theme.of(tester.element(find.text('77 mm')));
    expect(value.style?.color, theme.colorScheme.primary,
        reason: 'Theme-Grün statt rohem forestGreen — im dunklen Thema '
            'käme sonst ein zu dunkler Ton auf dunklem Grund');
  });

  testWidgets('mit Stationstabelle stehen Linien, Legende und Station da',
      (tester) async {
    // Tage bis gestern, damit auch das „gestern" der Zeitachse
    // mitgeprüft ist — mit festen Daten stimmte es nur heute.
    final now = DateTime.now();
    final yesterday = DateTime.utc(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final firstDay = yesterday.subtract(const Duration(days: 13));
    final days = [
      for (var i = 0; i < 14; i++) firstDay.add(Duration(days: i)),
    ];
    final backend = loggedInWithSpot();
    await pumpApp(tester, backend, extraOverrides: [
      rainStackLoaderProvider.overrideWithValue(() async =>
          stackOf(List.filled(14, 3), firstDay: firstDay)),
      weatherTableLoaderProvider
          .overrideWithValue(() async => weatherBytes(days)),
    ]);
    await openSpot(tester);
    await acceptWeather(tester);
    await settleWeather(tester);

    // Die Legende — drei unbeschriftete Linien wären Rätselraten.
    expect(find.text('Boden 5 cm'), findsOneWidget);
    expect(find.text('Luft max'), findsOneWidget);
    expect(find.text('Luft min'), findsOneWidget);

    // Die Herkunftszeile, wörtlich: Name, Entfernung, Höhe UND das
    // richtige Netz-Etikett. Vertauschte Etiketten („Luft" an der
    // Bodenstation) sähen mit bloßem textContaining-Namen richtig aus.
    expect(
        find.textContaining('Temperatur: Erfurt-Weimar '
            '(11 km, 316 m ü. NN, Luft) '
            'und Weimarer Land (23 km, 250 m ü. NN, Boden).'),
        findsOneWidget);

    // Achsen und Zeitrichtung stecken im Painter, nicht im Widget-Baum.
    final paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WeatherChartPainter));
    final painter = paint.painter as WeatherChartPainter;
    expect(painter.axis, isNotNull, reason: '°C-Achse fehlt');
    expect(painter.soil, isNotNull);
    expect(painter.airMax, isNotNull);
    expect(painter.airMin, isNotNull);
    expect(painter.endLabel, startsWith('gestern, '),
        reason: 'die Richtung der Zeitskala muss benannt sein');
  });

  testWidgets('ohne Stationstabelle bleibt der Regen-Teil vollständig',
      (tester) async {
    // Die Temperatur ist eine Zugabe: Fehlt sie (kein Empfang beim
    // ersten Laden, altes Asset), stehen Summen und Balken trotzdem da
    // — ohne Legende, ohne Stationszeile, ohne Platzhalter.
    final backend = loggedInWithSpot();
    await pumpApp(tester, backend, extraOverrides: [
      rainStackLoaderProvider.overrideWithValue(
          () async => stackOf([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])),
      weatherTableLoaderProvider.overrideWithValue(() async => null),
    ]);
    await openSpot(tester);
    await acceptWeather(tester);
    await settleWeather(tester);

    expect(find.textContaining('77 mm'), findsOneWidget);
    expect(find.textContaining('nur Deutschland'), findsOneWidget);
    expect(find.text('Boden 5 cm'), findsNothing);
    expect(find.textContaining('Temperatur:'), findsNothing);
    final paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WeatherChartPainter));
    expect((paint.painter as WeatherChartPainter).axis, isNull);
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
    await acceptWeather(tester);
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
    await acceptWeather(tester);
    await settleWeather(tester, lat: 51.0, lon: 13.5);

    expect(find.text('Wetter an diesem Spot'), findsNothing);
    expect(find.textContaining('mm'), findsNothing);
  });
}
