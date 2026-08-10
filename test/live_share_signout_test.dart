// Abmelden darf keinen Fehlerbericht erzeugen (Issue #124).
//
// Der Poll der Freundes-Standorte lief in einer Endlosschleife weiter,
// während die Sitzung schon weg war, und griff über `currentUser!` ins
// Leere: 37 Berichte „Null check operator used on a null value" in einer
// Woche, auf Android und Web, für einen völlig normalen Vorgang.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/errors.dart';
import 'package:pilzbuddy/data/providers.dart';
import 'package:pilzbuddy/data/session.dart';
import 'package:pilzbuddy/features/map/live_share_providers.dart';
import 'package:pilzbuddy/models/friend_location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes/fake_backend.dart';

/// Repository, das sich verhält wie das echte ohne Sitzung.
class _SignedOutLiveShareRepository extends FakeLiveShareRepository {
  _SignedOutLiveShareRepository(super.backend);

  @override
  Future<List<FriendLocation>> fetchFriendLocations() async =>
      throw const NotSignedInException();
}

void main() {
  tearDown(() => setErrorSink(null));

  test('Ohne Sitzung liefert requireUid einen erkennbaren Fehler', () {
    // Kein Netz nötig: Der Client wird nur angelegt, nicht benutzt.
    final client = SupabaseClient('https://example.invalid', 'anon-key');
    addTearDown(client.dispose);

    expect(client.auth.currentUser, isNull);
    expect(() => client.requireUid, throwsA(isA<NotSignedInException>()));
  });

  test('NotSignedInException hat eine eigene Meldung', () {
    // Nicht „Unerwarteter Fehler" — das würde zum Melden auffordern.
    final message = friendlyError(const NotSignedInException());
    expect(message, contains('Nicht mehr angemeldet'));
    expect(message, isNot(contains('Unerwarteter Fehler')));
  });

  test('Der Poll meldet das Abmelden nicht als Fehler', () async {
    final reported = <String>[];
    setErrorSink((context, _, _) => reported.add(context));

    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
      liveShareRepositoryProvider
          .overrideWithValue(_SignedOutLiveShareRepository(backend)),
      friendLocationsPollProvider
          .overrideWithValue(const Duration(milliseconds: 1)),
    ]);
    addTearDown(container.dispose);

    final locations = await container.read(friendLocationsProvider.future);

    expect(locations, isEmpty,
        reason: 'Ohne Sitzung gibt es nichts zu zeigen.');
    expect(reported, isEmpty,
        reason: 'Ein Abmelden ist kein Fehler und gehört nicht in '
            'error_reports — sonst füllt es den Wochendigest (Issue #124).');
  });

  test('Echte Ladefehler werden weiterhin gemeldet', () async {
    // Die Gegenprobe: Der neue Zweig darf nicht alles verschlucken.
    final reported = <String>[];
    setErrorSink((context, _, _) => reported.add(context));

    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
      liveShareRepositoryProvider
          .overrideWithValue(_FailingLiveShareRepository(backend)),
      friendLocationsPollProvider
          .overrideWithValue(const Duration(milliseconds: 1)),
    ]);
    addTearDown(container.dispose);

    // Ohne Zuhörer läuft der Stream gar nicht erst an.
    container.listen(friendLocationsProvider, (_, _) {});

    // Der Stream schluckt den Fehler und pollt weiter — also auf den
    // Bericht warten statt auf einen Wert.
    for (var i = 0; i < 50 && reported.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(reported, contains('Freundes-Standorte laden'));
  });

  test('Fehlender Empfang wird nicht gemeldet', () async {
    // Dieselbe Lehre wie beim Abmelden, nur häufiger: Der Poll läuft
    // alle paar Sekunden, ein Funkloch schriebe also im Minutentakt
    // nach `error_reports`. In den Digesten KW32 und KW33 waren sechs
    // von acht Berichten „Failed host lookup".
    // Gesammelt wird der FEHLER, nicht der Kontext: Die Schleife des
    // Tests darüber läuft im selben Prozess weiter (ihr Repository wirft
    // immer, der Generator kommt nie an ein `yield` und damit nie an
    // seine Abmeldung) und schreibt denselben Kontext. Nach dem TYP
    // gefragt, ist die Antwort eindeutig.
    final reported = <Object>[];
    setErrorSink((_, error, _) => reported.add(error));

    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
      liveShareRepositoryProvider
          .overrideWithValue(_OfflineLiveShareRepository(backend)),
      friendLocationsPollProvider
          .overrideWithValue(const Duration(milliseconds: 1)),
    ]);
    addTearDown(container.dispose);
    container.listen(friendLocationsProvider, (_, _) {});

    // Lange genug für viele Durchläufe — gemeldet werden darf keiner.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(reported.whereType<SocketException>(), isEmpty,
        reason: 'Kein Netz ist kein Fehlerbericht; sichtbar ist es am '
            'Banner, nicht im Wochendigest.');
  });
}

class _OfflineLiveShareRepository extends FakeLiveShareRepository {
  _OfflineLiveShareRepository(super.backend);

  @override
  Future<List<FriendLocation>> fetchFriendLocations() async =>
      throw const SocketException('Failed host lookup');
}

class _FailingLiveShareRepository extends FakeLiveShareRepository {
  _FailingLiveShareRepository(super.backend);

  @override
  Future<List<FriendLocation>> fetchFriendLocations() async =>
      throw const FormatException('kaputte Antwort');
}
