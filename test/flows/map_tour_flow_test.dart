// Die geführte Tour über die Karte (#350, neu gebaut für #596).
//
// Die Zusagen, und keine davon ist der Wortlaut:
//
//   1. Sie läuft beim ersten Start an — und danach nie wieder.
//   2. Überspringen und Zurück zählen wie Durchsehen, und Zurück beendet
//      die Tour, nicht die App.
//   3. Aussparung und Ring sitzen auf den ECHTEN Widgets, auf einem
//      normalen und einem kleinen Schirm — die Leiste steckt in einem
//      `FittedBox(scaleDown)`.
//   4. Sie FÜHRT VOR: Das Kontextmenü und das Ebenen-Blatt gehen auf,
//      und ihre Einträge sind hervorgehoben (Betreiber, 2026-09-24).
//   5. Was sie öffnet, schließt sie wieder, ohne etwas auszulösen.
//   6. Die Sprechblase liegt nie auf dem, was sie erklärt.
//   7. Am Ende führt ein Knopf in die Kurzanleitung, und von dort lässt
//      sie sich neu starten.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/coach/coach.dart';
import 'package:pilzbuddy/features/help/map_tour.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

/// Ein Knopf der Leiste — über den Tooltip, er ist ohnehin die Zusage an
/// den Nutzer, weil die Leiste keine Beschriftung trägt.
Finder tool(String tooltip) => find.byTooltip(tooltip);

CoachPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<CoachPainter>()
    .single;

/// Gleich bis auf Rundung — beide Rechtecke laufen durch Transformationen.
bool near(Rect a, Rect b) =>
    (a.left - b.left).abs() < 0.01 &&
    (a.top - b.top).abs() < 0.01 &&
    (a.right - b.right).abs() < 0.01 &&
    (a.bottom - b.bottom).abs() < 0.01;

Rect union(Iterable<Rect> rects) => rects.reduce((a, b) => a.expandToInclude(b));

final kTourTitles = [for (final s in kMapTourScript.steps) s.title];

void main() {
  /// Ein Gerät dieser Maße — Oberfläche UND `MediaQuery` (#358).
  void useScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  FakeBackend signedIn() {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    return backend;
  }

  FakeSettings fresh() => FakeSettings(mapTourSeen: false);

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Weiter'));
    await settle(tester);
  }

  /// Nichts wurde ausgelöst: kein Anlege-Blatt, kein Menü, kein
  /// Ebenen-Blatt.
  void nothingOpen() {
    expect(find.text('Nur vormerken, noch kein Fund'), findsNothing,
        reason: 'das Anlege-Blatt ist aufgegangen');
    expect(find.text('Heranzoomen'), findsNothing, reason: 'Menü noch offen');
    expect(find.text('Aktualisieren'), findsNothing,
        reason: 'Ebenen-Blatt noch offen');
    expect(find.byType(BottomSheet), findsNothing);
  }

  testWidgets('läuft beim ersten Start an, der Reihe nach, dann nie wieder',
      (tester) async {
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);

    for (final title in kTourTitles) {
      expect(find.text(title), findsOneWidget, reason: 'Schritt „$title"');
      await tester.tap(
          find.text(title == kTourTitles.last ? 'Los geht\'s' : 'Weiter'));
      await settle(tester);
    }
    expect(settings.mapTourSeen, isTrue);
    expect(find.byKey(const ValueKey('coach-bubble')), findsNothing);
    nothingOpen();

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(), settings: settings);
    expect(find.text(kTourTitles.first), findsNothing);
  });

  testWidgets('Aussparung und Ring sitzen auf den echten Widgets',
      (tester) async {
    // Gegen `getRect` geprüft, nie gegen Zahlen: Auf dem kleinen Schirm
    // verkleinert die `FittedBox` die Leiste wirklich. Die alte Tour
    // zeichnete dort eine um 8 px vergrößerte runde Aussparung, die in
    // den Nachbarknopf griff (Screenshots aus der PWA, 2026-09-24).
    for (final size in [const Size(412, 915), const Size(360, 640)]) {
      useScreen(tester, size);
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, signedIn(), settings: fresh());
      final at = ' bei ${size.width}×${size.height}';
      final toolbar = union([
        tester.getRect(tool('Ebenen')),
        tester.getRect(tool('Meine Position')),
      ]);

      // 1 — Fadenkreuz und „Neuer Spot", beide ausgespart.
      final fab = tester.getRect(find.ancestor(
          of: find.text('Neuer Spot'),
          matching: find.byType(FloatingActionButton)));
      expect(painter(tester).lit, hasLength(2), reason: 'zwei Stellen$at');
      expect(painter(tester).lit.any((r) => near(r, fab)), isTrue,
          reason: 'Neuer Spot$at: ${painter(tester).lit} gegen $fab');
      expect(near(painter(tester).ring.single, fab), isTrue,
          reason: 'der Ring nur um den Knopf$at');

      await next(tester); // 2 — lange drücken
      await next(tester); // 3 — Menü: Neuer Spot hier
      expect(find.text('Heranzoomen'), findsOneWidget,
          reason: 'das Kontextmenü ist offen$at');
      final chip = tester.getCenter(find.text('Neuer Spot').last);
      expect(union(painter(tester).ring).contains(chip), isTrue,
          reason: 'Ring auf dem Menüeintrag$at');

      await next(tester); // 4 — die übrigen Einträge
      for (final label in ['Was ist hier?', 'Navigation', 'Heranzoomen']) {
        expect(
            painter(tester)
                .lit
                .any((r) => r.contains(tester.getCenter(find.text(label).last))),
            isTrue,
            reason: '„$label" ausgespart$at');
      }

      await next(tester); // 5 — Ebenen in der Leiste
      expect(find.text('Heranzoomen'), findsNothing,
          reason: 'das Menü ist wieder zu$at');
      final lit = painter(tester).lit.single;
      expect(
          lit.contains(toolbar.topLeft + const Offset(1, 1)) &&
              lit.contains(toolbar.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: 'die ganze Leiste ist ausgespart$at: $lit gegen $toolbar');
      expect(painter(tester).ring.single,
          rectMoreOrLessEquals(tester.getRect(tool('Ebenen'))),
          reason: 'Ring auf „Ebenen"$at');

      await next(tester); // 6 — das Blatt
      expect(find.text('Aktualisieren'), findsOneWidget,
          reason: 'das Ebenen-Blatt ist offen$at');
      expect(union(painter(tester).ring).contains(tester.getCenter(find.text('Waldtypen'))),
          isTrue,
          reason: 'Ring auf „Waldtypen"$at');

      await next(tester); // 7 — der Rest der Leiste
      expect(find.text('Aktualisieren'), findsNothing,
          reason: 'das Blatt ist wieder zu$at');
      expect(
          union(painter(tester).ring),
          rectMoreOrLessEquals(union([
            tester.getRect(tool('Karte filtern')),
            tester.getRect(tool('Unterwegs')),
            tester.getRect(tool('Meine Position')),
          ])),
          reason: 'Ring auf Filter, Unterwegs, Position$at');
    }
  });

  testWidgets('der lange Druck wird vorgeführt, nicht beschrieben',
      (tester) async {
    await pumpApp(tester, signedIn(), settings: fresh());
    await next(tester);
    expect(find.text('Lange drücken'), findsOneWidget);
    expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((c) => c.painter)
            .whereType<FingerPainter>()
            .single
            .gesture,
        CoachGesture.longPress);
  });

  testWidgets('Tippen während der Vorführung löst nichts aus',
      (tester) async {
    // Die Überlagerung schluckt jeden Tipp: Liegt das Menü offen und
    // tippt jemand auf „Neuer Spot", geht es nur weiter.
    await pumpApp(tester, signedIn(), settings: fresh());
    await next(tester);
    await next(tester);
    expect(find.text('Neuer Spot, genau hier'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.text('Neuer Spot').last));
    await settle(tester);
    expect(find.text('Was ist hier?'), findsWidgets, reason: 'Schritt 4');
    expect(find.text('Nur vormerken, noch kein Fund'), findsNothing);
  });

  testWidgets('Überspringen mitten im Menü lässt nichts offen',
      (tester) async {
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);
    await next(tester);
    await next(tester);
    expect(find.text('Heranzoomen'), findsOneWidget);
    await tester.tap(find.text('Überspringen'));
    await settle(tester);
    expect(settings.mapTourSeen, isTrue);
    expect(find.byKey(const ValueKey('coach-bubble')), findsNothing);
    nothingOpen();
  });

  testWidgets('Überspringen im Blatt lässt nichts offen', (tester) async {
    await pumpApp(tester, signedIn(), settings: fresh());
    for (var i = 0; i < 5; i++) {
      await next(tester);
    }
    expect(find.text('Aktualisieren'), findsOneWidget);
    await tester.tap(find.text('Überspringen'));
    await settle(tester);
    nothingOpen();
  });

  testWidgets('die Zurück-Taste beendet die Tour, nicht die App',
      (tester) async {
    // Die Überlagerung liegt über dem Router — ohne eigene Anmeldung beim
    // Zurück-Verteiler bekäme der die Taste, und auf der Karte hieße das,
    // PilzBuddy zu verlassen.
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);
    await next(tester);
    await next(tester); // Menü offen
    final handled = await tester.binding.handlePopRoute();
    await settle(tester);
    expect(handled, isTrue);
    expect(find.byKey(const ValueKey('coach-bubble')), findsNothing);
    expect(settings.mapTourSeen, isTrue);
    nothingOpen();
    expect(tool('Ebenen'), findsOneWidget, reason: 'die App steht noch');
  });

  testWidgets('nach der Tour gehört die Zurück-Taste wieder dem System',
      (tester) async {
    // Die andere Hälfte, und die wiegt schwerer: Ein Abfangen, das
    // stehen bleibt, sperrte den Nutzer in der App ein. Auf der Karte
    // gibt es nichts zurückzunehmen — die Taste muss bis zum System
    // durch (`handlePopRoute` meldet dann `false`).
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);
    expect(await tester.binding.handlePopRoute(), isTrue,
        reason: 'während der Tour fängt sie die Taste');
    await settle(tester);
    expect(await tester.binding.handlePopRoute(), isFalse,
        reason: 'danach nicht mehr');
  });

  testWidgets('die Sprechblase liegt nie auf dem, was sie erklärt',
      (tester) async {
    for (final size in [const Size(412, 915), const Size(360, 640)]) {
      useScreen(tester, size);
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, signedIn(), settings: fresh());

      for (final title in kTourTitles) {
        expect(find.text(title), findsOneWidget,
            reason: 'Schritt „$title" bei ${size.width}×${size.height}');
        final bubble =
            tester.getRect(find.byKey(const ValueKey('coach-bubble')));
        // Und ganz im Bild: Bis 1.205.0 ragte sie beim Schritt zur
        // Leiste auf 360×640 oben hinaus — der Test hier prüfte nur, dass
        // sie nichts zudeckt, und das tut eine Blase außerhalb nie.
        final screen = Offset.zero & size;
        expect(
            screen.contains(bubble.topLeft) &&
                screen.contains(bubble.bottomRight - const Offset(1, 1)),
            isTrue,
            reason: 'Schritt „$title" bei ${size.width}×${size.height}: '
                'Blase $bubble außerhalb');
        final p = painter(tester);
        for (final r in [...p.lit, ...p.ring]) {
          expect(bubble.overlaps(r), isFalse,
              reason: 'Schritt „$title" bei ${size.width}×${size.height}: '
                  'Blase $bubble deckt $r zu');
        }
        if (title == kTourTitles.last) break;
        await next(tester);
      }
    }
  });

  testWidgets('der letzte Schritt führt weiter in die Kurzanleitung',
      (tester) async {
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);
    for (var i = 0; i < kTourTitles.length - 1; i++) {
      await next(tester);
    }
    expect(find.text(kTourTitles.last), findsOneWidget);
    expect(find.text('Überspringen'), findsNothing);
    await tester.tap(find.text('Kurzanleitung'));
    await settle(tester);
    expect(find.textContaining('Das Wichtigste in sechs Schritten'),
        findsOneWidget);
    expect(settings.mapTourSeen, isTrue);
    expect(find.byKey(const ValueKey('coach-bubble')), findsNothing);
  });

  testWidgets('aus der Kurzanleitung neu startbar', (tester) async {
    // Wer sie übersprungen hat, soll sie wiederfinden — dort, wo er
    // ohnehin nach einer Erklärung sucht.
    final settings = FakeSettings(mapTourSeen: true);
    await pumpApp(tester, signedIn(), settings: settings);
    expect(find.text(kTourTitles.first), findsNothing);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    final tile = find.text('Kurzanleitung');
    for (var i = 0; i < 8 && tile.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    await tester.ensureVisible(tile);
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);

    final start = find.text('Tour auf der Karte zeigen');
    for (var i = 0; i < 8 && start.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    await tester.ensureVisible(start);
    await settle(tester);
    await tester.tap(start);
    await settle(tester);

    expect(find.text(kTourTitles.first), findsOneWidget);
    expect(painter(tester).lit, hasLength(2));
  });
}
