// Die Ampel-Vorschau (2026-08-09), vom Blatt aus — und ihre
// „Ehrlichkeit im UI"-Regeln aus docs/pilzampel-konzept.md, hier als
// Wächter: Stufen in Worten, NIE Prozent; Art oder Gilde wird genannt;
// „bewertet Bedingungen, nicht Vorkommen" steht im Text; lieber grau
// als erfunden; und ohne den Experimentell-Schalter existiert nichts
// davon.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart' show AmpelPalette;
import 'package:pilzbuddy/core/settings.dart' show settingsProvider;
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/ampel/ampel_map_providers.dart';
import 'package:pilzbuddy/features/ampel/ampel_providers.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';
import 'package:pilzbuddy/features/spots/widgets/weather_chart.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';
import '../rain_grid_test.dart' show encode;

void main() {
  const spotLat = 51.0;
  const spotLng = 11.0;

  /// Ein Stapel über dem Spot: eine Zelle, [days] Tage mit je [mm].
  RainStackData stackOf({required int days, int mm = 5}) => RainStackData(
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
          for (var i = 0; i < days; i++)
            (
              date: DateTime.utc(2026, 7, 1).add(Duration(days: i)),
              gzipped: encode([
                [mm]
              ]),
            ),
        ],
      );

  /// Die Stationstabelle: eine Luftstation neben dem Spot, konstant
  /// Max 16 / Min 10 → Tagesmittel 13 °C — das Optimum der Glocke.
  List<int> weatherBytes({int days = 20}) {
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final start = DateTime.utc(2026, 7, 7);
    final json = {
      'days': [
        for (var i = 0; i < days; i++) iso(start.add(Duration(days: i))),
      ],
      'stations': [
        {
          'id': 1270,
          'lat': 51.1,
          'lon': 11.0,
          'h': 316,
          'name': 'Erfurt-Weimar',
          'max': [for (var i = 0; i < days; i++) 16.0],
          'min': [for (var i = 0; i < days; i++) 10.0],
        },
      ],
      'soil': [
        {
          'id': 3821,
          'lat': 51.2,
          'lon': 11.1,
          'h': 250,
          'name': 'Weimarer Land',
          'soil': [for (var i = 0; i < days; i++) 15.0],
        },
      ],
    };
    return GZipEncoder().encode(utf8.encode(jsonEncode(json)))!;
  }

  FakeBackend loggedInWithSpot({String species = 'Steinpilz'}) {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
      ownerId: me.id,
      lat: spotLat,
      lng: spotLng,
      name: 'Buchenhang',
      species: species,
    );
    return backend;
  }

  Future<void> pumpWithWeather(
    WidgetTester tester,
    FakeBackend backend, {
    required bool preview,
    int stackDays = 26,
  }) async {
    // Keine vergrößerte Testfläche: Das Blatt ist eine nicht-lazy
    // Column in einem SingleChildScrollView — `find` sieht auch, was
    // unter der Falte steht, und getippt wird nach `ensureVisible`.
    await pumpApp(
      tester,
      backend,
      // Zustimmung bewusst AUS und im Test angetippt — das Hausmuster
      // aller Wetter-Flowtests: Eine ab Start erteilte Zustimmung
      // startet den Verlauf-Isolate in der Fake-Async-Zone des
      // Harness, und dessen Ergebnis kommt dort nie an (auf dem Gerät
      // existiert der Fall seit 1.45 problemlos). Nebeneffekt mit
      // Absicht: Der „braucht die Wetterdaten"-Zustand der Ampel wird
      // so in jedem Test mit geprüft.
      settings: FakeSettings(ampelPreviewEnabled: preview),
      extraOverrides: [
        rainStackLoaderProvider
            .overrideWithValue(() async => stackOf(days: stackDays)),
        weatherTableLoaderProvider
            .overrideWithValue(() async => weatherBytes()),
      ],
    );
  }

  Future<void> openSpot(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
  }

  /// Tippt „Wetterdaten laden" und wartet Verlauf, Temperatur und
  /// Ablesung ab — Muster `settleWeather` aus dem Regen-Flowtest.
  Future<void> acceptAndSettle(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Wetterdaten laden'));
    await settle(tester);
    await tester.tap(find.text('Wetterdaten laden'));
    // KEIN settle zwischen Tap und runAsync — das ist der Kern des
    // Hausmusters (settleWeather im Regen-Flowtest): Ein Pump hier
    // ließe die Blatt-Sektionen die Wetter-Provider unter der
    // Fake-Async-Zone anlegen, deren compute-Isolate dort nie
    // antwortet. Ohne Pump entstehen die Provider erst im runAsync
    // (echte Zone) — 2,5 verlorene Stunden, damit dieser Kommentar
    // hier steht.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    await tester.runAsync(() async {
      const at = (lat: spotLat, lon: spotLng);
      await container.read(rainCourseProvider(at).future);
      await container.read(spotTemperatureProvider(at).future);
    });
    await settle(tester);
  }

  testWidgets('volle Daten: Wort-Stufe, Gilde, Bedingungs-Satz — und '
      'nirgends ein Prozent', (tester) async {
    // 5 mm/Tag über 26 Tage sättigt die Feuchte, 13 °C trifft das
    // Optimum: Score 1,0 → „günstig".
    await pumpWithWeather(tester, loggedInWithSpot(), preview: true);
    await openSpot(tester);

    // Vor der Zustimmung verweist die Ampel auf den Wetterdaten-Knopf,
    // statt heimlich zu laden — dieselbe Zusage wie beim Regen.
    expect(find.textContaining('braucht die Wetterdaten'), findsOneWidget);
    await acceptAndSettle(tester);

    expect(find.textContaining('Pilzwetter (experimentell)'), findsOneWidget);
    // Die Stufe steht als Span im Text.rich — gesucht wird im
    // Plaintext, mit „: "-Anker, damit „ungünstig" nie mittrifft.
    expect(find.textContaining(': günstig'), findsOneWidget);
    expect(find.textContaining('für Steinpilz'), findsOneWidget,
        reason: 'die Ampel nennt die Art, nie „die Pilze"');
    expect(find.textContaining('Regen (26 Tage): gut'), findsOneWidget);
    expect(find.textContaining('Temperatur: passt (13,0 °C)'),
        findsOneWidget);
    expect(find.textContaining('Bewertet Bedingungen, nicht Vorkommen'),
        findsOneWidget,
        reason: 'die Regel steht im Text, nicht im Kleingedruckten');
    expect(find.textContaining('%'), findsNothing,
        reason: 'Konzept: kein Prozentzeichen — drei Stufen mit Worten');
  });

  testWidgets('ohne Schalter existiert die Sektion nicht', (tester) async {
    await pumpWithWeather(tester, loggedInWithSpot(), preview: false);
    await openSpot(tester);
    await acceptAndSettle(tester);
    expect(find.textContaining('Pilzwetter'), findsNothing,
        reason: 'volle Wetterdaten, aber kein Experiment-Schalter — '
            'die Sektion darf nicht einmal grau erscheinen');
  });

  testWidgets('14-Tage-Stapel (heutiger Live-Stand): grau mit Grund',
      (tester) async {
    await pumpWithWeather(tester, loggedInWithSpot(),
        preview: true, stackDays: 14);
    await openSpot(tester);
    await acceptAndSettle(tester);
    expect(find.textContaining('keine Aussage'), findsOneWidget);
    expect(find.textContaining('erst 14 von 26 Tagen'), findsOneWidget);
    expect(find.textContaining(': günstig'), findsNothing,
        reason: 'lieber grau als aus 14 Tagen eine Stufe erfinden');
  });

  testWidgets('ungeprüfte Art: grau, ohne dass gerechnet wird',
      (tester) async {
    await pumpWithWeather(
        tester, loggedInWithSpot(species: 'Hallimasch'),
        preview: true);
    // Ohne Zustimmung: Das Gilden-Tor steht VOR allem anderen — die
    // Zeile erscheint, ohne dass irgendetwas geladen würde.
    await openSpot(tester);
    expect(find.textContaining('für Hallimasch nicht geprüft'),
        findsOneWidget,
        reason: 'das Steinpilz-Modell ist für Holzbewohner kategorisch '
            'falsch — Konzept, Artenklassifikation');
    expect(find.textContaining(': günstig'), findsNothing);
  });

  testWidgets('Karten-Ampel im Regen-Blatt: exklusiv zum Regen, '
      'Zustimmung fährt mit', (tester) async {
    final settings = FakeSettings(ampelPreviewEnabled: true);
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: settings);

    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    final toggle = find.text('Pilzwetter-Ampel (experimentell)');
    await tester.ensureVisible(toggle);
    await settle(tester);
    await tester.tap(toggle);
    await settle(tester);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    expect(container.read(ampelLayerEnabledProvider), isTrue);
    expect(settings.rainCourseEnabled, isTrue,
        reason: 'dieselbe Zustimmung wie der Regen-Verlauf — EIN '
            'Angebot, kein zweiter Dialog; die Kosten stehen am '
            'Schalter');

    // Eine Regenfläche wählen schaltet die Ampel aus — zwei
    // Deutungs-Flächen übereinander wären Matsch.
    await tester.tap(find.text('Letzte 30 Tage'));
    await settle(tester);
    expect(container.read(rainLayerProvider), RainLayer.last30d);
    expect(container.read(ampelLayerEnabledProvider), isFalse);
  });

  testWidgets('die Farbfamilie lässt sich wählen und wird gemerkt',
      (tester) async {
    // Betreiber-Wunsch 2026-08-09: drei Familien zur Wahl, weil die
    // Ampel-Töne über der Waldebene standen und Farbwahrnehmung im Wald
    // eine andere ist als am Schreibtisch.
    final settings = FakeSettings(ampelPreviewEnabled: true);
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: settings);

    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    final toggle = find.text('Pilzwetter-Ampel (experimentell)');
    await tester.ensureVisible(toggle);
    await settle(tester);
    await tester.tap(toggle);
    await settle(tester);

    // Die Liste im Blatt ist LAZY: Was unter dem Rand liegt, existiert
    // im Baum noch gar nicht — `ensureVisible` liefe dort in „No
    // element". Deshalb scrollen, bis die Zeile wirklich da ist
    // (dieselbe Lehre wie im Wald-Blatt, #259).
    final magenta = find.text('Magenta');
    await tester.scrollUntilVisible(magenta, 120,
        scrollable: find
            .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable))
            .first);
    await settle(tester);
    await tester.tap(magenta);
    await settle(tester);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    expect(container.read(ampelPaletteProvider), AmpelPalette.magenta);
    expect(settings.ampelPalette, AmpelPalette.magenta,
        reason: 'eine Farbwahl trifft man nicht jede Wanderung neu');

    // Neustart mit denselben Einstellungen: Die Wahl steht noch.
    await pumpApp(tester, backend, settings: settings);
    final again = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    expect(again.read(ampelPaletteProvider), AmpelPalette.magenta);
  });

  testWidgets('ohne Vorschau-Schalter kein Ampel-Eintrag im Regen-Blatt',
      (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: FakeSettings());
    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    expect(find.text('Pilzwetter-Ampel (experimentell)'), findsNothing);
  });

  testWidgets('der Profil-Schalter schaltet die Vorschau und merkt sie',
      (tester) async {
    final settings = FakeSettings();
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: settings);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    final toggle = find.text('Pilzwetter-Ampel (experimentell)');
    await tester.scrollUntilVisible(toggle, 120,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    // Der Untertitel sagt, was das Ding NICHT kann — Konzept-Regel.
    expect(find.textContaining('nicht, ob dort Pilze'), findsOneWidget);
    await tester.tap(toggle);
    await settle(tester);
    expect(settings.ampelPreviewEnabled, isTrue,
        reason: 'die Vorschau überlebt den Neustart');
  });

  test('die Farbfamilie steht im DATEINAMEN der Fläche', () async {
    // Die MapLibre-Strecke ist idempotent auf der URL: Ohne die Familie
    // im Namen würde das neu gefärbte Bild schlicht nicht getauscht,
    // und die Karte zeigte still die alte Wahl weiter. Genau dieser
    // Fehler ist beim Wald mit der Klassenwahl passiert
    // (`forestFillStamp`), deshalb hier ein eigener Wächter.
    Future<String?> urlFor(AmpelPalette palette) async {
      final repository = _CapturingRepository();
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWithValue(FakeSettings(
            ampelPreviewEnabled: true,
            rainCourseEnabled: true,
            ampelPalette: palette)),
        rainGridRepositoryProvider.overrideWithValue(repository),
        rainStackLoaderProvider
            .overrideWithValue(() async => stackOf(days: 26)),
        weatherTableLoaderProvider
            .overrideWithValue(() async => weatherBytes()),
      ]);
      addTearDown(container.dispose);
      container.read(ampelLayerEnabledProvider.notifier).state = true;
      final result = await container.read(ampelFillFileProvider.future);
      return result?.url;
    }

    final violett = await urlFor(AmpelPalette.violett);
    final magenta = await urlFor(AmpelPalette.magenta);
    expect(violett, contains('violett'));
    expect(magenta, contains('magenta'));
    expect(violett, isNot(magenta),
        reason: 'gleicher Name ⇒ MapLibre tauscht das Bild nicht');
  });

  testWidgets('das Diagramm bleibt beim 14-Tage-Fenster, auch wenn der '
      'Stapel 26 trägt', (tester) async {
    await pumpWithWeather(tester, loggedInWithSpot(), preview: true);
    await openSpot(tester);
    await acceptAndSettle(tester);
    await tester.scrollUntilVisible(find.byType(WeatherChart), 80,
        scrollable: find
            .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable))
            .first);
    await settle(tester);
    final chart = tester.widget<WeatherChart>(find.byType(WeatherChart));
    expect(chart.course.days, hasLength(14),
        reason: '26 Balken auf Handybreite wären Streichhölzer — die '
            'zusätzlichen Tage füttern das Modell, nicht das Auge');
  });
}

/// Fängt nur den Dateinamen ab — geschrieben wird im Test nichts
/// (`path_provider` gibt es hier nicht).
class _CapturingRepository extends RainGridRepository {
  @override
  Future<String?> writeFill(String layer, DateTime measured, List<int> png,
          {String variant = ''}) async =>
      'file:///nirgends/fill_${layer}_$variant.png';
}
