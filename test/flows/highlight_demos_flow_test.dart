// „Zeig es mir" (#596, dritter Teil) — jede Vorführung aus „Entdecken"
// heraus, in der echten App.
//
// Die Zusagen, für JEDEN Eintrag:
//   1. Es gibt eine Vorführung, und sie zeigt mindestens einen Schritt.
//   2. Jeder gezeigte Schritt findet sein Ziel — die Aussparung hat so
//      viele Stellen wie der Schritt verlangt. Sonst zeigte er ins Leere
//      und ginge nach zwei Sekunden von selbst weiter.
//   3. Die Blase liegt ganz im Bild.
//   4. Danach ist nichts mehr offen: kein Blatt, kein Dialog — und nichts
//      ausgelöst.
//   5. Was nicht jeder hat, hat einen Ersatzschritt: ohne Buddy das
//      Suchfeld, mit Buddy der Verlauf.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/router.dart';
import 'package:pilzbuddy/features/coach/coach.dart';
import 'package:pilzbuddy/features/highlights/feature_highlights.dart';
import 'package:pilzbuddy/features/highlights/highlight_demos.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

final bubble = find.byKey(const ValueKey('coach-bubble'));

CoachPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<CoachPainter>()
    .single;

String path(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first))
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .path;

void main() {
  late FakeBackend backend;
  late String me;

  FakeBackend world({bool buddy = true}) {
    backend = FakeBackend();
    me = backend.addUser(username: 'testpilz').id;
    backend.signInAs(me);
    backend.addSpot(ownerId: me, name: 'Buchenhang', species: 'Steinpilz');
    if (buddy) {
      backend.addFriendship(me, backend.addUser(username: 'waldfee').id);
    }
    return backend;
  }

  Future<void> openDiscover(WidgetTester tester) async {
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(routerProvider)
        .go('/profile/entdecken');
    await settle(tester);
  }

  /// Startet die Vorführung von [id] aus „Entdecken" und geht sie durch.
  Future<List<String>> run(WidgetTester tester, String id) async {
    await openDiscover(tester);
    final button = find.byKey(ValueKey('show-$id'));
    await tester.scrollUntilVisible(button, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(button);
    await settle(tester, frames: 3);
    await tester.tap(button);
    await settle(tester);

    final script = kHighlightDemos[id]!.script;
    final shown = <String>[];
    for (var i = 0; i < 12 && bubble.evaluate().isNotEmpty; i++) {
      final step = script.steps
          .firstWhere((s) => find.text(s.title).evaluate().isNotEmpty);
      shown.add(step.title);
      // Liegt das Ziel weiter unten in einer Liste, scrollt die Maschine
      // erst dorthin — das dauert ein paar Bilder.
      for (var f = 0;
          f < 40 && painter(tester).lit.length != step.lit.length;
          f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Das Ziel ist gefunden, nicht nur gesucht.
      expect(painter(tester).lit, hasLength(step.lit.length),
          reason: '$id, „${step.title}": Ziel nicht gefunden');
      final screen = Offset.zero &
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final box = tester.getRect(bubble);
      expect(
          screen.contains(box.topLeft) &&
              screen.contains(box.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: '$id, „${step.title}": Blase $box außerhalb');
      final last = find.text('Los geht\'s');
      await tester
          .tap(last.evaluate().isNotEmpty ? last : find.text('Weiter'));
      await settle(tester);
    }
    expect(bubble, findsNothing, reason: '$id: läuft noch');
    expect(find.byType(BottomSheet), findsNothing, reason: '$id: Blatt offen');
    expect(find.byType(Dialog), findsNothing, reason: '$id: Dialog offen');
    return shown;
  }

  test('jeder Eintrag hat eine Vorführung, und keine zeigt ins Leere', () {
    expect(kHighlightDemos.keys.toSet(),
        {for (final h in kFeatureHighlights) h.id});
    for (final demo in kHighlightDemos.values) {
      expect(demo.script.steps, isNotEmpty, reason: demo.script.id);
    }
  });

  for (final h in kFeatureHighlights) {
    testWidgets('„${h.title}": vorgeführt, danach nichts offen',
        (tester) async {
      await pumpApp(tester, world());
      final shown = await run(tester, h.id);
      expect(shown, isNotEmpty, reason: h.id);
    });
  }

  testWidgets('auf einem kleinen Schirm findet jede ihr Ziel, im Bild',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final h in kFeatureHighlights) {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, world());
      expect(await run(tester, h.id), isNotEmpty, reason: h.id);
    }
  });

  testWidgets('Nachrichten: mit Buddy endet sie im Verlauf', (tester) async {
    await pumpApp(tester, world());
    await openDiscover(tester);
    final button = find.byKey(const ValueKey('show-nachrichten'));
    await tester.scrollUntilVisible(button, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(button);
    await settle(tester, frames: 3);
    await tester.tap(button);
    await settle(tester);
    expect(find.text('Zum Verlauf'), findsOneWidget);
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(find.text('Schreib los'), findsOneWidget);
    expect(path(tester), startsWith('/friends/chat/'));
    await tester.tap(find.text('Los geht\'s'));
    await settle(tester);
    expect(path(tester), '/friends', reason: 'der Verlauf ist wieder zu');
  });

  testWidgets('Nachrichten: ohne Buddy zeigt sie das Suchfeld',
      (tester) async {
    await pumpApp(tester, world(buddy: false));
    final shown = await run(tester, 'nachrichten');
    expect(shown, ['Erst einen Buddy finden']);
  });

  testWidgets('Artgalerie: endet im Meldedialog, und der geht wieder zu',
      (tester) async {
    await pumpApp(tester, world());
    final shown = await run(tester, 'galerie-foto');
    expect(shown, ['Eine Art öffnen', 'Ganz unten', 'Bilder für die Galerie']);
    expect(path(tester), '/pilze');
  });

  testWidgets('die Tour des Reiters fällt nicht über die Vorführung her',
      (tester) async {
    // Spots zum ersten Mal über „Zeig es mir" — dort wartet auch die
    // Reiter-Tour. Sie darf weder dazwischen noch direkt danach laufen.
    await pumpApp(tester, world(),
        settings: FakeSettings(seenCoachTours: {}));
    final shown = await run(tester, 'spot-korrigieren');
    expect(shown.first, 'Einen Spot öffnen');
    await settle(tester);
    expect(bubble, findsNothing, reason: 'keine Tour hinterher');
  });
}
