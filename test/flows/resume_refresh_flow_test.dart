// Der Resume-Refresh (#316, zweite Hälfte): Ein kurzer Wechsel weg und
// zurück lädt NICHTS neu, ein echtes Zurückkehren die Supabase-Ziele,
// und die GitHub-Ziele höchstens einmal je Kadenz.
//
// Getestet wird das VERHALTEN — gezählte Abfragen an den Nähten —
// indem die Schwellen-Provider überschrieben und echte
// Lifecycle-Ereignisse durch die Binding geschickt werden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/update_check.dart';
import 'package:pilzbuddy/data/providers.dart';
import 'package:pilzbuddy/data/spot_repository.dart' show SpotsSnapshot;
import 'package:pilzbuddy/features/map/resume_refresh.dart';
import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Zählt die teuren Spot-Abfragen (volle `finds(*)`-Embeds).
class _CountingSpotRepository extends FakeSpotRepository {
  _CountingSpotRepository(super.backend);

  int fetches = 0;

  @override
  Future<SpotsSnapshot> fetchMySpots() {
    fetches++;
    return super.fetchMySpots();
  }
}

void main() {
  test('die Entscheidung selbst: kurz weg → nichts, lang weg → lokal, '
      'Kadenz um → auch Metadaten', () {
    ResumeRefresh decide(int awaySec, int sinceMetaMin) =>
        decideResumeRefresh(
          awayFor: Duration(seconds: awaySec),
          sinceMetaRefresh: Duration(minutes: sinceMetaMin),
          minAway: const Duration(seconds: 30),
          metaEvery: const Duration(hours: 1),
        );

    expect(decide(5, 999), ResumeRefresh.none,
        reason: 'Blick auf die Uhr — auch wenn die Meta-Kadenz längst '
            'um ist, wird ein kurzer Wechsel nie zum Anlass');
    expect(decide(29, 30), ResumeRefresh.none);
    expect(decide(30, 30), ResumeRefresh.local,
        reason: 'die Schwelle selbst zählt als weg gewesen');
    expect(decide(31, 59), ResumeRefresh.local);
    expect(decide(31, 60), ResumeRefresh.localAndMeta,
        reason: 'die Kadenz selbst zählt als um');
  });

  ({
    _CountingSpotRepository spots,
    List<int> metaCalls,
  }) seams(FakeBackend backend) {
    final spots = _CountingSpotRepository(backend);
    final metaCalls = <int>[];
    return (spots: spots, metaCalls: metaCalls);
  }

  Future<void> cycle(WidgetTester tester) async {
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
  }

  testWidgets('kurz weg und zurück: keine einzige neue Abfrage',
      (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    final s = seams(backend);
    await pumpApp(tester, backend, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(s.spots),
      updateInfoProvider.overrideWith((ref) {
        s.metaCalls.add(1);
        return Future.value(null);
      }),
      // Schwellen NICHT überschrieben: 30 s sind für einen Test-Zyklus
      // unerreichbar fern — genau der „Blick auf die Uhr"-Fall.
    ]);
    final spotsBefore = s.spots.fetches;
    final metaBefore = s.metaCalls.length;

    await cycle(tester);

    expect(s.spots.fetches, spotsBefore,
        reason: 'Unter der Mindest-Hintergrunddauer wird nichts '
            'neu geladen (#316: Blick auf die Uhr und zurück lud '
            'bisher sechs Provider, zwei davon über GitHub).');
    expect(s.metaCalls.length, metaBefore);
  });

  testWidgets('echtes Zurückkehren lädt Spots — die GitHub-Ziele nur, '
      'wenn ihre Kadenz um ist', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    final s = seams(backend);
    await pumpApp(tester, backend, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(s.spots),
      updateInfoProvider.overrideWith((ref) {
        s.metaCalls.add(1);
        return Future.value(null);
      }),
      // Jede Pause gilt als lang; die Meta-Kadenz bleibt bei 1 h.
      resumeRefreshMinAwayProvider.overrideWithValue(Duration.zero),
    ]);
    final spotsBefore = s.spots.fetches;
    final metaBefore = s.metaCalls.length;

    await cycle(tester);

    expect(s.spots.fetches, greaterThan(spotsBefore),
        reason: 'Nach echter Abwesenheit sollen neue Freundes-Spots '
            'und Anfragen ohne Neustart erscheinen — wie bisher.');
    expect(s.metaCalls.length, metaBefore,
        reason: 'Update-Check und Karten-Katalog liefen beim Start; '
            'innerhalb der Stunde geht KEIN weiterer GitHub-Aufruf '
            'raus.');
  });

  testWidgets('ist die Meta-Kadenz um, gehen die GitHub-Ziele einmal mit',
      (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    final s = seams(backend);
    await pumpApp(tester, backend, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(s.spots),
      updateInfoProvider.overrideWith((ref) {
        s.metaCalls.add(1);
        return Future.value(null);
      }),
      resumeRefreshMinAwayProvider.overrideWithValue(Duration.zero),
      resumeMetaRefreshEveryProvider.overrideWithValue(Duration.zero),
    ]);
    final metaBefore = s.metaCalls.length;

    await cycle(tester);

    expect(s.metaCalls.length, greaterThan(metaBefore),
        reason: 'Kadenz um ⇒ Update-Check und Katalog laufen wieder '
            'mit — die Drossel ist eine Kadenz, kein Abschalten.');
  });
}
