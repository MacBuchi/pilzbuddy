// Die Ampel-Vorschau (2026-08-09), vom Blatt aus — und ihre
// „Ehrlichkeit im UI"-Regeln aus docs/pilzampel-konzept.md, hier als
// Wächter: Stufen in Worten, NIE Prozent; Art oder Gilde wird genannt;
// „bewertet Bedingungen, nicht Vorkommen" steht im Text; lieber grau
// als erfunden; und ohne den Experimentell-Schalter existiert nichts
// davon.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/ampel/ampel_map_providers.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart'
    show
        ForestFillImage,
        forestFillVariant,
        forestLayerEnabledProvider;
import 'package:pilzbuddy/features/map/forest_fill.dart'
    show allForestClasses;
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
    expect(find.textContaining('10-Jahres-Studie bei Bielefeld'),
        findsOneWidget,
        reason: 'die Formel ist übernommen, nicht erfunden — die '
            'Quelle gehört an die Zeile (Betreiber, 2026-08-15); die '
            'volle Zitation steht auf der Lizenzseite');
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

  testWidgets('Karten-Ampel im Regen-Blatt: schaltet den Wald ein, '
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
    expect(container.read(forestLayerEnabledProvider), isTrue,
        reason: 'die Ampel leuchtet IN den Waldwaben — ohne Waldebene '
            'hätte sie nichts, worauf sie liegen könnte');
    expect(settings.rainCourseEnabled, isTrue,
        reason: 'dieselbe Zustimmung wie der Regen-Verlauf — EIN '
            'Angebot, kein zweiter Dialog; die Kosten stehen am '
            'Schalter');

    // Eine Regenfläche darf daneben liegen: Seit 1.76.0 gibt es keine
    // zweite Deutungs-FLÄCHE mehr, die sich mit dem Regen beißen
    // könnte — die Ampel steckt in den Waben.
    //
    // Zurückgescrollt wird ausdrücklich: Das Blatt ist eine lazy Liste,
    // und nach dem Weg zum Ampel-Schalter liegen die Regen-Einträge
    // wieder über dem sichtbaren Bereich (also außerhalb des Baums).
    await tester.scrollUntilVisible(find.text('Letzte 30 Tage'), -120,
        scrollable: find
            .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable))
            .first);
    await settle(tester);
    await tester.tap(find.text('Letzte 30 Tage'));
    await settle(tester);
    expect(container.read(rainLayerProvider), RainLayer.last30d);
    expect(container.read(ampelLayerEnabledProvider), isTrue);
  });

  testWidgets('der Regen-Knopf zeigt die Ampel, nicht nur den Regen (#278)',
      (tester) async {
    // Feldbericht: „Wenn die Pilzampel aktiv ist, sollte das
    // Wassersymbol auch ein Symbol für die Pilzampel zeigen und nicht
    // einfach nur inaktiv sein." Hinter dem einen Knopf sitzen zwei
    // Ebenen; er muss beide unterscheidbar anzeigen.
    final settings = FakeSettings(ampelPreviewEnabled: true);
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    await pumpApp(tester, backend, settings: settings);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));

    // Über den heroTag statt über den Tooltip: Der Tooltip ist genau
    // das, was dieser Test prüft — ihn zum Suchen zu benutzen, hieße
    // die Antwort in die Frage zu legen.
    final rainFab = find.byWidgetPredicate(
        (widget) => widget is FloatingActionButton && widget.heroTag == 'rain');
    FloatingActionButton fab() => tester.widget<FloatingActionButton>(rainFab);
    bool hasIcon(IconData icon) => find
        .descendant(of: rainFab, matching: find.byIcon(icon))
        .evaluate()
        .isNotEmpty;

    expect(fab().tooltip, 'Regen');
    expect(hasIcon(Icons.water_drop_outlined), isTrue);
    expect(fab().backgroundColor, isNull, reason: 'nichts an, nichts bunt');

    // Nur die Ampel: eigenes Symbol und eigene Farbe — vorher sah der
    // Knopf hier aus wie „aus", während der halbe Wald leuchtete.
    container.read(ampelLayerEnabledProvider.notifier).state = true;
    await settle(tester);
    expect(fab().tooltip, 'Pilzampel');
    expect(hasIcon(Icons.traffic), isTrue);
    expect(hasIcon(Icons.water_drop_outlined), isFalse);
    expect(fab().backgroundColor, AppColors.ampelStrong);

    // Beide an: Der Tropfen führt (der Knopf heißt Regen), die Ampel
    // bekommt ihren Punkt dazu.
    container.read(rainLayerProvider.notifier).state = RainLayer.last30d;
    await settle(tester);
    expect(fab().tooltip, 'Regen & Pilzampel');
    expect(hasIcon(Icons.water_drop), isTrue);
    expect(fab().backgroundColor, AppColors.friendBlue);
    expect(
        tester
            .widget<Badge>(
                find.descendant(of: rainFab, matching: find.byType(Badge)))
            .isLabelVisible,
        isTrue);

    // Nur Regen: wieder der alte Zustand, ohne Punkt.
    container.read(ampelLayerEnabledProvider.notifier).state = false;
    await settle(tester);
    expect(fab().tooltip, 'Regen');
    expect(fab().backgroundColor, AppColors.friendBlue);
    expect(
        tester
            .widget<Badge>(
                find.descendant(of: rainFab, matching: find.byType(Badge)))
            .isLabelVisible,
        isFalse,
        reason: 'ein Punkt ohne Ampel wäre Dekoration');
  });

  testWidgets('es gibt keine Farbwahl mehr im Regen-Blatt', (tester) async {
    // 1.73.0 stellte drei Familien zur Wahl, weil der gerenderte
    // Vergleich knapp war. Entschieden hat ihn das Feld (Türkis zu nah
    // am Kartenwasser), und seit die Kombi-Ebene je Waldklasse eigene
    // Töne setzt, wäre eine zweite Familie sechs weitere Handwerte —
    // für ein Feature mit einer benutzten Familie (Betreiber,
    // 2026-08-10). Der Wächter hält fest, dass die Auswahl weg BLEIBT.
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

    expect(find.text('Farbe'), findsNothing);
    expect(find.text('Violett'), findsNothing);
    expect(find.text('Magenta'), findsNothing);
    expect(find.text('Türkis'), findsNothing);
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

  test('der Wetter-Stand steht im DATEINAMEN der Fläche', () {
    // Die MapLibre-Strecke ist idempotent auf der URL: Ohne den Stand
    // im Namen würde das neu gerechnete Bild schlicht nicht getauscht,
    // und die Karte zeigte still das Wetter von gestern. Genau dieser
    // Fehler ist beim Wald mit der Klassenwahl passiert
    // (`forestFillStamp`), deshalb hier ein eigener Wächter. Die
    // Farbfamilie stand hier bis 1.79.0 mit drin — seit die Töne fest
    // sind, gibt es dort nichts mehr zu unterscheiden.
    ForestFillImage imageOf(DateTime newest) => ForestFillImage(
          png: Uint8List(0),
          west: 10,
          east: 11,
          north: 50,
          south: 49,
          referenceYear: 2024,
          classes: allForestClasses,
          windowKey: 'k1',
          fine: false,
          ampel: (newest: newest),
        );

    final heute = forestFillVariant(imageOf(DateTime.utc(2026, 8, 9)));
    expect(heute, contains('ampel-2026-08-09'));
    expect(forestFillVariant(imageOf(DateTime.utc(2026, 8, 10))),
        isNot(heute),
        reason: 'gleicher Name ⇒ MapLibre tauscht das Bild nicht');

    // Ohne Ampel bleibt der Name, was er seit #249 ist.
    expect(
        forestFillVariant(ForestFillImage(
          png: Uint8List(0),
          west: 10,
          east: 11,
          north: 50,
          south: 49,
          referenceYear: 2024,
          classes: allForestClasses,
          windowKey: 'k1',
          fine: false,
        )),
        'k1');
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
