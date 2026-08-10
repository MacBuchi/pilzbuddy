// Wie der Ausgangskorb (#267) auf der Karte landet: Aufträge werden zu
// Spots und Funden, die sich nur durch `pending` unterscheiden.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/outbox.dart';
import 'package:pilzbuddy/data/outbox_view.dart';
import 'package:pilzbuddy/data/spot_repository.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

void main() {
  NewFind find(String id, {String? species = 'Steinpilz'}) => NewFind(
      species: species, foundOn: DateTime.utc(2026, 8, 10), clientId: id);

  Spot serverSpot(String id) => Spot(
        id: id,
        ownerId: 'me',
        lat: 51.0,
        lng: 10.0,
        finds: [
          Find(id: '$id-alt', spotId: id, foundOn: DateTime.utc(2026, 7, 1)),
        ],
      );

  NewSpotJob spotJob(String id, {List<NewFind>? finds}) => NewSpotJob(
        id: id,
        createdAt: DateTime.utc(2026, 8, 10, 9),
        lat: 51.5,
        lng: 10.5,
        name: 'Buchenhang',
        finds: finds ?? [find('$id-f1')],
      );

  NewFindsJob findsJob(String id,
          {required String spotId, bool spotIsPending = false}) =>
      NewFindsJob(
        id: id,
        createdAt: DateTime.utc(2026, 8, 10, 10),
        spotId: spotId,
        spotIsPending: spotIsPending,
        finds: [find('$id-f1', species: 'Pfifferling')],
      );

  test('ohne Aufträge bleibt die Liste, wie sie war', () {
    final spots = [serverSpot('s1')];
    expect(withPendingJobs(spots, const [], ownerId: 'me'), same(spots));
  });

  test('ein wartender Spot erscheint als Marker', () {
    // Ohne das legt man denselben Spot ein zweites Mal an — genau der
    // Fehler, den der Korb verhindern soll.
    final result =
        withPendingJobs([serverSpot('s1')], [spotJob('j1')], ownerId: 'me');

    expect(result, hasLength(2));
    final waiting = result.last;
    expect(waiting.pending, isTrue);
    expect(waiting.id, 'j1');
    expect(waiting.displayName, 'Buchenhang');
    expect(waiting.lat, closeTo(51.5, 1e-9));
    expect(waiting.isOwn, isTrue);
    expect(waiting.finds.single.pending, isTrue);
    expect(waiting.finds.single.id, 'j1-f1',
        reason: 'die Kennung des Auftrags ist genau der Wert, unter dem die '
            'Zeile später auf dem Server steht');
  });

  test('ein wartender Fund hängt sich an seinen Server-Spot', () {
    final result = withPendingJobs(
        [serverSpot('s1')], [findsJob('j2', spotId: 's1')],
        ownerId: 'me');

    expect(result, hasLength(1));
    expect(result.single.pending, isFalse,
        reason: 'der Spot selbst ist längst übertragen');
    expect(result.single.finds, hasLength(2));
    expect(result.single.finds.last.pending, isTrue);
    expect(result.single.finds.last.species, 'Pfifferling');
  });

  test('ein wartender Fund am wartenden Spot landet bei ihm', () {
    final result = withPendingJobs(
      [serverSpot('s1')],
      [spotJob('j1'), findsJob('j2', spotId: 'j1', spotIsPending: true)],
      ownerId: 'me',
    );

    expect(result, hasLength(2));
    expect(result.last.finds, hasLength(2));
    expect(result.last.finds.map((f) => f.species),
        containsAll(['Steinpilz', 'Pfifferling']));
  });

  test('ein Fund ohne seinen Spot verschwindet, statt irgendwo zu landen',
      () {
    // Der Spot-Auftrag wurde verworfen. Ihn an einer beliebigen Stelle
    // zu zeigen wäre schlimmer als ihn wegzulassen.
    final result = withPendingJobs(
      [serverSpot('s1')],
      [findsJob('j2', spotId: 'weg', spotIsPending: true)],
      ownerId: 'me',
    );

    expect(result, hasLength(1));
    expect(result.single.finds, hasLength(1));
  });

  test('ein Fund an einem gelöschten Server-Spot geht ebenfalls nicht auf', () {
    final result = withPendingJobs(
        [serverSpot('s1')], [findsJob('j2', spotId: 'gelöscht')],
        ownerId: 'me');

    expect(result, hasLength(1));
    expect(result.single.finds, hasLength(1));
  });

  test('ein Leergang bleibt ein Leergang', () {
    // Sonst zählte er nach dem Anlegen im Wald als Fund — und das ist
    // genau die Trennlinie, an der Statistik und Marker-Icon hängen.
    final result = withPendingJobs(
      const [],
      [
        spotJob('j1', finds: [
          NewFind.blank(foundOn: DateTime.utc(2026, 8, 10), clientId: 'b1'),
        ]),
      ],
      ownerId: 'me',
    );

    expect(result.single.finds.single.blank, isTrue);
    expect(result.single.findsSorted, isEmpty,
        reason: 'findsSorted siebt Leergänge aus — auch wartende');
    expect(result.single.entriesSorted, hasLength(1));
  });

  test('gezählt werden Einträge, nicht Aufträge', () {
    // „3 Einträge" ist das, was die Nutzerin eingetippt hat.
    final jobs = [
      spotJob('j1', finds: [find('a'), find('b')]),
      findsJob('j2', spotId: 's1'),
    ];
    expect(pendingEntryCount(jobs), 3);
  });

  test('gescheiterte Aufträge lassen sich herausfiltern', () {
    final jobs = [
      spotJob('j1'),
      spotJob('j2').copyWith(failure: 'Der Server mag das nicht.'),
    ];
    expect(failedJobs(jobs).map((j) => j.id), ['j2']);
  });
}
