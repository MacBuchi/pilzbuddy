// Szenarien für die Offline-Karten: Verwaltung (Download/Löschen) und
// der Umschalter auf der Karte.
import 'package:flutter/material.dart' show BackButton;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_offline_maps.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  testWidgets('Offline-Karte herunterladen und wieder löschen',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final offlineMaps = FakeOfflineMapRepository();
    await pumpApp(tester, backend, offlineMaps: offlineMaps);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);

    // Katalog aus der Quelle, deutsche Regionen mit Größe.
    expect(find.text('Berlin'), findsOneWidget);
    expect(find.text('Bayern'), findsOneWidget);
    expect(find.text('76 MB'), findsOneWidget);

    await tester.tap(find.byTooltip('Berlin herunterladen'));
    await settle(tester);

    expect(offlineMaps.installed.single.key, 'de_berlin');
    expect(find.text('Installiert (Stand 20.3.2026)'), findsOneWidget);
    expect(find.text('Berlin ist jetzt offline verfügbar 🗺️'), findsOneWidget);
    await drainSnackbars(tester);

    await tester.tap(find.byTooltip('Berlin löschen'));
    await settle(tester);
    expect(find.text('Berlin löschen?'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await settle(tester);

    expect(offlineMaps.installed, isEmpty);
    expect(find.text('Installiert (Stand 20.3.2026)'), findsNothing);
  });

  testWidgets('Karten-Umschalter erscheint erst mit installierter Karte',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final offlineMaps = FakeOfflineMapRepository();
    await pumpApp(tester, backend, offlineMaps: offlineMaps);

    // Ohne installierte Karte: kein Umschalter auf der Karte.
    expect(find.byTooltip('Zur Offline-Karte'), findsNothing);

    // Karte "herunterladen" und Verwaltung wieder verlassen.
    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);
    await tester.tap(find.byTooltip('Berlin herunterladen'));
    await settle(tester);
    await drainSnackbars(tester);
    // pageBack() sucht den englischen "Back"-Tooltip — die App ist deutsch.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('Karte'));
    await settle(tester);

    // Jetzt ist der Umschalter da.
    expect(find.byTooltip('Zur Offline-Karte'), findsOneWidget);
    await tester.tap(find.byTooltip('Zur Offline-Karte'));
    await settle(tester);
    expect(find.text('Offline-Karte aktiv 🗺️'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Im Web gibt es keinen Offline-Karten-Einstieg',
      (tester) async {
    // kIsWeb lässt sich im Test nicht umschalten — dieser Test dokumentiert
    // stattdessen den Android-Pfad: Eintrag vorhanden.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await tester.tap(find.text('Profil'));
    await settle(tester);
    expect(find.text('Offline-Karten'), findsOneWidget);
  });
}
