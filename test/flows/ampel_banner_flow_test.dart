// Baustein B (#277) am laufenden Bild: der Nachlauf beim Kartenstart.
//
// Der WICHTIGSTE Test hier ist der zweite — „aus heißt aus". Der ganze
// Grund für den eigenen Schalter ist, dass das Höhengitter (3,4 MB) beim
// Start nicht ausgepackt wird, solange niemand das Banner bestellt hat;
// genau diese Last hat 1.99.4 aus dem Startpfad genommen. Ein `ref.watch`
// eine Zeile zu früh in `ampelScanProvider` holte sie lautlos zurück, und
// nichts an der Oberfläche sähe anders aus.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/ampel/ampel_scan.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/elevation_providers.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';
import '../rain_grid_test.dart' show encode;

void main() {
  const spotLat = 51.0;
  const spotLng = 11.0;

  /// Ein Stapel über dem Spot: eine Zelle, 26 Tage mit je [mm].
  ///
  /// 5 mm/Tag sättigt den Regenfaktor; zusammen mit 13 °C (dem Optimum
  /// der Glocke) steht die Ampel damit günstig. Welche Stufe genau
  /// daraus wird, prüft `ampel_scan_test.dart` gegen das Modell — hier
  /// zählt nur, dass die Zeile erscheint.
  RainStackData stackOf({int mm = 5}) => RainStackData(
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
          for (var i = 0; i < 26; i++)
            (
              date: DateTime.utc(2026, 7, 1).add(Duration(days: i)),
              gzipped: encode([
                [mm]
              ]),
            ),
        ],
      );

  /// Eine Luftstation neben dem Spot: Max 16 / Min 10 → Mittel 13 °C.
  List<int> weatherBytes() {
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final start = DateTime.utc(2026, 7, 7);
    return GZipEncoder().encode(utf8.encode(jsonEncode({
      'days': [for (var i = 0; i < 20; i++) iso(start.add(Duration(days: i)))],
      'stations': [
        {
          'id': 1270,
          'lat': 51.1,
          'lon': 11.0,
          'h': 316,
          'name': 'Erfurt-Weimar',
          'max': [for (var i = 0; i < 20; i++) 16.0],
          'min': [for (var i = 0; i < 20; i++) 10.0],
        },
      ],
      'soil': const [],
    })))!;
  }

  /// Ein flaches Höhengitter auf Stationshöhe — die Korrektur ist dann
  /// null, und der Test misst das Banner, nicht die Glocke.
  ElevationGrid flatGrid([int meters = 300]) => ElevationGrid(
        values:
            Uint8List.fromList(List.filled(64, meters ~/ elevationQuantM)),
        width: 8,
        height: 8,
        west: 10,
        east: 12,
        north: 52,
        south: 50,
        hexLonStep: 0.25,
        hexLatStep: 0.25,
      );

  (FakeBackend, FakeUser) loggedInWithSpot({String name = 'Buchenhang'}) {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
        ownerId: me.id,
        lat: spotLat,
        lng: spotLng,
        name: name,
        species: 'Steinpilz');
    return (backend, me);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
          tester.element(find.byType(Scaffold).first));

  /// „Der Riegel hat gegriffen": Der Nachlauf hat eine ANTWORT geliefert
  /// (eine leere), statt zu rechnen — und kein Gitter angefasst.
  ///
  /// Bewusst kein `await` auf `ampelScanProvider.future`. Fällt ein
  /// Riegel weg, hängt der Provider an seinem `compute`-Isolate, das in
  /// der Fake-Async-Zone nie antwortet; ein `await` liefe dann in den
  /// Zeitablauf statt in eine Fehlermeldung, und der Wächter wäre
  /// praktisch unbrauchbar (beim ersten Versuch zwei Minuten lang genau
  /// so erlebt). `hasValue` unterscheidet die beiden Fälle sofort:
  /// kurzgeschlossen ⇒ AsyncData, rechnend ⇒ AsyncLoading.
  ///
  /// Und geprüft wird `isLoading`, NICHT `hasValue`: Riverpods
  /// `AsyncLoading` trägt den vorherigen Wert mit sich, hier also die
  /// leere Liste — `hasValue` ist deshalb auch dann wahr, wenn gerade
  /// gerechnet wird. Mit `hasValue` blieb der Wächter unter beiden
  /// entfernten Riegeln grün.
  void expectSilent(WidgetTester tester, int loads) {
    final state = containerOf(tester).read(ampelScanProvider);
    expect(state.isLoading, isFalse,
        reason: 'der Riegel hat nicht gegriffen — der Nachlauf rechnet, '
            'statt sofort leer zu antworten');
    expect(state.value, isEmpty);
    expect(find.textContaining('stünde die Ampel günstig'), findsNothing);
    expect(loads, 0, reason: 'kein Gitter, solange ein Riegel steht');
  }

  /// Legt den Banner-Schalter um und lässt die Rechnung in der ECHTEN
  /// Zone laufen.
  ///
  /// Ohne `runAsync` bliebe sie stehen: `rainCoursesProvider` rechnet in
  /// einem `compute`-Isolate, und dessen Antwort kommt in der
  /// Fake-Async-Zone des Harness nie an. Dasselbe Hausmuster wie
  /// `acceptAndSettle` im Ampel-Flowtest — und derselbe Grund, warum der
  /// Schalter im Test angelegt und nicht ab Start gesetzt wird.
  Future<void> enableAndSettle(WidgetTester tester) async {
    final container = containerOf(tester);
    container.read(ampelBannerEnabledProvider.notifier).set(true);
    await tester.runAsync(() => container.read(ampelScanProvider.future));
    await settle(tester);
  }

  testWidgets('günstige Ampel am eigenen Spot: das Banner steht da',
      (tester) async {
    final (backend, _) = loggedInWithSpot();
    await pumpApp(
      tester,
      backend,
      settings: FakeSettings(
          ampelPreviewEnabled: true, rainCourseEnabled: true),
      extraOverrides: [
        rainStackLoaderProvider.overrideWithValue(() async => stackOf()),
        weatherTableLoaderProvider
            .overrideWithValue(() async => weatherBytes()),
        elevationLoaderProvider.overrideWithValue(() async => flatGrid()),
      ],
    );

    expect(find.textContaining('stünde die Ampel günstig'), findsNothing,
        reason: 'ohne Schalter kein Banner');

    await enableAndSettle(tester);

    // Der Wortlaut ist die Aussage: Konjunktiv, „experimentell", kein
    // „geh jetzt". Das Modell ist unvalidiert (die Arten-Kontrolle der
    // Rückwärtsprüfung ist durchgefallen), es hat sich keine
    // Aufforderung verdient.
    expect(find.textContaining('An Buchenhang stünde die Ampel günstig'),
        findsOneWidget);
    expect(find.textContaining('experimentell'), findsWidgets);
  });

  testWidgets('Der App-Start packt das Höhengitter NICHT aus, '
      'solange das Banner aus ist', (tester) async {
    // Der eigentliche Zweck des eigenen Schalters, und die Zeile, die
    // ihn hält. Beobachten IST laden: Ein `ref.watch` auf
    // `elevationGridProvider` VOR den drei Schaltern in
    // `ampelScanProvider` packte 3,4 MB bei jedem Start aus — für alle,
    // auch für die, die das Banner nie eingeschaltet haben.
    var loads = 0;
    final (backend, _) = loggedInWithSpot();
    await pumpApp(
      tester,
      backend,
      settings: FakeSettings(
          ampelPreviewEnabled: true, rainCourseEnabled: true),
      extraOverrides: [
        rainStackLoaderProvider.overrideWithValue(() async => stackOf()),
        weatherTableLoaderProvider
            .overrideWithValue(() async => weatherBytes()),
        elevationLoaderProvider.overrideWithValue(() async {
          loads++;
          return flatGrid();
        }),
      ],
    );

    expect(loads, 0,
        reason: 'der Start darf das Höhengitter nicht anfassen, solange '
            'niemand das Banner bestellt hat');

    // Und erst der Schalter holt es.
    await enableAndSettle(tester);
    expect(loads, 1);
  });

  testWidgets('ohne die Ampel-Vorschau bleibt es still', (tester) async {
    // Ein Banner über ein Feature, das im Blatt gar nicht existiert,
    // wäre eine Aussage ohne Nachlesestelle. Der Schalter im Profil ist
    // deshalb nur sichtbar, wenn die Vorschau an ist — dieser Test hält
    // fest, dass auch der PROVIDER es prüft und nicht nur die
    // Oberfläche.
    var loads = 0;
    final (backend, _) = loggedInWithSpot();
    await pumpApp(
      tester,
      backend,
      settings: FakeSettings(
          ampelPreviewEnabled: false,
          rainCourseEnabled: true,
          ampelBannerEnabled: true),
      extraOverrides: [
        rainStackLoaderProvider.overrideWithValue(() async => stackOf()),
        weatherTableLoaderProvider
            .overrideWithValue(() async => weatherBytes()),
        elevationLoaderProvider.overrideWithValue(() async {
          loads++;
          return flatGrid();
        }),
      ],
    );

    expectSilent(tester, loads);
  });

  testWidgets('ohne Wetter-Zustimmung bleibt es still', (tester) async {
    // Die dritte Bedingung. Ehrlich gesagt hält sie heute nicht der
    // Riegel in `ampelScanProvider`, sondern `rainStackProvider`, das
    // dieselbe Zustimmung prüft — die Gegenprobe (Riegel entfernt) bleibt
    // grün. Geprüft wird hier also das VERHALTEN, nicht die eine Zeile:
    // ohne Zustimmung kein Banner und kein Gitter, egal welcher der
    // beiden Riegel es trägt.
    var loads = 0;
    final (backend, _) = loggedInWithSpot();
    await pumpApp(
      tester,
      backend,
      settings: FakeSettings(
          ampelPreviewEnabled: true,
          rainCourseEnabled: false,
          ampelBannerEnabled: true),
      extraOverrides: [
        rainStackLoaderProvider.overrideWithValue(() async => stackOf()),
        weatherTableLoaderProvider
            .overrideWithValue(() async => weatherBytes()),
        elevationLoaderProvider.overrideWithValue(() async {
          loads++;
          return flatGrid();
        }),
      ],
    );

    expectSilent(tester, loads);
  });

  testWidgets('das X schaltet bis Tagesende stumm — und merkt es sich',
      (tester) async {
    // Ein telefonförmiger Schirm: Auf dem 800x600-Vorgabeschirm des
    // Harness (quer) reicht die neunköpfige FAB-Spalte bis nach ganz
    // oben und deckt das X eines breiten Banners zu — siehe Befund
    // unten.
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (backend, _) = loggedInWithSpot();
    final settings = FakeSettings(
        ampelPreviewEnabled: true, rainCourseEnabled: true);
    await pumpApp(
      tester,
      backend,
      settings: settings,
      extraOverrides: [
        rainStackLoaderProvider.overrideWithValue(() async => stackOf()),
        weatherTableLoaderProvider
            .overrideWithValue(() async => weatherBytes()),
        elevationLoaderProvider.overrideWithValue(() async => flatGrid()),
      ],
    );
    await enableAndSettle(tester);
    expect(find.textContaining('stünde die Ampel günstig'), findsOneWidget);

    // Das X im selben Banner — über die nächste Material-Hülle gesucht,
    // weil auch andere Banner ein Kreuz tragen (Muster aus
    // `buddy_find_banner_test.dart`).
    final close = find.descendant(
      of: find
          .ancestor(
              of: find.textContaining('stünde die Ampel günstig'),
              matching: find.byType(Material))
          .first,
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(close);
    await settle(tester);

    expect(find.textContaining('stünde die Ampel günstig'), findsNothing);
    // Über den Neustart hinaus: Der Zeitpunkt liegt in den Settings, und
    // er liegt noch heute — morgen sind es andere Daten und damit eine
    // andere Aussage.
    final until = settings.ampelBannerDismissedUntil;
    expect(until, isNotNull);
    expect(until!.isAfter(DateTime.now().toUtc()), isTrue);
    expect(until.difference(DateTime.now().toUtc()).inHours, lessThan(25));
  });
}
