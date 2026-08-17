// Die drei Tore der Freundes-Standort-Schleife (#316): Ohne
// angenommene Freundschaft wird GAR NICHT gefragt, ohne aktive Freigabe
// nur träge, im Hintergrund gar nicht — und mit aktiver Freigabe bleibt
// der schnelle Takt unangetastet, denn dafür gibt es die Schleife.
//
// Getestet wird das VERHALTEN (gezählte Abfragen am Fake-Repository),
// nicht die Intervall-Konstante — die Vorgabe steht im Issue.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/providers.dart';
import 'package:pilzbuddy/features/map/live_share_providers.dart';
import 'package:pilzbuddy/models/friend_location.dart';
import 'package:pilzbuddy/models/friendship.dart';

import 'fakes/fake_backend.dart';

/// Wirft wie ein Start im Funkloch — für das Rückfall-Tor.
class _OfflineFriendRepository extends FakeFriendRepository {
  _OfflineFriendRepository(super.backend);

  @override
  Future<List<FriendshipEntry>> fetchFriendships() async =>
      throw Exception('SocketException: Failed host lookup');
}

/// Zählt jede Abfrage — die Messgröße aller Tests hier.
class _CountingLiveShareRepository extends FakeLiveShareRepository {
  _CountingLiveShareRepository(super.backend);

  int calls = 0;

  @override
  Future<List<FriendLocation>> fetchFriendLocations() {
    calls++;
    return super.fetchFriendLocations();
  }
}

void main() {
  ({
    ProviderContainer container,
    _CountingLiveShareRepository repo,
    FakeBackend backend,
    FakeUser me,
  }) harness({bool foreground = true, bool friendsUnreachable = false}) {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    final repo = _CountingLiveShareRepository(backend);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
      friendRepositoryProvider.overrideWithValue(friendsUnreachable
          ? _OfflineFriendRepository(backend)
          : FakeFriendRepository(backend)),
      liveShareRepositoryProvider.overrideWithValue(repo),
      // Schneller Takt quasi sofort, träger Takt praktisch nie: So ist
      // die ZAHL der Abfragen die Aussage, ohne an Uhren zu hängen.
      friendLocationsPollProvider
          .overrideWithValue(const Duration(milliseconds: 1)),
      friendLocationsIdlePollProvider
          .overrideWithValue(const Duration(hours: 1)),
      appInForegroundProvider.overrideWith((ref) => foreground),
    ]);
    addTearDown(container.dispose);
    return (container: container, repo: repo, backend: backend, me: me);
  }

  Future<void> settle(ProviderContainer container,
      {int milliseconds = 80}) async {
    container.listen(friendLocationsProvider, (_, _) {});
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
  }

  test('ohne angenommene Freundschaft wird gar nicht gefragt', () async {
    final h = harness();
    // Eine ANFRAGE ist keine Freundschaft — auch mit ihr bleibt es
    // bei null Abfragen.
    final fremd = h.backend.addUser(username: 'fremd');
    h.backend.addFriendship(fremd.id, h.me.id, status: 'pending');

    await settle(h.container);

    expect(h.repo.calls, 0,
        reason: 'Niemand kann mit mir teilen — jede Abfrage wäre eine '
            'leere Antwort auf eine Frage, die niemand gestellt hat '
            '(#316: 240 Abfragen je Stunde und Solo-Nutzer).');
  });

  test('mit Freund ohne Freigabe: genau eine Entdeckungs-Abfrage im '
      'trägen Takt', () async {
    final h = harness();
    final lilli = h.backend.addUser(username: 'lilli92');
    h.backend.addFriendship(lilli.id, h.me.id);

    await settle(h.container);

    expect(h.repo.calls, 1,
        reason: 'Leere Antwort ⇒ träger Takt (hier 1 h): Nach der '
            'ersten Abfrage muss Ruhe sein. Liefe der schnelle Takt, '
            'stünden hier Dutzende.');
  });

  test('mit aktiver Freigabe bleibt der schnelle Takt', () async {
    final h = harness();
    final lilli = h.backend.addUser(username: 'lilli92');
    h.backend.addFriendship(lilli.id, h.me.id);
    h.backend.addLiveShare(lilli.id);

    await settle(h.container);

    expect(h.repo.calls, greaterThan(5),
        reason: 'Genau dieser Fall ist der Zweck der Schleife — er '
            'darf durch #316 nicht langsamer werden.');
    final locations =
        await h.container.read(friendLocationsProvider.future);
    expect(locations, isNotEmpty);
  });

  test('im Hintergrund ruht die Schleife; der Vordergrund weckt sie',
      () async {
    final h = harness(foreground: false);
    final lilli = h.backend.addUser(username: 'lilli92');
    h.backend.addFriendship(lilli.id, h.me.id);
    h.backend.addLiveShare(lilli.id);

    await settle(h.container);
    expect(h.repo.calls, 0,
        reason: 'Für einen Bildschirm, den niemand sieht, wird nicht '
            'gepollt.');

    h.container.read(appInForegroundProvider.notifier).state = true;
    await settle(h.container);
    expect(h.repo.calls, greaterThan(0),
        reason: 'Zurück im Vordergrund fragt der Provider sofort — '
            'sonst wäre das Tor ein Leck statt einer Pause.');
  });

  test('scheitert die Freundschafts-Antwort, wird gepollt wie früher',
      () async {
    // Start im Funkloch: `friendshipsProvider` wirft. Dann lieber
    // vorsichtshalber fragen, als Freigaben still zu verpassen, bis
    // irgendetwas die Freundschaften neu lädt.
    final h = harness(friendsUnreachable: true);

    await settle(h.container);

    expect(h.repo.calls, greaterThan(0),
        reason: 'Unbekannt ist nicht dasselbe wie „keine Freunde" — '
            'im Zweifel gilt das alte Verhalten.');
  });
}
