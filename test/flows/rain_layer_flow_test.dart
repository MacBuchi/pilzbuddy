// Die Regenebene von der Karte aus: Knopf → Blatt → Wahl → Ebene liegt
// auf der Karte. Der Weg wird hier ganz gegangen, weil die einzelnen
// Teile ihn nicht beweisen: Ein korrekt gebautes GetMap nützt nichts,
// wenn der Knopf das falsche Blatt öffnet oder die Wahl nirgends ankommt.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';
import 'package:pilzbuddy/features/map/rain_layer.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';
import '../rain_grid_test.dart' show gridOf;

void main() {
  FakeBackend loggedIn() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  /// Ein Kegel: in der Mitte 200 mm, zum Rand hin auf 0. Ergibt
  /// geschlossene Ringe um die Mitte — jede Höhenstufe kommt genau einmal
  /// vor und ist lang genug, um nicht als Fragment wegzufallen.
  RainGrid coneGrid() => gridOf([
        for (var y = 0; y < 40; y++)
          [
            for (var x = 0; x < 40; x++)
              math.max(
                  0,
                  200 -
                      10 * math.max((x - 20).abs(), (y - 20).abs())),
          ],
      ]);

  /// Wartet, bis Gitter, Linien und Fläche gerechnet sind — beides läuft
  /// im Isolate, dafür braucht der Test echte Zeit.
  Future<void> settleRain(WidgetTester tester, RainLayer layer) async {
    final container = containerOf(tester);
    await tester.runAsync(() async {
      await container.read(rainContoursProvider(layer).future);
      await container.read(rainFillProvider(layer).future);
    });
    await settle(tester);
  }

  List<Override> withGrid() =>
      [rainGridLoaderProvider.overrideWithValue((_) async => coneGrid())];

  testWidgets('Vorgabe ist aus — niemand lädt ungefragt ein Regenbild',
      (tester) async {
    await pumpApp(tester, loggedIn());
    expect(containerOf(tester).read(rainLayerProvider), RainLayer.off);
  });

  testWidgets('Knopf öffnet das Blatt, die Wahl kommt an', (tester) async {
    await pumpApp(tester, loggedIn());

    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    expect(find.text('Letzte 30 Tage'), findsOneWidget);

    await tester.tap(find.text('Letzte 30 Tage'));
    await settle(tester);

    expect(containerOf(tester).read(rainLayerProvider), RainLayer.last30d);
  });

  testWidgets('Das Blatt nennt den Geltungsbereich, sobald eine Ebene liegt',
      (tester) async {
    await pumpApp(tester, loggedIn());
    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);

    // Ohne Ebene keine Legende und kein Geltungsbereich.
    expect(find.textContaining('Nur Deutschland'), findsNothing);

    await tester.tap(find.text('Letzte 24 Stunden'));
    await settle(tester);

    expect(find.textContaining('Nur Deutschland'), findsOneWidget,
        reason: 'Ohne diesen Satz sieht eine leere Fläche in Österreich '
            'nach einem Fehler der App aus.');
  });

  testWidgets('Aus nimmt die Ebene wieder weg', (tester) async {
    await pumpApp(tester, loggedIn());
    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    await tester.tap(find.text('Jetzt'));
    await settle(tester);
    await tester.tap(find.text('Aus'));
    await settle(tester);

    expect(containerOf(tester).read(rainLayerProvider), RainLayer.off);
  });

  testWidgets('flutter_map (der Web-Pfad) hängt die Ebene wirklich ein',
      (tester) async {
    await pumpApp(tester, loggedIn(), useRealMap: true);
    expect(find.byType(OverlayImageLayer), findsNothing);

    containerOf(tester).read(rainLayerProvider.notifier).state =
        RainLayer.last30d;
    await settle(tester);

    final layer =
        tester.widget<OverlayImageLayer>(find.byType(OverlayImageLayer));
    final image = layer.overlayImages.single as OverlayImage;
    expect(image.bounds.north, RainLayer.last30d.bounds.north);
    expect(image.opacity, RainLayer.last30d.opacity);
    expect(image.filterQuality, FilterQuality.none,
        reason: 'Weichgezeichnet sähe das 1-km-Raster genauer aus, als es '
            'ist — dieselbe Regel wie raster-resampling: nearest bei '
            'MapLibre.');
  });

  testWidgets('Die Regenebene liegt UNTER den Spot-Markern', (tester) async {
    // Ein Spot, der hinter dem Regen verschwindet, wäre genau dann
    // unauffindbar, wenn man ihn braucht.
    final backend = loggedIn();
    backend.addSpot(
      ownerId: backend.currentUserId!,
      lat: 48.1,
      lng: 11.5,
      name: 'Buchenhang',
      species: 'Steinpilz',
    );
    await pumpApp(tester, backend, useRealMap: true);
    containerOf(tester).read(rainLayerProvider.notifier).state = RainLayer.now;
    await settle(tester);

    final children = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .children
        .map((w) => w.runtimeType)
        .toList();
    final rain = children.indexOf(OverlayImageLayer);
    // Zuerst: Ist sie überhaupt da? Ohne diese Zeile wäre der Vergleich
    // unten wahr, sobald die Ebene FEHLT (indexOf liefert dann −1) — der
    // Test ginge also gerade dann durch, wenn nichts mehr funktioniert.
    expect(rain, isNonNegative);
    expect(rain, lessThan(children.lastIndexOf(MarkerLayer)));
  });

  testWidgets('Mit Gitter zeichnet die App die eigene Fläche statt DWD-Bild',
      (tester) async {
    // Der ganze Weg: Gitter → Bänder → Karte. Die Teile sind je einzeln
    // geprüft, aber keiner von ihnen beweist, dass die Fläche den
    // Renderer erreicht — und genau das ist die Stelle, an der ein falsch
    // verdrahteter Provider still nichts tut.
    //
    // Seit 1.48.0 werden KEINE Höhenlinien mehr gezeichnet: Bei 55 %
    // Deckkraft tragen die Bänder die Aussage allein, und die Konturen
    // dienen nur noch als Geometrie für die Beschriftung (MapLibre).
    await pumpApp(tester, loggedIn(),
        useRealMap: true, extraOverrides: withGrid());

    containerOf(tester).read(rainLayerProvider.notifier).state =
        RainLayer.last30d;
    await settleRain(tester, RainLayer.last30d);

    expect(find.byType(PolylineLayer), findsNothing,
        reason: 'die Linien sind bewusst weg — sie waren der Grund, warum '
            'die Fläche so blass sein musste');
    final image = tester
        .widget<OverlayImageLayer>(find.byType(OverlayImageLayer))
        .overlayImages
        .single as OverlayImage;
    expect(image.imageProvider, isA<MemoryImage>(),
        reason: 'das eigene Gitter, nicht das DWD-Bild');
    expect(image.filterQuality, FilterQuality.medium,
        reason: 'als Hauptdarstellung dürfen die 1-km-Treppenstufen nicht '
            'hervortreten — sie widersprächen den geglätteten Konturen');
  });

  testWidgets('Die eigene Fläche ersetzt das DWD-Bild — auf IHREN Grenzen',
      (tester) async {
    // Zwei Dinge in einem, weil sie zusammengehören: Sobald eigene Linien
    // liegen, darf das DWD-Bild NICHT mehr darunter liegen (zwei
    // Darstellungen derselben Zahlen), und die Fläche muss auf den
    // Grenzen des Gitters sitzen, nicht auf denen der Bildebene — die
    // Bildebene deckt mehr ab, der Unterschied wären rund zwanzig
    // Kilometer Versatz gegen die eigenen Linien.
    await pumpApp(tester, loggedIn(),
        useRealMap: true, extraOverrides: withGrid());
    containerOf(tester).read(rainLayerProvider.notifier).state =
        RainLayer.last30d;
    await settleRain(tester, RainLayer.last30d);

    final overlays =
        tester.widgetList<OverlayImageLayer>(find.byType(OverlayImageLayer));
    expect(overlays.length, 1,
        reason: 'zwei Bildebenen hieße: DWD-Bild UND eigene Fläche');
    final image = overlays.single.overlayImages.single as OverlayImage;
    final grid = coneGrid();
    expect(image.bounds.north, grid.north);
    expect(image.bounds.west, grid.west);
    expect(image.bounds.north, isNot(RainLayer.last30d.bounds.north));
  });

  testWidgets('Die eigene Fläche liegt UNTER den Spot-Markern',
      (tester) async {
    // Ein Spot, der hinter dem Regen verschwindet, wäre genau dann
    // unauffindbar, wenn man ihn braucht — und die Fläche ist seit
    // 1.48.0 deutlich kräftiger als vorher.
    await pumpApp(tester, loggedIn(),
        useRealMap: true, extraOverrides: withGrid());
    containerOf(tester).read(rainLayerProvider.notifier).state =
        RainLayer.last30d;
    await settleRain(tester, RainLayer.last30d);

    // Die Linien stecken in einem Builder (er liest die Kamera), stehen
    // also nicht selbst in der `children`-Liste. Deshalb über den
    // Elementbaum: Geschwister werden der Reihe nach besucht, und in
    // einem Stack ist diese Reihe die Malreihenfolge.
    final order = <Widget>[];
    void visit(Element element) {
      order.add(element.widget);
      element.visitChildren(visit);
    }

    visit(tester.element(find.byType(FlutterMap)));
    final fill = order.indexWhere((w) => w is OverlayImageLayer);
    final markers = order.lastIndexWhere((w) => w is MarkerLayer);
    expect(fill, isNonNegative);
    expect(markers, isNonNegative);
    expect(fill, lessThan(markers));
  });

  testWidgets(
      'Während das Gitter lädt: kein DWD-Bild, aber schon die eigene Legende',
      (tester) async {
    // Der Umschalt-Moment, den der Betreiber gemeldet hat: Solange das
    // Gitter lädt, zeigte die App erst das DWD-Bild samt DWD-Legende und
    // sprang dann auf die eigenen Farben um. Richtig ist: Während des
    // Ladens liegt NICHTS auf der Karte (auch kein umsonst geladenes
    // DWD-Bild), und beide Legenden stehen sofort — sie sind statisch.
    final gate = Completer<RainGrid?>();
    var imageRequests = 0;
    await pumpApp(tester, loggedIn(), useRealMap: true, extraOverrides: [
      rainGridLoaderProvider.overrideWithValue((_) => gate.future),
      rainImageProviderFactory.overrideWithValue((url) {
        imageRequests++;
        return MemoryImage(kTransparentTile);
      }),
    ]);
    // Das Gate nicht offen über das Testende hinaus stehen lassen.
    addTearDown(() {
      if (!gate.isCompleted) gate.complete(null);
    });

    containerOf(tester).read(rainLayerProvider.notifier).state =
        RainLayer.last30d;
    await settle(tester);

    expect(find.byType(OverlayImageLayer), findsNothing,
        reason: 'das DWD-Bild wäre der Farbblitz, der gleich wieder '
            'verschwindet');
    expect(imageRequests, 0,
        reason: 'ein Bild, das gleich ersetzt wird, darf gar nicht erst '
            'angefragt werden — 187–568 KB je Erstaktivierung');
    expect(find.text('150+ mm'), findsOneWidget,
        reason: 'die Karten-Legende ist statisch und steht sofort');

    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    expect(find.text('ab 10 mm'), findsOneWidget,
        reason: 'das Blatt zeigt sofort die eigene Legende, nicht erst '
            'die des DWD');
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Image)),
        findsNothing,
        reason: 'kein DWD-Legendenbild während des Ladens');
  });

  testWidgets('Kommt kein Gitter, fällt die Ebene aufs DWD-Bild zurück',
      (tester) async {
    // Die Rückfalllinie bleibt: Ohne Gitter (kein Empfang, kein Cache)
    // ist das DWD-Bild die einzige Darstellung — dann gehört auch die
    // DWD-Legende ins Blatt und die eigene Karten-Legende verschwindet.
    final gate = Completer<RainGrid?>();
    var imageRequests = 0;
    await pumpApp(tester, loggedIn(), useRealMap: true, extraOverrides: [
      rainGridLoaderProvider.overrideWithValue((_) => gate.future),
      rainImageProviderFactory.overrideWithValue((url) {
        imageRequests++;
        return MemoryImage(kTransparentTile);
      }),
    ]);

    containerOf(tester).read(rainLayerProvider.notifier).state =
        RainLayer.last30d;
    await settle(tester);

    gate.complete(null);
    await tester.runAsync(() => containerOf(tester)
        .read(rainContoursProvider(RainLayer.last30d).future));
    await settle(tester);

    final overlays =
        tester.widgetList<OverlayImageLayer>(find.byType(OverlayImageLayer));
    expect(overlays.length, 1,
        reason: 'jetzt — und erst jetzt — liegt das DWD-Bild da');
    expect(imageRequests, greaterThan(0));
    expect(find.text('150+ mm'), findsNothing,
        reason: 'die eigene Skala neben DWD-Farben wäre schlicht falsch');

    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);
    expect(find.text('ab 10 mm'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Image)),
        findsOneWidget,
        reason: 'zur DWD-Darstellung gehört die DWD-Legende');
  });

  testWidgets('Das Blatt zeigt zu eigenen Linien die eigene Legende',
      (tester) async {
    // Die DWD-Legende neben unseren Farben wäre schlimmer als gar keine.
    await pumpApp(tester, loggedIn(),
        useRealMap: true, extraOverrides: withGrid());
    containerOf(tester).read(rainLayerProvider.notifier).state =
        RainLayer.last30d;
    await settleRain(tester, RainLayer.last30d);

    await tester.tap(find.byTooltip('Regen'));
    await settle(tester);

    expect(find.text('ab 10 mm'), findsOneWidget);
    expect(find.text('ab 150 mm'), findsOneWidget);
    expect(find.textContaining('weniger als 10 mm'), findsOneWidget,
        reason: 'ohne Farbe heißt „wenig", nicht „keine Daten"');
  });
}
