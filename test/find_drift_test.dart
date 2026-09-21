// Die Regel zu Fundstellen weit vom Spot (#475): abgeleitet aus Spot und
// Funden, bestätigt als Zeitpunkt am Spot.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/find_offset.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/find_position.dart';
import 'package:pilzbuddy/models/spot.dart';

void main() {
  Find findAt(String id, double lat, double lng, {DateTime? createdAt}) =>
      Find(
        id: id,
        spotId: 's',
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1),
        createdAt: createdAt,
        position: FindPosition.picked(lat: lat, lng: lng),
      );

  Spot spotWith(List<Find> finds, {DateTime? confirmedAt}) => Spot(
        id: 's',
        ownerId: 'me',
        lat: 50.5,
        lng: 7.5,
        finds: finds,
        offsetConfirmedAt: confirmedAt,
      );

  test('erst über 100 m gilt eine Fundstelle als abweichend — weiteste zuerst',
      () {
    final near = findAt('near', 50.5008, 7.5); // ~90 m
    final far = findAt('far', 50.5022, 7.5); // ~245 m
    final farther = findAt('farther', 50.5, 7.506); // ~425 m
    final none = Find(
        id: 'none', spotId: 's', foundOn: DateTime(2026, 9, 1));
    final drifting = driftingFinds(spotWith([near, none, far, farther]));
    expect(drifting.map((f) => f.id), ['farther', 'far']);
  });

  test('die Grenze ist die des Eintragens, keine zweite Zahl', () {
    expect(kFindFixMaxOffsetM, 100.0);
  });

  test('unbestätigt warnt; bestätigt schweigt; ein jüngerer Fund warnt wieder',
      () {
    final old = findAt('old', 50.5022, 7.5, createdAt: DateTime(2026, 9, 1));
    expect(spotDriftUnconfirmed(spotWith([old])), isTrue);
    final confirmed = DateTime(2026, 9, 10);
    expect(spotDriftUnconfirmed(spotWith([old], confirmedAt: confirmed)),
        isFalse);
    final young =
        findAt('young', 50.5, 7.506, createdAt: DateTime(2026, 9, 12));
    expect(
        spotDriftUnconfirmed(spotWith([old, young], confirmedAt: confirmed)),
        isTrue);
  });

  test('ein Fund ohne Alter warnt im Zweifel, auch nach Bestätigung', () {
    final unknownAge = findAt('u', 50.5022, 7.5);
    expect(
        spotDriftUnconfirmed(
            spotWith([unknownAge], confirmedAt: DateTime(2026, 9, 10))),
        isTrue);
  });

  test('ohne abweichende Fundstelle gibt es nichts zu bestätigen', () {
    expect(spotDriftUnconfirmed(spotWith([findAt('n', 50.5001, 7.5)])),
        isFalse);
  });
}
