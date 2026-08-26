// Das feine Waldgitter am Stück vorladen (#264) — der Weg durch die App.
//
// Was auf der Platte landet, beweist `forest_block_repository_test.dart`
// gegen einen MockClient. Hier geht es um das, was nur im Zusammenspiel
// sichtbar wird: dass der Knopf die Zustimmung erteilt, dass der
// Foreground-Service mitläuft und wieder endet, und dass ein Fehlschlag
// nicht still bleibt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_block_providers.dart';
import 'package:pilzbuddy/features/offline_maps/offline_map_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_forest_blocks.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  List<Override> withRepository(FakeForestBlockRepository repository) => [
        forestBlockRepositoryProvider.overrideWithValue(repository),
        forestBlockCatalogLoaderProvider
            .overrideWithValue(repository.loadCatalog),
        // Der Vorlauf wiederholt bei Netzfehlern geduldig — im Test soll
        // das nicht in echter Wartezeit stattfinden.
        mapDownloadDelaysProvider.overrideWithValue((
          retry: const Duration(milliseconds: 1),
          networkPoll: const Duration(milliseconds: 1),
        )),
      ];

  Future<void> openOfflineMaps(WidgetTester tester) async {
    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Offline-Karten'));
    await settle(tester);
    // Die Waldkachel steht unter den Regionen und dem Auto-Schalter
    // (#332) — auf dem Testschirm also unterhalb des Sichtbaren, und was
    // eine ListView nicht zeigt, baut sie auch nicht.
    await tester.scrollUntilVisible(
        find.text('Feine Waldkarte (≈ 100 m)'), 200,
        scrollable: find.byType(Scrollable).last);
    await settle(tester);
  }

  testWidgets('ohne Zustimmung nennt die Kachel nur die ungefähre Größe',
      (tester) async {
    // Der Katalog wird ohne Zustimmung nicht angefasst (#253) — die
    // Kachel darf deshalb keine Genauigkeit vortäuschen, die sie nicht
    // hat.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openOfflineMaps(tester);

    expect(find.text('Feine Waldkarte (≈ 100 m)'), findsOneWidget);
    expect(find.text('rund 26 MB'), findsOneWidget);
    expect(find.byTooltip('Feine Waldkarte herunterladen'), findsOneWidget);
    expect(find.byTooltip('Feine Waldkarte löschen'), findsNothing);
  });

  testWidgets('vorladen holt alles, stimmt zu und meldet sich',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final settings = FakeSettings();
    final keepAlive = FakeKeepAlive();
    final repository = FakeForestBlockRepository(
        catalog: fakeForestCatalog(blockCount: 4, bytes: 1024 * 1024));
    await pumpApp(tester, backend,
        settings: settings,
        keepAlive: keepAlive,
        extraOverrides: withRepository(repository));
    await openOfflineMaps(tester);

    await tester.tap(find.byTooltip('Feine Waldkarte herunterladen'));
    await settle(tester);

    expect(repository.installed, hasLength(4));
    expect(settings.forestFineEnabled, isTrue,
        reason: 'der Knopf IST die Zustimmung — ohne sie zeigte die Karte '
            'die eben geladenen Daten nicht an');
    expect(find.textContaining('offline verfügbar'), findsOneWidget);
    expect(find.textContaining('Vollständig geladen'), findsOneWidget);
    expect(find.byTooltip('Feine Waldkarte herunterladen'), findsNothing);
    expect(find.byTooltip('Feine Waldkarte löschen'), findsOneWidget);
    expect(keepAlive.starts, 1);
    expect(keepAlive.running, isFalse,
        reason: 'der Service gehört nach getaner Arbeit beendet');
    await drainSnackbars(tester);
  });

  testWidgets('während des Ladens zeigt die Kachel Fortschritt und Halt',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final keepAlive = FakeKeepAlive();
    final repository = FakeForestBlockRepository(
        catalog: fakeForestCatalog(blockCount: 4),
        stepDelay: const Duration(milliseconds: 400));
    await pumpApp(tester, backend,
        keepAlive: keepAlive, extraOverrides: withRepository(repository));
    await openOfflineMaps(tester);

    await tester.tap(find.byTooltip('Feine Waldkarte herunterladen'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Lädt …'), findsOneWidget);
    expect(find.byTooltip('Feine Waldkarte anhalten'), findsOneWidget);
    expect(keepAlive.running, isTrue,
        reason: 'ohne Service friert Android den Prozess beim App-Wechsel '
            'ein und der Download steht still');

    await tester.tap(find.byTooltip('Feine Waldkarte anhalten'));
    await settle(tester, frames: 20);

    expect(repository.installed, hasLength(lessThan(4)));
    expect(find.byTooltip('Feine Waldkarte vervollständigen'), findsOneWidget,
        reason: 'das Angefangene bleibt liegen, der Rest ist nachholbar');
    expect(keepAlive.running, isFalse);
  });

  testWidgets('wieder löschen gibt den Platz frei', (tester) async {
    final (backend, _) = loggedInBackend();
    final repository = FakeForestBlockRepository();
    await pumpApp(tester, backend,
        extraOverrides: withRepository(repository));
    await openOfflineMaps(tester);

    await tester.tap(find.byTooltip('Feine Waldkarte herunterladen'));
    await settle(tester);
    await drainSnackbars(tester);

    await tester.tap(find.byTooltip('Feine Waldkarte löschen'));
    await settle(tester);
    expect(find.text('Feine Waldkarte löschen?'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await settle(tester);

    expect(repository.installed, isEmpty);
    expect(find.byTooltip('Feine Waldkarte herunterladen'), findsOneWidget);
    expect(find.byTooltip('Feine Waldkarte löschen'), findsNothing);
  });

  testWidgets('ein Fehlschlag sagt es und lässt den Knopf stehen',
      (tester) async {
    // Der Vorlauf ist das Gegenteil des Wegs auf Bedarf: Wer ihn tippt,
    // will die Daten JETZT — ein stilles Nichtstun wäre hier falsch.
    final (backend, _) = loggedInBackend();
    final keepAlive = FakeKeepAlive();
    final repository = FakeForestBlockRepository(failAt: 2);
    await pumpApp(tester, backend,
        keepAlive: keepAlive, extraOverrides: withRepository(repository));
    await openOfflineMaps(tester);

    await tester.tap(find.byTooltip('Feine Waldkarte herunterladen'));
    await settle(tester, frames: 40);

    expect(find.textContaining('Feine Waldkarte:'), findsOneWidget);
    expect(find.byTooltip('Feine Waldkarte vervollständigen'), findsOneWidget,
        reason: 'die zwei geholten Blöcke zählen, der Rest ist offen');
    expect(keepAlive.running, isFalse,
        reason: 'auch nach einem Fehlschlag darf keine Benachrichtigung '
            'stehen bleiben');
    await drainSnackbars(tester);
  });

  testWidgets('ohne je gesehenen Katalog meldet der Vorlauf einen Fehler',
      (tester) async {
    // Kein Katalog heißt: kein Netz und noch nie einen gesehen. Als
    // Erfolg zu melden, dass „nichts zu tun" war, wäre eine Lüge.
    final (backend, _) = loggedInBackend();
    final repository = FakeForestBlockRepository(catalogReachable: false);
    await pumpApp(tester, backend,
        extraOverrides: withRepository(repository));
    await openOfflineMaps(tester);

    await tester.tap(find.byTooltip('Feine Waldkarte herunterladen'));
    await settle(tester, frames: 40);

    expect(find.textContaining('Feine Waldkarte:'), findsOneWidget);
    expect(find.textContaining('offline verfügbar'), findsNothing);
    await drainSnackbars(tester);
  });
}
