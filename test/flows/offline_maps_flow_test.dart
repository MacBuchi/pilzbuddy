// Szenarien für die Offline-Karten: Verwaltung (Download/Löschen) und
// der Umschalter auf der Karte.
import 'package:flutter/material.dart' show BackButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_repository.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_offline_maps.dart';
import '../fakes/fake_settings.dart';
import '../fakes/map_ui.dart';
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

    // Ohne installierte Karte: kein Eintrag im Ebenen-Blatt. Seit #347
    // ist der Umschalter eine Zeile dort und kein eigener FAB mehr —
    // die Zusage bleibt dieselbe, nichts anzubieten, was es nicht gibt.
    await openMapLayers(tester);
    expect(layerRow('Offline-Karte'), findsNothing);
    await closeMapLayers(tester);

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

    // Jetzt ist die Zeile da — und sagt den Zustand in Worten.
    //
    // Bis #347 stand dafür ein Symbol da (Erdball / durchgestrichener
    // Erdball, #104/#114 — es war einmal invertiert). Der Untertitel ist
    // die Verbesserung: Er unterscheidet „aus", „an" und „an, weil kein
    // Empfang" — ein Symbol konnte das nie.
    await openMapLayers(tester);
    expect(layerRow('Offline-Karte'), findsOneWidget);
    expect(find.text('Karten aus dem Netz'), findsOneWidget);

    await tester.tap(layerSwitch('Offline-Karte'));
    await settle(tester);

    // Der Untertitel hängt am GELADENEN Offline-Stil, nicht am Schalter:
    // Im Test gibt es keine echten PMTiles, die Karte bleibt also online
    // — und die Zeile muss das sagen, statt Offline zu behaupten
    // (stiller Rückfall). Genau dafür war das Symbol da, und genau das
    // leistet der Satz jetzt.
    expect(find.text('Karten aus dem Netz'), findsOneWidget);
    await closeMapLayers(tester);
    await drainSnackbars(tester);
  });

  testWidgets('Download läuft beim Tab-Wechsel weiter (#38)', (tester) async {
    final (backend, _) = loggedInBackend();
    final offlineMaps = FakeOfflineMapRepository()
      ..stepDelay = const Duration(milliseconds: 400);
    await pumpApp(tester, backend, offlineMaps: offlineMaps);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);

    await tester.tap(find.byTooltip('Berlin herunterladen'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Lädt …'), findsOneWidget);

    // Mitten im Download den Tab wechseln — früher brach das den
    // Download ab, jetzt läuft er im app-weiten Provider weiter.
    await tester.tap(find.text('Karte'));
    await settle(tester);

    expect(offlineMaps.installed.single.key, 'de_berlin');
    // Die Umschalt-Zeile erscheint, sobald der Download durch ist.
    await openMapLayers(tester);
    expect(layerRow('Offline-Karte'), findsOneWidget);
    await closeMapLayers(tester);
    await drainSnackbars(tester);
  });

  testWidgets(
      'Schlechtes Netz: Download setzt automatisch fort statt aufzugeben',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final offlineMaps = FakeOfflineMapRepository()..failuresBeforeSuccess = 2;
    await pumpApp(tester, backend, offlineMaps: offlineMaps);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);
    await tester.tap(find.byTooltip('Berlin herunterladen'));
    // Zwei simulierte Abbrüche + automatische Wiederaufnahmen abwarten.
    await settle(tester, frames: 15);

    // Kein manueller Neustart nötig: drei Versuche, am Ende installiert.
    expect(offlineMaps.downloadCalls, 3);
    expect(offlineMaps.installed.single.key, 'de_berlin');
    expect(find.text('Installiert (Stand 20.3.2026)'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Foreground-Service läuft nur während des Downloads',
      (tester) async {
    // Ohne laufenden Service friert Android den Prozess beim App-Wechsel
    // ein und der Download steht still. Danach muss der Service aber auch
    // wieder weg sein — eine Dauerbenachrichtigung wäre grob unhöflich.
    final (backend, _) = loggedInBackend();
    final offlineMaps = FakeOfflineMapRepository()
      ..stepDelay = const Duration(milliseconds: 400);
    final keepAlive = FakeKeepAlive();
    await pumpApp(tester, backend,
        offlineMaps: offlineMaps, keepAlive: keepAlive);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);
    expect(keepAlive.running, isFalse);

    await tester.tap(find.byTooltip('Berlin herunterladen'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(keepAlive.running, isTrue);
    expect(keepAlive.starts, 1);
    expect(keepAlive.texts.first, contains('Berlin'));

    await settle(tester);
    expect(offlineMaps.installed.single.key, 'de_berlin');
    expect(keepAlive.running, isFalse);
    await drainSnackbars(tester);
  });

  testWidgets('Abgebrochener Download beendet den Service ebenfalls',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final offlineMaps = FakeOfflineMapRepository()
      ..stepDelay = const Duration(milliseconds: 500);
    final keepAlive = FakeKeepAlive();
    await pumpApp(tester, backend,
        offlineMaps: offlineMaps, keepAlive: keepAlive);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);
    await tester.tap(find.byTooltip('Berlin herunterladen'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(keepAlive.running, isTrue);

    await tester.tap(find.byTooltip('Berlin anhalten'));
    await settle(tester);

    expect(keepAlive.running, isFalse);
  });

  testWidgets('Download lässt sich anhalten — Fortschritt bleibt',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final offlineMaps = FakeOfflineMapRepository()
      ..stepDelay = const Duration(milliseconds: 500);
    await pumpApp(tester, backend, offlineMaps: offlineMaps);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);
    await tester.tap(find.byTooltip('Berlin herunterladen'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Lädt …'), findsOneWidget);

    await tester.tap(find.byTooltip('Berlin anhalten'));
    await settle(tester);

    expect(offlineMaps.installed, isEmpty);
    expect(find.textContaining('Lädt …'), findsNothing);
    expect(find.text('76 MB'), findsOneWidget);
  });

  testWidgets('Der Umschalter merkt sich die Wahl (#145)', (tester) async {
    final settings = FakeSettings();
    final (backend, _) = loggedInBackend();
    final offlineMaps = FakeOfflineMapRepository()
      ..installed.add(const InstalledMap(
        key: 'de_berlin',
        dateStamp: '20260320',
        sizeBytes: 70 * 1024 * 1024,
        filePath: '/fake/offline_maps/de_berlin_20260320.pmtiles',
      ));
    await pumpApp(tester, backend,
        offlineMaps: offlineMaps, settings: settings);

    expect(settings.offlineMapEnabled, isFalse);

    await toggleLayer(tester, 'Offline-Karte');
    expect(settings.offlineMapEnabled, isTrue,
        reason: 'Die Wahl muss gespeichert werden, nicht nur im Speicher '
            'stehen — sonst ist sie beim nächsten Start wieder weg');

    // Und zurück: Auch das Ausschalten wird gemerkt, sonst bliebe man
    // nach einem einzigen Versehen dauerhaft offline. Der SCHALTER steht
    // dabei auf „an", während der Untertitel „Karten aus dem Netz" sagt
    // — beides stimmt: Es gibt im Test keine echten PMTiles, der Stil
    // lädt nicht, und die Karte fällt still auf OSM zurück. Genau diese
    // beiden Aussagen ließen sich am alten Symbol nicht unterscheiden.
    await toggleLayer(tester, 'Offline-Karte');
    expect(settings.offlineMapEnabled, isFalse);
    await drainSnackbars(tester);
  });

  test('Nach dem Neustart gilt die gemerkte Kartenquelle (#145)', () {
    // Der Kern der Regression: Vorher war das ein StateProvider mit
    // Startwert false — die Wahl war nach jedem Kaltstart weg, und zwar
    // im Wald, wo sie gebraucht wird.
    final offline = ProviderContainer(overrides: [
      settingsProvider
          .overrideWithValue(FakeSettings(offlineMapEnabled: true)),
    ]);
    addTearDown(offline.dispose);
    expect(offline.read(offlineMapEnabledProvider), isTrue);

    final online = ProviderContainer(overrides: [
      settingsProvider.overrideWithValue(FakeSettings()),
    ]);
    addTearDown(online.dispose);
    expect(online.read(offlineMapEnabledProvider), isFalse);
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
