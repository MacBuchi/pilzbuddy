// Die kurzen Touren je Reiter (#596, zweiter Teil) — in der echten App.
//
// Die Zusagen:
//   1. Jede läuft beim ersten Besuch ihres Reiters an, danach nie wieder.
//   2. Ohne eigene Daten zeigt sie Beispiele — gekennzeichnet, nur
//      während der Tour, und nichts davon landet in den Daten.
//   3. Die Karten-Tour geht vor.
//   4. Sie FÜHRT VOR: Das Spot-Blatt geht auf, die Artseite geht auf —
//      und beides ist danach wieder zu.
//   5. Schritte an Dingen, die es nicht gibt, fallen weg statt ins Leere
//      zu zeigen.
//   6. Aus der Kurzanleitung lässt sich jede neu starten.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/router.dart';
import 'package:pilzbuddy/features/coach/coach.dart';
import 'package:pilzbuddy/features/help/map_tour.dart';
import 'package:pilzbuddy/features/help/tab_tours.dart';
import 'package:pilzbuddy/features/help/tour_examples.dart';
import 'package:pilzbuddy/features/spots/spot_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

final bubble = find.byKey(const ValueKey('coach-bubble'));

CoachPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<CoachPainter>()
    .single;

bool near(Rect a, Rect b) =>
    (a.left - b.left).abs() < 0.5 &&
    (a.top - b.top).abs() < 0.5 &&
    (a.right - b.right).abs() < 0.5 &&
    (a.bottom - b.bottom).abs() < 0.5;

String titleOf(CoachScript script, int i) => script.steps[i].title;

String path(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first))
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .path;

/// Geht die laufende Tour bis zum Ende durch und sagt, welche Schritte
/// sie gezeigt hat.
final intro = find.byKey(const ValueKey('coach-intro'));

/// Geht die laufende Tour bis zum Ende durch und sagt, welche Schritte
/// sie gezeigt hat — die Startseite mitgezählt (dort „Zeig's mir").
Future<List<String>> walk(WidgetTester tester, CoachScript script,
    {void Function(String title)? at}) async {
  final shown = <String>[];
  if (intro.evaluate().isNotEmpty) {
    final step = script.steps.first;
    shown.add(find.text(step.title).evaluate().isNotEmpty
        ? step.title
        : step.chainTitle!);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
  }
  for (var i = 0; i < 20 && bubble.evaluate().isNotEmpty; i++) {
    final title = script.tourSteps
        .map((s) => s.title)
        .firstWhere((t) => find.text(t).evaluate().isNotEmpty);
    shown.add(title);
    // Die Blase liegt ganz im Bild — sonst ist „Weiter" nicht zu
    // erreichen (auf der Artseite so passiert, bevor sie an den Rand
    // rücken konnte).
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final box = tester.getRect(bubble);
    expect(screen.contains(box.topLeft) && screen.contains(box.bottomRight - const Offset(1, 1)),
        isTrue, reason: '„$title": Blase $box außerhalb von $screen');
    at?.call(title);
    final last = find.text('Los geht\'s');
    await tester.tap(last.evaluate().isNotEmpty ? last : find.text('Weiter'));
    await settle(tester);
  }
  return shown;
}

void main() {
  late FakeBackend backend;
  late String me;

  FakeBackend signedIn() {
    backend = FakeBackend();
    me = backend.addUser(username: 'testpilz').id;
    backend.signInAs(me);
    return backend;
  }

  FakeSettings noTabTours() => FakeSettings(seenCoachTours: {});

  test('jede Reiter-Tour steht in der Vorgabe der Fakes', () {
    // Sonst bekäme jeder Bestandstest, der den Reiter öffnet, sie über
    // den Schirm gelegt.
    expect({for (final s in kTabTourScripts) s.id},
        FakeSettings.kFakeAllTabToursSeen);
  });

  testWidgets('Spots: vorgeführt am ersten Spot, danach nie wieder',
      (tester) async {
    final settings = noTabTours();
    signedIn();
    backend.addSpot(ownerId: me, name: 'Buchenhang', species: 'Steinpilz');
    await pumpApp(tester, backend, settings: settings);
    expect(bubble, findsNothing, reason: 'auf der Karte läuft nichts');
    await openTab(tester, 'Spots');

    final shown = await walk(tester, kSpotsTourScript, at: (title) {
      final p = painter(tester);
      switch (title) {
        case 'Das Spot-Blatt':
          // Das Blatt ist WIRKLICH offen, und ausgespart sind seine Knöpfe.
          // Die Zeile mit BEIDEN Knöpfen, nicht die im Knopf selbst.
          final entries = find
              .ancestor(
                  of: find.text('Fund eintragen'), matching: find.byType(Row))
              .evaluate()
              .firstWhere((e) =>
                  find
                      .descendant(
                          of: find.byElementPredicate((x) => x == e),
                          matching: find.text('Nichts gefunden'))
                      .evaluate()
                      .isNotEmpty);
          final entriesRect =
              tester.getRect(find.byElementPredicate((x) => x == entries));
          expect(near(p.lit.single, entriesRect), isTrue,
              reason: '${p.lit} gegen $entriesRect');
        case 'Zeig mir, wo':
          expect(find.byType(BottomSheet), findsNothing,
              reason: 'das Blatt ist wieder zu');
          final button = tester.getRect(find.ancestor(
              of: find.byIcon(Icons.map_outlined),
              matching: find.byType(IconButton)));
          expect(near(p.ring.single, button), isTrue,
              reason: '${p.ring} gegen $button');
      }
    });
    expect(shown, [for (final s in kSpotsTourScript.steps) s.title]);
    expect(settings.seenCoachTours, contains('spots'));
    expect(find.byType(BottomSheet), findsNothing);
    expect(path(tester), '/spots', reason: 'nichts ausgelöst');

    await openTab(tester, 'Karte');
    await openTab(tester, 'Spots');
    expect(bubble, findsNothing);
  });

  testWidgets('Spots: ohne Spot führt die Tour ein Beispiel vor, danach '
      'ist es weg', (tester) async {
    final settings = noTabTours();
    await pumpApp(tester, signedIn(), settings: settings);
    await openTab(tester, 'Spots');
    expect(find.text('Deine Spots'), findsOneWidget, reason: 'Startseite');

    final shown = await walk(tester, kSpotsTourScript, at: (title) {
      final p = painter(tester);
      switch (title) {
        case 'Deine Spots als Liste':
          expect(find.byKey(kExampleSpotKey), findsOneWidget);
          expect(
              find.descendant(
                  of: find.byKey(kExampleSpotKey),
                  matching: find.byKey(kTourExampleBadgeKey)),
              findsOneWidget,
              reason: 'als Beispiel gekennzeichnet');
          expect(p.lit.single.height, greaterThan(0));
        case 'Das Spot-Blatt':
          expect(find.byKey(kExampleSpotSheetKey), findsOneWidget,
              reason: 'das Beispiel-Blatt ist offen');
          expect(
              find.descendant(
                  of: find.byKey(kExampleSpotSheetKey),
                  matching: find.byKey(kTourExampleBadgeKey)),
              findsOneWidget);
          expect(find.text('Nichts gefunden'), findsWidgets);
        case 'Zeig mir, wo':
          expect(find.byType(BottomSheet), findsNothing);
      }
    });
    expect(shown, [for (final s in kSpotsTourScript.steps) s.title],
        reason: 'kein Schritt fällt weg');
    expect(settings.seenCoachTours, contains('spots'));
    expect(find.byKey(kExampleSpotKey), findsNothing, reason: 'danach weg');
    expect(find.byKey(kTourExampleBadgeKey), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(backend.spots, isEmpty, reason: 'gezeichnet, nie gespeichert');
    expect(find.textContaining('Noch kein eigener Spot'), findsOneWidget);
  });

  testWidgets('mit einem echten Spot kein Beispiel', (tester) async {
    signedIn();
    backend.addSpot(ownerId: me, name: 'Eichenrand', species: 'Steinpilz');
    await pumpApp(tester, backend, settings: noTabTours());
    await openTab(tester, 'Spots');
    await walk(tester, kSpotsTourScript, at: (_) {
      expect(find.byKey(kExampleSpotKey), findsNothing);
      expect(find.byKey(kExampleSpotSheetKey), findsNothing);
    });
  });

  testWidgets('ein verdeckter Reiter startet nichts, auch wenn er nachlädt',
      (tester) async {
    // Die Reiter bleiben nach dem ersten Besuch im Baum. Lädt die Liste
    // nach, während man auf der Karte ist, darf die Spot-Tour nicht über
    // die Karte fallen — ihre Anker lägen in einem verdeckten Reiter.
    // Ungesehen und verdeckt ist sie nach einem Besuch, bei dem gerade
    // etwas anderes lief (eine Vorführung) — das stellt `reserve` nach.
    final settings = noTabTours();
    await pumpApp(tester, signedIn(), settings: settings);
    final coach = ProviderScope.containerOf(
            tester.element(find.byType(Scaffold).first))
        .read(coachProvider.notifier);
    coach.reserve();
    await openTab(tester, 'Spots');
    expect(intro, findsNothing, reason: 'die Maschine war belegt');
    coach.release();
    await openTab(tester, 'Karte');
    backend.addSpot(ownerId: me, name: 'Buchenhang');
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .invalidate(mySpotsProvider);
    await settle(tester);
    expect(intro, findsNothing, reason: 'nicht über der Karte');
    expect(bubble, findsNothing);

    await openTab(tester, 'Spots');
    expect(find.text(titleOf(kSpotsTourScript, 0)), findsOneWidget);
  });

  testWidgets('Überspringen im Spot-Blatt lässt nichts offen',
      (tester) async {
    final settings = noTabTours();
    signedIn();
    backend.addSpot(ownerId: me, name: 'Buchenhang');
    await pumpApp(tester, backend, settings: settings);
    await openTab(tester, 'Spots');
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(find.text('Fund eintragen'), findsOneWidget);
    await tester.tap(find.text('Überspringen'));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(bubble, findsNothing);
    expect(settings.seenCoachTours, contains('spots'));
  });

  testWidgets('die Karten-Tour geht vor', (tester) async {
    signedIn();
    backend.addSpot(ownerId: me, name: 'Buchenhang');
    await pumpApp(tester, backend,
        settings: FakeSettings(mapTourSeen: false, seenCoachTours: {}));
    expect(find.text('Willkommen bei PilzBuddy'), findsOneWidget);
    expect(find.text(titleOf(kSpotsTourScript, 0)), findsNothing);
  });

  testWidgets('Pilze: die Artseite geht auf und wieder zu', (tester) async {
    final settings = noTabTours();
    await pumpApp(tester, signedIn(), settings: settings);
    await openTab(tester, 'Pilze');

    String? detailPath;
    final shown = await walk(tester, kPilzeTourScript, at: (title) {
      final p = painter(tester);
      switch (title) {
        case 'Wann gemeldet wird':
          expect(p.ring.single.width, 84, reason: 'die Balken der Zeile');
        case 'Zuerst die Warnung':
          detailPath = path(tester);
          expect(detailPath, startsWith('/pilze/'));
          expect(p.lit.single.height, greaterThan(0));
      }
    });
    expect(detailPath, isNotNull, reason: 'die Seite war offen');
    expect(shown.take(5), [for (final s in kPilzeTourScript.steps.take(5)) s.title]);
    expect(path(tester), '/pilze', reason: 'wieder zurück in der Liste');
    expect(settings.seenCoachTours, contains('pilze'));
  });

  testWidgets('Buddys: ohne Buddy und Fotos führt die Tour Beispiele vor',
      (tester) async {
    final settings = noTabTours();
    await pumpApp(tester, signedIn(), settings: settings);
    await openTab(tester, 'Buddys');
    final shown = await walk(tester, kBuddysTourScript, at: (title) {
      switch (title) {
        case 'Fundfotos deiner Buddys':
          expect(find.byKey(kExampleGalleryKey), findsOneWidget);
          expect(near(painter(tester).lit.single,
                  tester.getRect(find.byKey(kExampleGalleryKey))),
              isTrue);
        case 'Name und Nachrichten':
          expect(find.byKey(kExampleBuddyKey), findsOneWidget);
          expect(
              find.descendant(
                  of: find.byKey(kExampleBuddyKey),
                  matching: find.byKey(kTourExampleBadgeKey)),
              findsOneWidget);
      }
    });
    expect(shown, [for (final s in kBuddysTourScript.steps) s.title],
        reason: 'kein Schritt fällt weg');
    expect(settings.seenCoachTours, contains('buddys'));
    expect(find.byKey(kExampleBuddyKey), findsNothing, reason: 'danach weg');
    expect(find.byKey(kExampleGalleryKey), findsNothing);
    expect(find.textContaining('Noch keine Buddys verbunden'), findsOneWidget);
    expect(path(tester), '/friends', reason: 'nichts ausgelöst');
  });

  testWidgets('Beispiele auf einem kleinen Schirm: jede Blase im Bild',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, signedIn(), settings: noTabTours());
    for (final (tab, script) in [
      ('Spots', kSpotsTourScript),
      ('Buddys', kBuddysTourScript),
    ]) {
      await openTab(tester, tab);
      final shown = await walk(tester, script);
      expect(shown, [for (final s in script.steps) s.title], reason: tab);
    }
  });

  testWidgets('Buddys: Stift und Sprechblase am ersten Buddy',
      (tester) async {
    signedIn();
    final buddy = backend.addUser(username: 'waldfee').id;
    backend.addFriendship(me, buddy);
    await pumpApp(tester, backend, settings: noTabTours());
    await openTab(tester, 'Buddys');
    final shown = await walk(tester, kBuddysTourScript, at: (title) {
      if (title != 'Name und Nachrichten') return;
      final ring = painter(tester).ring;
      expect(ring, hasLength(2));
      expect(ring.any((r) => near(r, tester.getRect(find.byKey(messageButtonKeyOf(buddy))))),
          isTrue);
    });
    expect(shown.last, 'Name und Nachrichten');
  });

  testWidgets('auf einem kleinen Schirm bleibt jede Blase im Bild',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    signedIn();
    backend.addSpot(ownerId: me, name: 'Buchenhang', species: 'Steinpilz');
    final buddy = backend.addUser(username: 'waldfee').id;
    backend.addFriendship(me, buddy);
    await pumpApp(tester, backend, settings: noTabTours());
    for (final (tab, script) in [
      ('Spots', kSpotsTourScript),
      ('Pilze', kPilzeTourScript),
      ('Buddys', kBuddysTourScript),
    ]) {
      await openTab(tester, tab);
      final shown = await walk(tester, script);
      expect(shown, isNotEmpty, reason: tab);
    }
  });

  testWidgets('aus der Kurzanleitung neu startbar, auch wenn gesehen',
      (tester) async {
    await pumpApp(tester, signedIn());
    await openTab(tester, 'Profil');
    final tile = find.text('Kurzanleitung');
    for (var i = 0; i < 8 && tile.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    await tester.ensureVisible(tile);
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);

    final start = find.byKey(const ValueKey('tab-tour-buddys'));
    for (var i = 0; i < 8 && start.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    await tester.ensureVisible(start);
    await settle(tester);
    await tester.tap(start);
    await settle(tester);

    expect(path(tester), '/friends');
    expect(find.text('Deine Buddys'), findsOneWidget, reason: 'Startseite');
  });
  testWidgets('„Nicht jetzt" im Reiter: diese Sitzung Ruhe, beim nächsten '
      'Start wieder', (tester) async {
    final settings = noTabTours();
    await pumpApp(tester, signedIn(), settings: settings);
    await openTab(tester, 'Buddys');
    expect(find.text('Deine Buddys'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-intro-later')));
    await settle(tester);
    expect(intro, findsNothing);
    expect(settings.seenCoachTours, isNot(contains('buddys')));

    await openTab(tester, 'Karte');
    await openTab(tester, 'Buddys');
    expect(intro, findsNothing, reason: 'nicht bei jedem Reiterwechsel');

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(), settings: settings);
    await openTab(tester, 'Buddys');
    expect(find.text('Deine Buddys'), findsOneWidget,
        reason: 'nächster Start fragt wieder');
  });

  testWidgets('erster Start: Karte, dann „Weiter mit den Spots?" — '
      '„Später" beendet die Kette', (tester) async {
    signedIn();
    backend.addSpot(ownerId: me, name: 'Buchenhang', species: 'Steinpilz');
    final settings = FakeSettings(mapTourSeen: false, seenCoachTours: {});
    await pumpApp(tester, backend, settings: settings);
    await walk(tester, kWelcomeTourScript);
    expect(settings.mapTourSeen, isTrue);

    // Die Kette fragt an der Grenze, statt einfach weiterzulaufen.
    expect(path(tester), '/spots');
    expect(find.text('Weiter mit den Spots?'), findsOneWidget);
    expect(find.text('Später'), findsOneWidget);
    final shown = await walk(tester, kSpotsTourScript);
    expect(shown.first, 'Weiter mit den Spots?');
    expect(settings.seenCoachTours, contains('spots'));

    expect(path(tester), '/pilze');
    expect(find.text('Weiter mit den Pilzen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-intro-later')));
    await settle(tester);
    expect(intro, findsNothing);
    expect(bubble, findsNothing, reason: 'die Kette ist zu Ende');
    expect(settings.seenCoachTours, isNot(contains('pilze')));
    expect(settings.seenCoachTours, isNot(contains('buddys')));

    // Die Buddys kamen nicht mehr dran — ihre Tour wartet auf den ersten
    // Besuch, mit ihrer eigenen Startseite.
    await openTab(tester, 'Buddys');
    expect(find.text('Deine Buddys'), findsOneWidget);
  });
}

Key messageButtonKeyOf(String otherId) => ValueKey('message-button-$otherId');
