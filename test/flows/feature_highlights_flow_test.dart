// Neuheiten nach einer Beförderung (#596) — in der echten App.
//
// Die Zusagen:
//   1. Bestandsnutzer ohne Merker bekommen EINMAL den Rückblick.
//   2. Eine frische Installation bekommt ihn nie — auch nicht nach der
//      Tour, weil sie ihre Version schon beim ersten Start merkt.
//   3. Liegt schon etwas über der Karte, wartet das Blatt, ohne verloren
//      zu gehen.
//   4. „Ausprobieren" führt zum Ziel, und jedes Ziel ist eine Route.
//   5. „Entdecken" zeigt den Neu-Punkt und merkt ihn sich danach.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pilzbuddy/core/router.dart';
import 'package:pilzbuddy/features/highlights/feature_highlights.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

const kVersion = '1.204.0';

void main() {
  FakeBackend signedIn() {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    return backend;
  }

  FeatureHighlight byId(String id) =>
      kFeatureHighlights.singleWhere((h) => h.id == id);

  final recapTitle = find.text('Das kann PilzBuddy inzwischen');

  testWidgets('Bestandsnutzer: Rückblick einmal, danach nie wieder',
      (tester) async {
    final settings = FakeSettings(highlightsSeenVersion: null);
    await pumpApp(tester, signedIn(),
        settings: settings, appVersion: kVersion);

    expect(recapTitle, findsOneWidget);
    expect(find.text(byId(kRecapLead.first).title), findsOneWidget);
    expect(settings.highlightsSeenVersion, kVersion);
    // Die Seiten des Blatts gelten als gesehen, der Rest nicht.
    expect(settings.seenHighlightIds, containsAll(kRecapLead));
    expect(settings.seenHighlightIds, isNot(contains('langer-tipp')));

    // Durchblättern und schließen.
    for (var i = 1; i < kRecapLead.length; i++) {
      await tester.tap(find.text('Weiter'));
      await settle(tester);
      expect(find.text(byId(kRecapLead[i]).title), findsOneWidget);
    }
    await tester.tap(find.text('Fertig'));
    await settle(tester);
    expect(recapTitle, findsNothing);

    // Zweiter Start: nichts.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(),
        settings: settings, appVersion: kVersion);
    expect(recapTitle, findsNothing);
    expect(find.text('Neu in PilzBuddy'), findsNothing);
  });

  testWidgets('frische Installation: kein Rückblick, auch nicht nach der Tour',
      (tester) async {
    final settings =
        FakeSettings(highlightsSeenVersion: null, mapTourSeen: false);
    await pumpApp(tester, signedIn(),
        settings: settings, appVersion: kVersion);
    expect(recapTitle, findsNothing);
    expect(settings.highlightsSeenVersion, kVersion);

    // Tour gesehen, nächster Start: weiterhin nichts.
    settings.mapTourSeen = true;
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(),
        settings: settings, appVersion: kVersion);
    expect(recapTitle, findsNothing);
  });

  testWidgets('Haftungshinweis offen: das Blatt wartet auf den nächsten Start',
      (tester) async {
    final settings =
        FakeSettings(highlightsSeenVersion: null, safetyNoteSeen: false);
    await pumpApp(tester, signedIn(),
        settings: settings, appVersion: kVersion);
    expect(find.text('Kurz vorweg'), findsOneWidget);
    expect(recapTitle, findsNothing);
    // Nicht gemerkt — sonst wäre der Rückblick verloren.
    expect(settings.highlightsSeenVersion, isNull);

    await tester.tap(find.text('Verstanden'));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(),
        settings: settings, appVersion: kVersion);
    expect(recapTitle, findsOneWidget);
  });

  testWidgets('nach einem Update: „Neu in PilzBuddy" mit dem Neuen',
      (tester) async {
    final settings = FakeSettings(highlightsSeenVersion: '1.192.0');
    await pumpApp(tester, signedIn(),
        settings: settings, appVersion: kVersion);
    expect(find.text('Neu in PilzBuddy'), findsOneWidget);
    // Jüngstes zuerst: Naturschutzgebiete (1.201.0).
    expect(find.text(byId('schutzgebiete').title), findsOneWidget);
  });

  testWidgets('„Ausprobieren" führt zum Ziel', (tester) async {
    final settings = FakeSettings(highlightsSeenVersion: null);
    await pumpApp(tester, signedIn(),
        settings: settings, appVersion: kVersion);
    await tester.tap(find.text('Ausprobieren'));
    await settle(tester);
    expect(recapTitle, findsNothing);
    final router = ProviderScope.containerOf(
            tester.element(find.byType(Scaffold).first))
        .read(routerProvider);
    expect(router.routerDelegate.currentConfiguration.uri.path,
        byId(kRecapLead.first).target);
  });

  testWidgets('jedes Ziel ist eine Route der App', (tester) async {
    await pumpApp(tester, signedIn());
    final GoRouter router = ProviderScope.containerOf(
            tester.element(find.byType(Scaffold).first))
        .read(routerProvider);
    for (final h in kFeatureHighlights) {
      final match = router.configuration.findMatch(Uri.parse(h.target));
      expect(match.isNotEmpty, isTrue, reason: '${h.id}: ${h.target}');
      expect(match.uri.path, h.target, reason: h.id);
    }
    for (final extra in ['/profile/entdecken', '/profile/changelog']) {
      expect(router.configuration.findMatch(Uri.parse(extra)).isNotEmpty,
          isTrue,
          reason: extra);
    }
  });

  testWidgets('„Entdecken": Neu-Punkt beim ersten Öffnen, danach gemerkt',
      (tester) async {
    final settings = FakeSettings(seenHighlightIds: {'nachrichten'});
    await pumpApp(tester, signedIn(), settings: settings);
    await openTab(tester, 'Profil');
    final tile = find.text('Entdecken');
    await tester.scrollUntilVisible(tile, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(tile);
    await settle(tester);

    Finder badgeIn(String id) => find.descendant(
        of: find.byKey(ValueKey('discover-$id')), matching: find.text('Neu'));
    // Gesehenes ohne Punkt, Ungesehenes mit — beides auf dem ersten
    // Bildschirm (Karte ist die erste Gruppe), sonst prüfte findsNothing
    // eine Zeile, die gar nicht gebaut ist.
    expect(find.byKey(const ValueKey('discover-pilzampel')), findsOneWidget);
    expect(badgeIn('pilzampel'), findsOneWidget);
    expect(settings.seenHighlightIds,
        containsAll(kFeatureHighlights.map((h) => h.id)));

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);
    expect(find.byKey(const ValueKey('discover-pilzampel')), findsOneWidget);
    expect(badgeIn('pilzampel'), findsNothing);
  });
}
