// Ohne Empfang zeigt die Karte die zwischengespeicherten Spots — und sagt
// dazu, aus welchem Stand sie stammen.
//
// Der Fall, der bis 1.44.0 kaputt war: Kaltstart im Wald ohne Empfang. Der
// Ladefehler wurde bei jedem Aufrufer zur leeren Liste, die Karte stand
// kommentarlos ohne Spots da. Ein fehlgeschlagener *Refresh* war nie
// betroffen (Riverpod behält den vorherigen Wert) — deshalb prüft der
// letzte Test hier ausdrücklich, dass das so bleibt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/providers.dart';
import 'package:pilzbuddy/features/spots/spot_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_spot_cache.dart';
import '../fakes/test_app.dart';

/// Findet ein Banner über seinen Text, egal wie tief es eingebettet ist.
Finder bannerWith(String fragment) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').contains(fragment));

void main() {
  /// Backend mit einem angemeldeten Nutzer und einem Spot.
  (FakeBackend, FakeSpotRepository) signedInWithSpot() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
      ownerId: me.id,
      lat: 48.1,
      lng: 11.5,
      name: 'Buchenhang',
      species: 'Steinpilz',
    );
    return (backend, FakeSpotRepository(backend));
  }

  testWidgets('Aus dem Zwischenspeicher: Banner nennt den Stand',
      (tester) async {
    final (backend, repo) = signedInWithSpot();
    repo.cachedAt = DateTime(2026, 9, 12);

    await pumpApp(tester, backend, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(repo),
    ]);

    expect(bannerWith('Ohne Empfang'), findsOneWidget);
    expect(bannerWith('12.9.2026'), findsOneWidget,
        reason: 'Ohne Datum weiß niemand, wie alt der Stand ist — und ein '
            'fehlender Spot von gestern sähe nach einem App-Fehler aus.');
    expect(bannerWith('Freundes-Spots fehlen'), findsOneWidget,
        reason: 'Freundes-Spots werden bewusst nicht zwischengespeichert; '
            'ungesagt sähe ihr Fehlen nach einem Fehler aus.');
  });

  testWidgets('Mit Empfang gibt es kein Offline-Banner', (tester) async {
    final (backend, repo) = signedInWithSpot();

    await pumpApp(tester, backend, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(repo),
    ]);

    expect(bannerWith('Ohne Empfang'), findsNothing);
  });

  testWidgets('Die Spots sind da, egal woher sie kommen', (tester) async {
    final (backend, repo) = signedInWithSpot();
    repo.cachedAt = DateTime(2026, 9, 12);

    await pumpApp(tester, backend, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(repo),
    ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));

    expect(container.read(mySpotListProvider).single.name, 'Buchenhang',
        reason: 'Der Zwischenspeicher liefert vollwertige Spots — sonst '
            'wäre die Karte im Wald zwar bevölkert, aber unbrauchbar.');
  });

  testWidgets('Abmelden wirft die lokale Kopie weg', (tester) async {
    // Die Fundstellen eines abgemeldeten Kontos haben auf dem Gerät
    // nichts mehr verloren — und das steht so im Changelog.
    final (backend, repo) = signedInWithSpot();
    final cache = FakeSpotCache();

    await pumpApp(tester, backend, spotCache: cache, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(repo),
    ]);
    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.byTooltip('Abmelden'));
    await settle(tester);

    expect(cache.cleared, isTrue);
    expect(backend.currentUserId, isNull,
        reason: 'Das Aufräumen darf das Abmelden nicht verhindern.');
  });

  testWidgets('Ein fehlgeschlagener Refresh löscht die Spots NICHT',
      (tester) async {
    // Riverpod reicht bei einem Fehler den vorherigen Wert durch
    // (AsyncError.copyWithPrevious). Das ist der Grund, warum das
    // Entsperren im Wald — map_screen invalidiert bei jedem Resume —
    // ungefährlich ist. Wer daran dreht, bricht genau das.
    final (backend, repo) = signedInWithSpot();

    await pumpApp(tester, backend, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(repo),
    ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    expect(container.read(mySpotListProvider), hasLength(1));

    repo.failNextFetch = true;
    container.invalidate(mySpotsProvider);
    await settle(tester);

    expect(container.read(mySpotListProvider), hasLength(1),
        reason: 'Der vorherige Stand muss stehen bleiben.');
  });
}
