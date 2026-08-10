// Die Wiedervorlage (#267): Reihenfolge, Auflösung lokaler Referenzen,
// und die Unterscheidung „später nochmal" von „das wird nie etwas".
//
// Gegen ein Repository-Double statt gegen den FakeBackend: Hier geht es
// um die Reaktion auf FEHLER, und die lassen sich so gezielt auslösen.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/outbox.dart';
import 'package:pilzbuddy/data/outbox_runner.dart';
import 'package:pilzbuddy/data/spot_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'fakes/fake_outbox.dart';

/// Zeichnet auf, was gesendet wurde, und wirft auf Wunsch.
class _RecordingRepository implements SpotRepository {
  _RecordingRepository({this.onSpot, this.onFinds});

  /// Wirft, wenn gesetzt — sonst wird die id zurückgegeben.
  final Object? Function(String clientId)? onSpot;
  final Object? Function(String spotId)? onFinds;

  final spots = <String>[]; // clientIds in Sende-Reihenfolge
  final finds = <String>[]; // spotIds in Sende-Reihenfolge

  @override
  Future<String> addSpot({
    required double lat,
    required double lng,
    String? name,
    required List<NewFind> finds,
    String? clientId,
  }) async {
    final error = onSpot?.call(clientId!);
    if (error != null) throw error;
    spots.add(clientId!);
    return 'server-$clientId';
  }

  @override
  Future<void> addFinds({
    required String spotId,
    required List<NewFind> finds,
  }) async {
    final error = onFinds?.call(spotId);
    if (error != null) throw error;
    this.finds.add(spotId);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  NewFind find(String id) =>
      NewFind(species: 'Steinpilz', foundOn: DateTime.utc(2026, 8, 10), clientId: id);

  NewSpotJob spotJob(String id) => NewSpotJob(
        id: id,
        createdAt: DateTime.utc(2026, 8, 10, 9),
        lat: 51.1,
        lng: 10.4,
        finds: [find('$id-f1')],
      );

  NewFindsJob findsJob(String id,
          {required String spotId, bool spotIsPending = false}) =>
      NewFindsJob(
        id: id,
        createdAt: DateTime.utc(2026, 8, 10, 10),
        spotId: spotId,
        spotIsPending: spotIsPending,
        finds: [find('$id-f1')],
      );

  ({OutboxRunner runner, FakeOutbox outbox, _RecordingRepository repository})
      setup(List<OutboxJob> jobs, {_RecordingRepository? repository}) {
    final outbox = FakeOutbox(jobs: jobs);
    final repo = repository ?? _RecordingRepository();
    return (
      runner: OutboxRunner(repository: repo, outbox: outbox),
      outbox: outbox,
      repository: repo,
    );
  }

  test('ein leerer Korb tut nichts', () async {
    final s = setup([]);
    expect(await s.runner.run(uid: 'me'), (sent: 0, remaining: 0, failed: 0));
  });

  test('alles geht raus und der Korb ist danach leer', () async {
    final s = setup([spotJob('a'), findsJob('b', spotId: 'server-x')]);
    final result = await s.runner.run(uid: 'me');

    expect(result.sent, 2);
    expect(result.remaining, 0);
    expect(s.outbox.jobs, isEmpty);
    expect(s.repository.spots, ['a']);
    expect(s.repository.finds, ['server-x']);
  });

  test('ein Fund am wartenden Spot bekommt dessen echte id', () async {
    // Der Kern des Ganzen: Beim Anlegen im Wald gibt es noch keine
    // Server-id, der Fund verweist auf den Auftrag.
    final s = setup([
      spotJob('a'),
      findsJob('b', spotId: 'a', spotIsPending: true),
    ]);
    await s.runner.run(uid: 'me');

    expect(s.repository.finds, ['server-a'],
        reason: 'ohne Auflösung liefe der Fund gegen die Auftragskennung');
    expect(s.outbox.jobs, isEmpty);
  });

  test('bleibt der Spot liegen, wartet sein Fund mit — mit aufgelöster id',
      () async {
    // Der Spot geht durch, der Fund scheitert am Netz. Beim nächsten Lauf
    // gibt es den Spot-Auftrag nicht mehr — die id MUSS also im Korb
    // stehen, sonst hinge der Fund für immer.
    final s = setup(
      [spotJob('a'), findsJob('b', spotId: 'a', spotIsPending: true)],
      repository: _RecordingRepository(
          onFinds: (_) => const SocketException('kein Netz')),
    );
    final result = await s.runner.run(uid: 'me');

    expect(result.sent, 1);
    expect(s.outbox.jobs, hasLength(1));
    final waiting = s.outbox.jobs.single as NewFindsJob;
    expect(waiting.spotId, 'server-a');
    expect(waiting.spotIsPending, isFalse);
    expect(waiting.failure, isNull, reason: 'kein Netz ist kein Fehlschlag');
  });

  test('kein Netz hält den Lauf an — der Rest bleibt in Reihenfolge liegen',
      () async {
    final s = setup(
      [spotJob('a'), spotJob('b'), spotJob('c')],
      repository: _RecordingRepository(
          onSpot: (id) =>
              id == 'b' ? const SocketException('kein Netz') : null),
    );
    final result = await s.runner.run(uid: 'me');

    expect(result.sent, 1);
    expect(s.repository.spots, ['a'],
        reason: 'nach dem Abriss darf nichts mehr versucht werden');
    expect(s.outbox.jobs.map((j) => j.id), ['b', 'c']);
    expect(s.outbox.jobs.every((j) => j.failure == null), isTrue);
    expect(s.outbox.jobs.first.attempts, 0,
        reason: 'ein Funkloch ist kein Fehlversuch, sonst verbrauchte eine '
            'Wanderung ohne Empfang alle fünf');
  });

  test('eine Ablehnung des Servers wird sofort endgültig', () async {
    final s = setup(
      [findsJob('b', spotId: 'gelöscht')],
      repository: _RecordingRepository(
          onFinds: (_) => const PostgrestException(
              message: 'insert violates foreign key', code: '23503')),
    );
    final result = await s.runner.run(uid: 'me');

    expect(result.sent, 0);
    expect(result.failed, 1);
    expect(s.outbox.jobs.single.failure, isNotNull,
        reason: 'wiederholen ändert an einer Ablehnung nichts');
  });

  test('ein unklarer Fehler wird fünfmal versucht, dann aufgegeben',
      () async {
    var jobs = <OutboxJob>[spotJob('a')];
    for (var round = 1; round <= OutboxRunner.maxAttempts; round++) {
      final s = setup(jobs,
          repository: _RecordingRepository(
              onSpot: (_) => StateError('irgendwas')));
      await s.runner.run(uid: 'me');
      jobs = s.outbox.jobs.toList();
      expect(jobs.single.attempts, round);
      expect(jobs.single.failure, round < OutboxRunner.maxAttempts
          ? isNull
          : isNotNull);
    }
  });

  test('ein aufgegebener Auftrag wird nicht erneut gesendet', () async {
    final s = setup([
      spotJob('a').copyWith(failure: 'Der Server mag das nicht.'),
      spotJob('b'),
    ]);
    final result = await s.runner.run(uid: 'me');

    expect(s.repository.spots, ['b'],
        reason: 'der aufgegebene blockiert die dahinter nicht — und läuft '
            'auch nicht selbst wieder an');
    expect(result.sent, 1);
    expect(result.failed, 1);
  });

  test('scheitert der Spot endgültig, scheitern seine Funde mit', () async {
    // Sonst versuchte der Fund es bei jeder Verbindung neu und fände
    // seinen Spot nie.
    final s = setup(
      [spotJob('a'), findsJob('b', spotId: 'a', spotIsPending: true)],
      repository: _RecordingRepository(
          onSpot: (_) => const PostgrestException(
              message: 'row-level security', code: '42501')),
    );
    final result = await s.runner.run(uid: 'me');

    expect(result.failed, 2);
    expect(s.repository.finds, isEmpty);
    expect(s.outbox.jobs.last.failure, contains('Spot'));
  });

  test('zwei Läufe gleichzeitig senden nichts doppelt', () async {
    // Verbindungsrückkehr und Banner-Tipp können zusammenfallen.
    final gate = Completer<void>();
    final repo = _RecordingRepository();
    final outbox = FakeOutbox(jobs: [spotJob('a')]);
    final slow = OutboxRunner(
        repository: _SlowRepository(repo, gate.future), outbox: outbox);

    final first = slow.run(uid: 'me');
    final second = await slow.run(uid: 'me');
    expect(second, (sent: 0, remaining: 0, failed: 0),
        reason: 'der zweite Lauf darf nicht mitmischen');
    gate.complete();
    expect((await first).sent, 1);
    expect(repo.spots, ['a']);
  });
}

/// Hält den ersten Sendevorgang an, bis das Tor geöffnet wird.
class _SlowRepository implements SpotRepository {
  _SlowRepository(this._inner, this._gate);

  final _RecordingRepository _inner;
  final Future<void> _gate;

  @override
  Future<String> addSpot({
    required double lat,
    required double lng,
    String? name,
    required List<NewFind> finds,
    String? clientId,
  }) async {
    await _gate;
    return _inner.addSpot(
        lat: lat, lng: lng, name: name, finds: finds, clientId: clientId);
  }

  @override
  Future<void> addFinds({
    required String spotId,
    required List<NewFind> finds,
  }) =>
      _inner.addFinds(spotId: spotId, finds: finds);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
