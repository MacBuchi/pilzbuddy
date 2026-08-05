// Die RLS-Spiegel für Buddy-Funde (#190) auf Repository-Ebene: Wer sieht
// welche Funde, und wer darf schreiben. Die echten Policies beweist der
// lokale Stack (siehe PR); hier steht sicher, dass der Fake dieselben
// Regeln spricht — sonst testen die Flow-Tests eine andere Welt.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes/fake_backend.dart';

void main() {
  (FakeBackend, FakeUser, FakeUser) withFriend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final lilli = backend.addUser(username: 'lilli92');
    backend.signInAs(me.id);
    backend.addFriendship(lilli.id, me.id);
    addTearDown(backend.dispose);
    return (backend, me, lilli);
  }

  test('Entfreunden versteckt den Buddy-Fund auch für den Spot-Besitzer',
      () async {
    // Regel 3 aus #190, symmetrisch: Endet die Freigabe, bleiben jedem
    // nur die eigenen Funde — versteckt, nicht gelöscht.
    final (backend, me, lilli) = withFriend();
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        species: 'Parasol', foundOn: DateTime(2026, 7, 5), authorId: lilli.id);
    final repo = FakeSpotRepository(backend);

    var snapshot = await repo.fetchMySpots();
    expect(snapshot.spots.single.finds, hasLength(2),
        reason: 'solange die Freundschaft besteht, ist Lillis Fund sichtbar');

    backend.friendships.clear();
    snapshot = await repo.fetchMySpots();
    expect(snapshot.spots.single.finds.map((f) => f.species), ['Steinpilz'],
        reason: 'nach dem Entfreunden bleiben nur die eigenen Funde');
  });

  test('Funde dritter Buddies bleiben verborgen', () async {
    // Betreiber-Entscheid: Fund-Daten wandern nie zu Nicht-Freunden.
    final (backend, me, lilli) = withFriend();
    final tom = backend.addUser(username: 'tom');
    backend.addFriendship(lilli.id, tom.id);
    final spotId = backend.addSpot(
        ownerId: lilli.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        species: 'Krause Glucke',
        foundOn: DateTime(2026, 7, 3),
        authorId: tom.id);
    final repo = FakeSpotRepository(backend);

    final friendSpots = await repo.fetchFriendSpots();
    expect(friendSpots.single.finds.map((f) => f.species), ['Steinpilz'],
        reason: 'tom ist nicht mein Freund — sein Fund geht mich nichts an');
  });

  test('Eigene Funde am Freundes-Spot überleben dessen Detail-Sperre',
      () async {
    // owner_shares_details gate gilt für die Funde des BESITZERS — die
    // eigenen liefert finds_author_all immer.
    final (backend, me, lilli) = withFriend();
    lilli.shareDetails = false;
    final spotId = backend.addSpot(
        ownerId: lilli.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        species: 'Pfifferling', foundOn: DateTime(2026, 7, 4), authorId: me.id);
    final repo = FakeSpotRepository(backend);

    final friendSpots = await repo.fetchFriendSpots();
    expect(friendSpots.single.finds.map((f) => f.species), ['Pfifferling'],
        reason: 'lillis Funde sind gesperrt, meine eigenen nicht');
  });

  test('addFind ohne Freigabe-Beziehung wirft wie die RLS (42501)', () async {
    final (backend, me, lilli) = withFriend();
    final excluded = backend.addSpot(ownerId: lilli.id, sharingExcluded: true);
    final repo = FakeSpotRepository(backend);

    expect(
        () => repo.addFind(spotId: excluded, foundOn: DateTime(2026, 8, 5)),
        throwsA(isA<PostgrestException>()
            .having((e) => e.code, 'code', '42501')));

    // Und die Gegenprobe in Grün: am geteilten Spot geht es, mit dem
    // Eintrager als Autor.
    final shared = backend.addSpot(ownerId: lilli.id, lat: 51.5);
    await repo.addFind(
        spotId: shared, species: 'Steinpilz', foundOn: DateTime(2026, 8, 5));
    final saved =
        backend.spots.firstWhere((s) => s.id == shared).finds.single;
    expect(saved.authorId, me.id);
  });
}
