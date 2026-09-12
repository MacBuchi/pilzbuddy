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
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/ampel/ampel_scan.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/elevation_providers.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/map/widgets/map_banners.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
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
    expect(find.textContaining('· Ampel günstig'), findsNothing);
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

    expect(find.textContaining('· Ampel günstig'), findsNothing,
        reason: 'ohne Schalter kein Banner');

    await enableAndSettle(tester);

    // Der Wortlaut ist die Aussage: Konjunktiv, „experimentell", kein
    // „geh jetzt". Das Modell ist unvalidiert (die Arten-Kontrolle der
    // Rückwärtsprüfung ist durchgefallen), es hat sich keine
    // Aufforderung verdient.
    //
    // Seit der Chip-Zeile steht der Vorbehalt in einem EIGENEN Text
    // neben dem Namen — nicht aus Layoutlaune, sondern damit die Ellipse
    // bei langen Spotnamen den Namen frisst und nicht ihn.
    expect(find.textContaining('Buchenhang · Ampel günstig'),
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

  testWidgets('das X schaltet für diese Sitzung stumm — der Neustart '
      'bringt es zurück', (tester) async {
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
    expect(find.textContaining('· Ampel günstig'), findsOneWidget);

    // Das X im selben Banner — über die nächste Material-Hülle gesucht,
    // weil auch andere Banner ein Kreuz tragen (Muster aus
    // `buddy_find_banner_test.dart`).
    final close = find.descendant(
      of: find
          .ancestor(
              of: find.textContaining('· Ampel günstig'),
              matching: find.byType(Material))
          .first,
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(close);
    await settle(tester);

    expect(find.textContaining('· Ampel günstig'), findsNothing);

    // **Und der Neustart nimmt die Stummschaltung zurück** (#425). Bis
    // 1.128.0 lag hier ein Zeitpunkt bis Mitternacht in den
    // Einstellungen; ein einziger Tipp nahm das Feature damit für bis zu
    // 24 Stunden weg, ohne Spur und ohne Rückweg — gemeldet als „ich
    // bekomme kein Banner mehr", vom Betreiber selbst.
    //
    // Der leere Frame dazwischen ist Pflicht: Ein zweiter `pumpApp` ohne
    // ihn setzt Riverpod nicht zurück, und der Test prüfte dann nur
    // dieselbe Sitzung noch einmal.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend, settings: settings);
    await settle(tester);

    // Geprüft wird der MERKER, nicht das gerenderte Banner — und das ist
    // Absicht, keine Bequemlichkeit. Der Nachlauf rechnet über
    // `compute()`, braucht also `runAsync`; ein zweites `runAsync` nach
    // einem Neustart im selben Test hängt, und zwar so, dass nicht
    // einmal `--timeout` es abräumt (gemessen: > 4 min, Abbruch von
    // Hand). Die Zusage dieses Tests ist ohnehin die schmalere: Die neue
    // Sitzung startet UNGEDÄMPFT. Dass ein ungedämpftes Banner bei
    // Treffern erscheint, steht im ersten Test dieser Datei.
    //
    // Und stärker als jede Zeitprüfung ist, dass es die Einstellung gar
    // nicht mehr GIBT: `ampelBannerDismissedUntil` ist mit #425 aus
    // `Settings` entfernt, ein Rest kann also nirgends liegen bleiben.
    expect(containerOf(tester).read(ampelBannerMutedProvider), isFalse,
        reason: 'die Stummschaltung endet mit der Sitzung');
  });

  /// Der volle Aufbau für die Sprung-Tests: Telefon-Schirm, Banner an,
  /// Rechnung durch.
  Future<void> pumpReady(WidgetTester tester, FakeBackend backend) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings =
        FakeSettings(ampelPreviewEnabled: true, rainCourseEnabled: true);
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
  }

  FakeMapViewState camera(WidgetTester tester) =>
      tester.state<FakeMapViewState>(find.byType(FakeMapView));

  testWidgets('ein Treffer: das Banner filtert und rückt ihn ins Bild',
      (tester) async {
    // Der Kern von #345 gilt weiter: Bis 1.103.0 ließ das Antippen die
    // Kamera stehen — Blatt zu, und man stand wieder am Startpunkt. Bei
    // einem Spot 30 km entfernt half nur noch der Name.
    //
    // Seit #399 ist die Antwort darauf aber eine andere: nicht Sprung
    // plus Blatt, sondern Filter plus Zoom — und zwar bei EINEM Treffer
    // genauso wie bei zehn. Zwei Antworten auf denselben Tipp waren der
    // eigentliche Bruch.
    final (backend, _) = loggedInWithSpot();
    await pumpReady(tester, backend);

    expect(camera(tester).center, isNot(const LatLng(spotLat, spotLng)),
        reason: 'sonst prüfte der Test einen Sprung, der schon geschehen ist');

    // **Der Mittelpunkt gehört in den Finder.** Seit 1.136.0 heißt das
    // Banner „… · Ampel günstig" und der Filter-Chip „Gefiltert: Ampel
    // günstig" — ohne das Trennzeichen trifft `textContaining` beide,
    // und der Tipp landet auf dem falschen.
    await tester.tap(find.textContaining('· Ampel günstig'));
    await settle(tester);

    // Der Filter steht — und er STEHT SICHTBAR. Ein von der App selbst
    // gesetzter Filter ohne Anzeige wäre genau der unbemerkt versteckte
    // Spot, vor dem #154 warnt.
    expect(find.textContaining('Gefiltert: Ampel günstig'), findsOneWidget);

    // Und die Kamera ist beim Spot. Nicht auf die Stelle genau: Der Zoom
    // rechnet einen Rand ein, die Mitte liegt aber auf dem einzigen
    // Treffer.
    expect(camera(tester).center.latitude, closeTo(spotLat, 0.001));
    expect(camera(tester).center.longitude, closeTo(spotLng, 0.001));

    // **Und das Banner bleibt** (#349). Bis 1.104.0 stand hier das
    // Gegenteil: Der einzelne Treffer galt als „abgearbeitet" und wurde
    // bis Mitternacht stummgeschaltet. Der Betreiber hat daraufhin
    // gemeldet, der Hinweis „funktioniere seit dem letzten Update nicht
    // mehr" — er hatte ihn einmal angetippt, wie das Banner es selbst
    // vorschlägt („— antippen"), und danach kam an diesem Tag keiner
    // mehr. Lesen ist nicht erledigen; der Spot bleibt günstig.
    expect(containerOf(tester).read(ampelBannerMutedProvider), isFalse);
  });

  testWidgets('mehrere Treffer: alle liegen danach im Bild', (tester) async {
    // „7 Spots · Ampel günstig" ist kein Ausnahmefall: Die
    // eigenen Spots liegen in derselben Region und bekommen dasselbe
    // Wetter. Bis #345 öffnete das Banner den bestbewerteten und
    // schaltete sich bis Mitternacht stumm — die Zahl im Text war eine
    // Aussage, zu der es keinen Weg gab. Seit #399 führt sie zu allen
    // zugleich.
    final (backend, me) = loggedInWithSpot();
    backend.addSpot(
        ownerId: me.id,
        lat: 51.05,
        lng: 11.05,
        name: 'Fichtenschonung',
        species: 'Marone');
    await pumpReady(tester, backend);

    expect(find.textContaining('2 Spots · Ampel günstig'),
        findsOneWidget);

    await tester.tap(find.textContaining('· Ampel günstig'));
    await settle(tester);

    expect(find.textContaining('Gefiltert: Ampel günstig'), findsOneWidget);

    // Die Mitte liegt zwischen beiden — nicht auf dem bestbewerteten.
    // Genau das ging vorher nicht.
    expect(camera(tester).center.latitude, closeTo(51.025, 0.001));
    expect(camera(tester).center.longitude, closeTo(11.025, 0.001));

    // Und das Banner bleibt stehen: Sonst wäre Spot 2 nach dem Besuch
    // von Spot 1 bis Mitternacht unerreichbar. Nur das X schaltet stumm.
    expect(containerOf(tester).read(ampelBannerMutedProvider), isFalse,
        reason: 'bei mehreren Treffern schaltet erst das X stumm');
  });

  testWidgets('zweimal antippen bleibt beim selben Zoom', (tester) async {
    // Der Kern von #420. Gemeldet als „Mehrmaliges Tippen setzt anderen
    // Kartenzoom", und genau so war es: `fitToSpots` liefert den Zoom
    // als DELTA aus Zoomstufe und Bodenauflösung. Die Auflösung wurde
    // beim BAUEN erfasst, die Zoomstufe erst beim Tippen gelesen — nach
    // der ersten Fahrt beschrieben die beiden also zwei verschiedene
    // Kameras, und jeder weitere Tipp addierte dasselbe Delta erneut.
    //
    // Zwei Spots weit auseinander, damit der Fit überhaupt zoomt: Beim
    // Start steht die Karte auf der Deutschland-Übersicht, danach rund
    // 3,6 Stufen näher. Der Fehler verdoppelte diesen Sprung.
    final (backend, me) = loggedInWithSpot();
    backend.addSpot(
        ownerId: me.id,
        lat: 51.4,
        lng: 11.4,
        name: 'Fichtenschonung',
        species: 'Marone');
    await pumpReady(tester, backend);
    expect(find.textContaining('2 Spots · Ampel günstig'),
        findsOneWidget,
        reason: 'beide Spots müssen Treffer sein, sonst prüft der Test '
            'den Filter statt der Kamera');

    // Ohne diesen Stillstand kennt die App ihre Bodenauflösung nicht und
    // zentriert bloß — der Zoom-Fehler wäre gar nicht auslösbar.
    await simulateCameraIdle(tester);
    final start = camera(tester).zoom;

    await tester.tap(find.textContaining('· Ampel günstig'));
    await settle(tester);
    final afterFirst = camera(tester).zoom;
    expect(afterFirst, isNot(closeTo(start, 0.5)),
        reason: 'der erste Tipp MUSS zoomen, sonst ist der zweite ohne '
            'Aussage');

    // Die Karte kommt zur Ruhe und meldet ihre neue Auflösung — auf dem
    // Gerät passiert das von selbst.
    await simulateCameraIdle(tester);

    await tester.tap(find.textContaining('· Ampel günstig'));
    await settle(tester);

    // Derselbe Filter, dieselben Spots, dieselbe Kamera: Der zweite
    // Tipp hat nichts mehr zu tun. Vor dem Fix landete er hier rund 3,6
    // Stufen weiter drin.
    expect(camera(tester).zoom, closeTo(afterFirst, 0.05));
  });

  testWidgets('der erste Tipp rückt die TREFFER ins Bild, nicht alle Spots',
      (tester) async {
    // Die zweite Hälfte von #420, und sie war im Code als Absicht
    // ausdrücklich aufgeschrieben: „Erst filtern, dann zoomen — der
    // Rückruf liest die SICHTBAREN Spots" (`map_banners.dart`). Die
    // Absicht kam nie an. Der Banner setzt den Filter und ruft SOFORT,
    // der Rebuild kommt erst im nächsten Frame — die Closure trug also
    // die Spot-Liste von VOR dem Filter.
    //
    // Sichtbar wird das nur mit einem Spot, den die Ampel NICHT nennt:
    // Der Schwarzwald-Spot liegt außerhalb des Regengitters und ist
    // damit kein Treffer.
    final (backend, me) = loggedInWithSpot();
    backend.addSpot(
        ownerId: me.id,
        lat: 48.0,
        lng: 8.0,
        name: 'Schwarzwald',
        species: 'Marone');
    await pumpReady(tester, backend);
    expect(find.textContaining('Buchenhang · Ampel günstig'),
        findsOneWidget,
        reason: 'genau ein Treffer — sonst prüft der Test nichts');

    await simulateCameraIdle(tester);
    await tester.tap(find.textContaining('· Ampel günstig'));
    await settle(tester);

    // Auf dem Treffer, nicht auf der Mitte zwischen Treffer und
    // Schwarzwald (49,5 / 9,5).
    expect(camera(tester).center.latitude, closeTo(spotLat, 0.001));
    expect(camera(tester).center.longitude, closeTo(spotLng, 0.001));
  });

  testWidgets('Der Vorbehalt steht neben dem Namen, nicht in ihm',
      (tester) async {
    // Die Zusage: Bei einem langen Spotnamen frisst die Ellipse den
    // NAMEN, nie „(experimentell)". In einem einzigen Text ginge das
    // nicht — dort schneidet die Ellipse immer hinten ab, und hinten
    // steht die Einschränkung. Der Entwurf schlug „(exp.)" vor; das
    // kürzt den Vorbehalt, während die Behauptung ungekürzt bleibt.
    final (backend, _) = loggedInWithSpot(
        name: 'Der lange Buchenhang hinter dem alten Forsthaus am Bach');
    await pumpApp(
      tester,
      backend,
      settings:
          FakeSettings(ampelPreviewEnabled: true, rainCourseEnabled: true),
      extraOverrides: [
        rainStackLoaderProvider.overrideWithValue(() async => stackOf()),
        weatherTableLoaderProvider
            .overrideWithValue(() async => weatherBytes()),
        elevationLoaderProvider.overrideWithValue(() async => flatGrid()),
      ],
    );
    await enableAndSettle(tester);

    // Zwei getrennte Texte, und der Vorbehalt ist NICHT im schrumpfenden
    // Teil. Genau das ist der Unterschied zu einer einzigen Zeichenkette.
    final hedge = find.text(' (experimentell)');
    expect(hedge, findsOneWidget,
        reason: 'ein eigener Text — in einer gemeinsamen Zeichenkette '
            'gäbe es ihn hier gar nicht zu finden');

    // Der Name schrumpft, der Vorbehalt nicht: Die Ellipse hängt am
    // Namen, und nur an ihm.
    final name = find.textContaining('· Ampel günstig');
    expect(tester.widget<Text>(name).overflow, TextOverflow.ellipsis);
    expect(tester.widget<Text>(hedge).overflow, isNot(TextOverflow.ellipsis));

    // Und er steht wirklich auf dem Schirm — nicht bloß im Baum —,
    // obwohl der Name die Zeile längst sprengt. Gemessen gegen die
    // Breite der ECHTEN Hülle, nicht gegen eine geratene Zahl.
    final shellWidth = tester.getSize(find.byType(Scaffold).first).width;
    expect(tester.getSize(hedge).width, greaterThan(0));
    expect(tester.getBottomRight(hedge).dx, lessThanOrEqualTo(shellWidth),
        reason: 'der Vorbehalt darf nicht aus dem Schirm geschoben werden');
  });
}
